# frozen_string_literal: true

require "stringio"

RSpec.describe GemContribute::CLI::Fix do
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }
  let(:tmpdir) { Dir.mktmpdir("gem-contribute-fix-") }
  let(:store) { GemContribute::TokenStore.new(path: File.join(tmpdir, "auth.json")) }
  let(:resolver) { instance_double(GemContribute::Resolver) }
  let(:adapter) { instance_double(GemContribute::HostAdapters::GitHubAdapter) }
  let(:git) { instance_double(GemContribute::CLI::Git) }
  let(:clone_root) { File.join(tmpdir, "code", "oss") }
  let(:cli) do
    described_class.new(
      stdout: stdout, stderr: stderr,
      resolver: resolver, store: store,
      adapter_factory: ->(**) { adapter },
      git: git, clone_root: clone_root,
      sleeper: ->(_s) {}
    )
  end

  let(:project) do
    GemContribute::Project.new(
      gem_name: "sidekiq", host: "github.com", owner: "sidekiq", repo: "sidekiq",
      metadata: {}
    )
  end

  before do
    store.store("github.com", access_token: "gho_test")
    allow(resolver).to receive(:resolve).and_return(project)
    allow(git).to receive(:clone)
    allow(git).to receive(:checkout_branch)
    allow(git).to receive(:add_remote)
  end

  after { FileUtils.rm_rf(tmpdir) }

  it "exits with usage error when the argument is missing or malformed" do
    expect(cli.run([])).to eq(2)
    expect(stderr.string).to include("Usage:")

    expect(cli.run(["sidekiq"])).to eq(2)
  end

  it "exits 1 with the auth-login hint when no token is cached" do
    store.delete("github.com")

    expect(cli.run(["sidekiq/1234"])).to eq(1)
    expect(stderr.string).to include("auth login")
  end

  it "exits 1 with an init hint when clone_root is nil" do
    cli_no_clone_root = described_class.new(
      stdout: stdout, stderr: stderr,
      resolver: resolver, store: store,
      adapter_factory: ->(**) { adapter },
      git: git, clone_root: nil,
      sleeper: ->(_s) {}
    )
    expect(cli_no_clone_root.run(["sidekiq/1"])).to eq(1)
    expect(stderr.string).to include("gem-contribute init")
  end

  it "forks, polls until ready, clones, and branches when no fork exists yet", :aggregate_failures do
    allow(adapter).to receive(:viewer_login).and_return("alice")
    allow(adapter).to receive(:already_forked?).with(project).and_return(false)
    allow(adapter).to receive(:fork).with(project).and_return(
      "name" => "sidekiq",
      "owner" => { "login" => "alice" },
      "clone_url" => "https://github.com/alice/sidekiq.git"
    )
    # First poll says still propagating, second says ready.
    allow(adapter).to receive(:fork_ready?).and_return(false, true)

    target = File.join(clone_root, "sidekiq", "sidekiq")

    expect(cli.run(["sidekiq/1234"])).to eq(0)
    expect(git).to have_received(:clone).with("https://github.com/alice/sidekiq.git", target)
    expect(git).to have_received(:checkout_branch).with(target, "gem-contribute/issue-1234")
    expect(git).to have_received(:add_remote).with(target, "upstream", "https://github.com/sidekiq/sidekiq.git")
    expect(stdout.string).to include("Forking sidekiq/sidekiq")
    expect(stdout.string).to include(target)
    expect(stdout.string).to include("gem-contribute/issue-1234")
    expect(adapter).to have_received(:fork).once
  end

  it "skips fork creation but still clones and branches when the user already has a fork" do
    allow(adapter).to receive(:viewer_login).and_return("alice")
    allow(adapter).to receive(:already_forked?).with(project).and_return(true)
    allow(adapter).to receive(:fork)

    target = File.join(clone_root, "sidekiq", "sidekiq")

    expect(cli.run(["sidekiq/99"])).to eq(0)
    expect(git).to have_received(:clone).with("https://github.com/alice/sidekiq.git", target)
    expect(git).to have_received(:checkout_branch).with(target, "gem-contribute/issue-99")
    expect(adapter).not_to have_received(:fork)
    expect(stdout.string).to include("already have a fork")
  end

  it "reuses an existing local clone instead of re-cloning" do
    allow(adapter).to receive(:viewer_login).and_return("alice")
    allow(adapter).to receive(:already_forked?).with(project).and_return(true)

    target = File.join(clone_root, "sidekiq", "sidekiq")
    FileUtils.mkdir_p(File.join(target, ".git"))

    expect(cli.run(["sidekiq/7"])).to eq(0)
    expect(git).not_to have_received(:clone)
    expect(git).to have_received(:checkout_branch).with(target, "gem-contribute/issue-7")
    expect(stdout.string).to include("Reusing existing clone")
  end

  it "fails clearly if the gem doesn't resolve to github.com" do
    other = GemContribute::Project.new(
      gem_name: "internal", host: :unknown, owner: nil, repo: nil,
      metadata: { reason: :unknown_host }
    )
    allow(resolver).to receive(:resolve).and_return(other)

    expect(cli.run(["internal/1"])).to eq(1)
    expect(stderr.string).to include("only github.com is supported")
  end

  it "fails after the readiness timeout if fork_ready? never returns true" do
    allow(adapter).to receive(:already_forked?).with(project).and_return(false)
    allow(adapter).to receive(:fork).with(project).and_return("clone_url" => "https://github.com/alice/sidekiq.git")
    allow(adapter).to receive_messages(viewer_login: "alice", fork_ready?: false)

    expect(cli.run(["sidekiq/1"])).to eq(1)
    expect(stderr.string).to include("fork not reachable")
  end

  # rubocop:disable RSpec/MultipleMemoizedHelpers
  describe "with -e and -a flags" do
    let(:hooks) { instance_double(GemContribute::CLI::PostCloneHooks, call: nil) }
    let(:cli_with_hooks) do
      described_class.new(
        stdout: stdout, stderr: stderr,
        resolver: resolver, store: store,
        adapter_factory: ->(**) { adapter },
        git: git, clone_root: clone_root,
        sleeper: ->(_s) {},
        post_clone_hooks: hooks
      )
    end
    let(:target_path) { File.join(clone_root, "sidekiq", "sidekiq") }

    before do
      allow(adapter).to receive(:viewer_login).and_return("alice")
      allow(adapter).to receive(:already_forked?).with(project).and_return(true)
    end

    it "passes parsed flags to post_clone_hooks" do
      expect(cli_with_hooks.run(["sidekiq/1", "-e", "-a"])).to eq(0)
      expect(hooks).to have_received(:call).with(target_path, editor: true, ai_tool: true)
    end

    it "parses flags placed before the target" do
      expect(cli_with_hooks.run(["-e", "sidekiq/1"])).to eq(0)
      expect(hooks).to have_received(:call).with(target_path, editor: true, ai_tool: false)
    end

    it "calls hooks with both flags false when neither flag is given" do
      expect(cli_with_hooks.run(["sidekiq/1"])).to eq(0)
      expect(hooks).to have_received(:call).with(target_path, editor: false, ai_tool: false)
    end
  end
  # rubocop:enable RSpec/MultipleMemoizedHelpers
end
