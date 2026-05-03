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
  let(:git) { instance_double(GemContribute::Git) }
  let(:fork_op) { instance_double(GemContribute::Operations::Fork) }
  let(:clone_op) { instance_double(GemContribute::Operations::Clone) }
  let(:post_clone_hooks) { instance_double(GemContribute::CLI::PostCloneHooks, call: nil) }
  let(:clone_root) { File.join(tmpdir, "code", "oss") }
  let(:project) do
    GemContribute::Project.new(
      gem_name: "sidekiq", host: "github.com",
      owner: "sidekiq", repo: "sidekiq", metadata: {}
    )
  end
  let(:target_path) { File.join(clone_root, "sidekiq", "sidekiq") }
  let(:fork_info) do
    GemContribute::Operations::Fork::Result.new(
      clone_url: "https://github.com/alice/sidekiq.git",
      fork_url: "https://github.com/alice/sidekiq",
      upstream_url: "https://github.com/sidekiq/sidekiq",
      viewer: "alice", reused: false
    )
  end
  let(:cli) do
    described_class.new(
      stdout: stdout, stderr: stderr,
      resolver: resolver, store: store,
      adapter_factory: ->(**) { adapter },
      git: git, clone_root: clone_root,
      post_clone_hooks: post_clone_hooks,
      fork_op: fork_op, clone_op: clone_op
    )
  end

  after { FileUtils.rm_rf(tmpdir) }

  describe "#run (CLI verb)" do
    before do
      store.store("github.com", access_token: "gho_test")
      allow(resolver).to receive(:resolve).and_return(project)
      allow(fork_op).to receive(:call).and_return(fork_info)
      allow(clone_op).to receive(:call).and_return(target_path)
    end

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
        git: git, clone_root: nil,
        post_clone_hooks: post_clone_hooks,
        fork_op: fork_op, clone_op: clone_op
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

    it "delegates to the Operations primitives and prints a summary on the default branch",
       :aggregate_failures do
      expect(cli.run(["sidekiq"])).to eq(0)

      expect(fork_op).to have_received(:call).with(adapter: adapter, project: project)
      expect(clone_op).to have_received(:call).with(
        adapter: adapter, project: project,
        fork_clone_url: fork_info.clone_url, root: clone_root
      )
      expect(stdout.string).to include("Forked and cloned")
      expect(stdout.string).to include("default branch")
      expect(stdout.string).to include(target_path)
      expect(stdout.string).to include(fork_info.fork_url)
      expect(stdout.string).to include(fork_info.upstream_url)
      expect(post_clone_hooks).to have_received(:call).with(target_path, editor: false, ai_tool: false)
    end

    it "passes -e and -a flags through to post_clone_hooks" do
      expect(cli.run(["sidekiq", "-e", "-a"])).to eq(0)
      expect(post_clone_hooks).to have_received(:call).with(target_path, editor: true, ai_tool: true)
    end

    it "accepts owner/repo form and skips RubyGems resolution" do
      expect(cli.run(["rubyevents/rubyevents"])).to eq(0)
      expect(resolver).not_to have_received(:resolve)
      expect(fork_op).to have_received(:call).with(
        adapter: adapter,
        project: have_attributes(owner: "rubyevents", repo: "rubyevents", host: "github.com")
      )
    end
  end

  describe "#bootstrap (the shared primitive)" do
    it "calls the fork op then the clone op and returns [path, fork_info]" do
      allow(fork_op).to receive(:call).and_return(fork_info)
      allow(clone_op).to receive(:call).and_return(target_path)

      path, info = cli.bootstrap(adapter, project)

      expect(path).to eq(target_path)
      expect(info).to eq(fork_info)
      expect(clone_op).to have_received(:call).with(
        adapter: adapter, project: project,
        fork_clone_url: fork_info.clone_url, root: clone_root
      )
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
