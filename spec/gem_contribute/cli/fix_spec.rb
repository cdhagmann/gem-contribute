# frozen_string_literal: true

require "stringio"
require "dry/monads"

# rubocop:disable RSpec/MultipleMemoizedHelpers
RSpec.describe GemContribute::CLI::Fix do
  include Dry::Monads[:result]

  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }
  let(:tmpdir) { Dir.mktmpdir("gem-contribute-fix-") }
  let(:store) { GemContribute::TokenStore.new(path: File.join(tmpdir, "auth.json")) }
  let(:resolver) { instance_double(GemContribute::Resolver) }
  let(:adapter) { instance_double(GemContribute::HostAdapters::GitHubAdapter) }
  let(:git) { instance_double(GemContribute::Git) }
  let(:fork_cli) { instance_double(GemContribute::CLI::Fork) }
  let(:clone_root) { File.join(tmpdir, "code", "oss") }
  let(:config) { GemContribute::Config.new(path: File.join(tmpdir, "config.yml")) }
  let(:cli) do
    described_class.new(
      stdout: stdout, stderr: stderr,
      resolver: resolver, store: store,
      adapter_factory: ->(**) { adapter },
      git: git, clone_root: clone_root,
      config: config, fork: fork_cli
    )
  end

  let(:project) do
    GemContribute::Project.new(
      gem_name: "sidekiq", host: "github.com", owner: "sidekiq", repo: "sidekiq",
      metadata: {}
    )
  end
  let(:target) { File.join(clone_root, "sidekiq", "sidekiq") }
  let(:fork_info) do
    GemContribute::Operations::Fork::Result.new(
      clone_url: "https://github.com/alice/sidekiq.git",
      fork_url: "https://github.com/alice/sidekiq",
      upstream_url: "https://github.com/sidekiq/sidekiq",
      viewer: "alice", reused: false
    )
  end

  before do
    store.store("github.com", access_token: "gho_test")
    allow(resolver).to receive(:resolve).and_return(project)
    allow(git).to receive(:checkout_branch)
    allow(git).to receive(:branch_exists?).and_return(false)
    allow(fork_cli).to receive(:bootstrap).with(adapter, project).and_return(Success([target, fork_info]))
    allow(GemContribute::CLI::IssueAnnouncer).to receive(:announce_working).and_return(:posted)
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
      fork: fork_cli
    )
    expect(cli_no_clone_root.run(["sidekiq/1"])).to eq(1)
    expect(stderr.string).to include("gem-contribute init")
  end

  it "delegates the fork+clone bootstrap and then branches", :aggregate_failures do
    expect(cli.run(["sidekiq/1234"])).to eq(0)
    expect(fork_cli).to have_received(:bootstrap).with(adapter, project)
    expect(git).to have_received(:checkout_branch).with(target, "gem-contribute/issue-1234")
    expect(stdout.string).to include(target)
    expect(stdout.string).to include("gem-contribute/issue-1234")
    expect(stdout.string).to include(fork_info.upstream_url)
    expect(stdout.string).to include(fork_info.fork_url)
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

  it "surfaces a Failure([:adapter_error, ...]) from the bootstrap with a friendly message" do
    allow(fork_cli).to receive(:bootstrap)
      .and_return(Failure([:adapter_error, "fork not reachable after 60s"]))

    expect(cli.run(["sidekiq/1"])).to eq(1)
    expect(stderr.string).to include("fix failed: fork not reachable")
  end

  it "surfaces a Failure(:unauthenticated) from the bootstrap with the auth-login hint" do
    allow(fork_cli).to receive(:bootstrap).and_return(Failure(:unauthenticated))

    expect(cli.run(["sidekiq/1"])).to eq(1)
    expect(stderr.string).to include("auth login")
  end

  describe "with -e and -a flags" do
    let(:hooks) { instance_double(GemContribute::CLI::PostCloneHooks, call: nil) }
    let(:cli_with_hooks) do
      described_class.new(
        stdout: stdout, stderr: stderr,
        resolver: resolver, store: store,
        adapter_factory: ->(**) { adapter },
        git: git, clone_root: clone_root,
        post_clone_hooks: hooks,
        config: config, fork: fork_cli
      )
    end

    it "passes parsed flags to post_clone_hooks" do
      expect(cli_with_hooks.run(["sidekiq/1", "-e", "-a"])).to eq(0)
      expect(hooks).to have_received(:call).with(target, editor: true, ai_tool: true)
    end

    it "parses flags placed before the target" do
      expect(cli_with_hooks.run(["-e", "sidekiq/1"])).to eq(0)
      expect(hooks).to have_received(:call).with(target, editor: true, ai_tool: false)
    end

    it "calls hooks with both flags false when neither flag is given" do
      expect(cli_with_hooks.run(["sidekiq/1"])).to eq(0)
      expect(hooks).to have_received(:call).with(target, editor: false, ai_tool: false)
    end
  end

  describe "issue comment integration" do
    it "announces working on the issue by default" do
      expect(cli.run(["sidekiq/1234"])).to eq(0)
      expect(GemContribute::CLI::IssueAnnouncer).to have_received(:announce_working)
        .with(adapter: adapter, project: project, issue: "1234",
              stdout: stdout, stderr: stderr)
    end

    it "skips the announce when --no-comment is passed" do
      expect(cli.run(["sidekiq/1234", "--no-comment"])).to eq(0)
      expect(GemContribute::CLI::IssueAnnouncer).not_to have_received(:announce_working)
    end

    it "skips the announce when the issue's branch already exists locally (resuming)" do
      FileUtils.mkdir_p(File.join(target, ".git"))
      allow(git).to receive(:branch_exists?).with(target, "gem-contribute/issue-1234").and_return(true)

      expect(cli.run(["sidekiq/1234"])).to eq(0)
      expect(GemContribute::CLI::IssueAnnouncer).not_to have_received(:announce_working)
    end

    it "announces when the clone exists but the branch for this issue is new" do
      # User worked on issue 4 yesterday (clone exists), now starting issue 1234 fresh.
      FileUtils.mkdir_p(File.join(target, ".git"))
      allow(git).to receive(:branch_exists?).with(target, "gem-contribute/issue-1234").and_return(false)

      expect(cli.run(["sidekiq/1234"])).to eq(0)
      expect(GemContribute::CLI::IssueAnnouncer).to have_received(:announce_working)
    end

    it "skips the announce when the viewer owns the upstream" do
      owned = GemContribute::Project.new(
        gem_name: "rubocop", host: "github.com",
        owner: "alice", repo: "rubocop", metadata: {}
      )
      allow(resolver).to receive(:resolve).and_return(owned)
      owned_target = File.join(clone_root, "alice", "rubocop")
      allow(fork_cli).to receive(:bootstrap).with(adapter, owned).and_return(Success([owned_target, fork_info]))

      expect(cli.run(["rubocop/1234"])).to eq(0)
      expect(GemContribute::CLI::IssueAnnouncer).not_to have_received(:announce_working)
    end

    context "when comment_on_fix is false in config" do
      before { config.set("comment_on_fix", "false") }

      it "skips the announce" do
        expect(cli.run(["sidekiq/1234"])).to eq(0)
        expect(GemContribute::CLI::IssueAnnouncer).not_to have_received(:announce_working)
      end
    end

    context "when a per-repo override turns it off" do
      before do
        File.write(File.join(tmpdir, "config.yml"),
                   YAML.dump("comment_on_fix" => true,
                             "comment_on_fix_overrides" => { "sidekiq/sidekiq" => false }))
      end

      it "skips the announce" do
        expect(cli.run(["sidekiq/1234"])).to eq(0)
        expect(GemContribute::CLI::IssueAnnouncer).not_to have_received(:announce_working)
      end
    end
  end
  # rubocop:enable RSpec/MultipleMemoizedHelpers
end
