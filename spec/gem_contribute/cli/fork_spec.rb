# frozen_string_literal: true

require "stringio"

# rubocop:disable RSpec/MultipleMemoizedHelpers
RSpec.describe GemContribute::CLI::Fork do
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }
  let(:tmpdir) { Dir.mktmpdir("gem-contribute-fork-") }
  let(:store) { GemContribute::TokenStore.new(path: File.join(tmpdir, "auth.json")) }
  let(:resolver) { instance_double(GemContribute::Resolver) }
  let(:adapter) { instance_double(GemContribute::HostAdapters::GitHubAdapter) }
  let(:fork_clone) { instance_double(GemContribute::CLI::ForkClone) }
  let(:post_clone_hooks) { instance_double(GemContribute::CLI::PostCloneHooks, call: nil) }
  let(:clone_root) { File.join(tmpdir, "code", "oss") }
  let(:cli) do
    described_class.new(
      stdout: stdout, stderr: stderr,
      resolver: resolver, store: store,
      adapter_factory: ->(**) { adapter },
      clone_root: clone_root,
      fork_clone: fork_clone,
      post_clone_hooks: post_clone_hooks
    )
  end
  let(:project) do
    GemContribute::Project.new(
      gem_name: "sidekiq", host: "github.com",
      owner: "sidekiq", repo: "sidekiq", metadata: {}
    )
  end
  let(:target_path) { File.join(clone_root, "sidekiq", "sidekiq") }

  before do
    store.store("github.com", access_token: "gho_test")
    allow(resolver).to receive(:resolve).and_return(project)
  end

  after { FileUtils.rm_rf(tmpdir) }

  it "exits 2 with usage when no gem name is given" do
    expect(cli.run([])).to eq(2)
    expect(stderr.string).to include("Usage:")
  end

  it "exits 1 with the auth-login hint when no token is cached" do
    store.delete("github.com")

    expect(cli.run(["sidekiq"])).to eq(1)
    expect(stderr.string).to include("auth login")
  end

  it "exits 1 with an init hint when clone_root is nil" do
    cli_no_root = described_class.new(
      stdout: stdout, stderr: stderr,
      resolver: resolver, store: store,
      adapter_factory: ->(**) { adapter },
      clone_root: nil,
      fork_clone: fork_clone, post_clone_hooks: post_clone_hooks
    )

    expect(cli_no_root.run(["sidekiq"])).to eq(1)
    expect(stderr.string).to include("gem-contribute init")
  end

  it "exits 1 when the gem doesn't resolve to github.com" do
    other = GemContribute::Project.new(
      gem_name: "internal", host: :unknown, owner: nil, repo: nil, metadata: {}
    )
    allow(resolver).to receive(:resolve).and_return(other)

    expect(cli.run(["internal"])).to eq(1)
    expect(stderr.string).to include("only github.com is supported")
  end

  it "performs fork-clone and prints a summary on the default branch", :aggregate_failures do
    allow(adapter).to receive(:viewer_login).and_return("alice")
    allow(fork_clone).to receive(:call).with(adapter, project, "alice").and_return(target_path)

    expect(cli.run(["sidekiq"])).to eq(0)
    expect(stdout.string).to include("Forked and cloned")
    expect(stdout.string).to include("default branch")
    expect(stdout.string).to include(target_path)
    expect(post_clone_hooks).to have_received(:call).with(target_path, editor: false, ai_tool: false)
  end

  it "passes -e and -a flags through to post_clone_hooks" do
    allow(adapter).to receive(:viewer_login).and_return("alice")
    allow(fork_clone).to receive(:call).and_return(target_path)

    expect(cli.run(["sidekiq", "-e", "-a"])).to eq(0)
    expect(post_clone_hooks).to have_received(:call).with(target_path, editor: true, ai_tool: true)
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
