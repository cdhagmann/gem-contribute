# frozen_string_literal: true

require "stringio"
require "dry/monads"

# rubocop:disable RSpec/MultipleMemoizedHelpers
RSpec.describe GemContribute::CLI::Fork do
  include Dry::Monads[:result]

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
      viewer: "alice", reused: false, owned_upstream: false
    )
  end
  let(:clone_info) { GemContribute::Operations::Clone::Result.new(path: target_path, reused: false) }
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
      allow(fork_op).to receive(:call).and_return(Success(fork_info))
      allow(clone_op).to receive(:call).and_return(Success(clone_info))
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
      expect(stdout.string).to include("Forking sidekiq/sidekiq")
      expect(stdout.string).to include("Forked → alice/sidekiq")
      expect(stdout.string).to include("Cloned into #{target_path}")
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

    it "prints a cd-then-edit hint when no -e/-a flag is passed", :aggregate_failures do
      expect(cli.run(["sidekiq"])).to eq(0)
      expect(stdout.string).to include("Next: cd #{target_path} && $EDITOR .")
      expect(stdout.string).to include("`gem-contribute fix sidekiq/<issue#>`")
    end

    it "drops the cd-then-edit hint when -e or -a is passed", :aggregate_failures do
      expect(cli.run(["sidekiq", "-e"])).to eq(0)
      expect(stdout.string).not_to include("cd ")
      expect(stdout.string).not_to include("$EDITOR")
      expect(stdout.string).to include("Next: pick an issue and run `gem-contribute fix sidekiq/<issue#>`")
    end

    it "accepts owner/repo form and skips RubyGems resolution" do
      expect(cli.run(["rubyevents/rubyevents"])).to eq(0)
      expect(resolver).not_to have_received(:resolve)
      expect(fork_op).to have_received(:call).with(
        adapter: adapter,
        project: have_attributes(owner: "rubyevents", repo: "rubyevents", host: "github.com")
      )
    end

    it "exits 1 with an adapter-error message when fork_op returns Failure(:adapter_error, ...)" do
      allow(fork_op).to receive(:call).and_return(Failure([:adapter_error, "rate limit exceeded"]))

      expect(cli.run(["sidekiq"])).to eq(1)
      expect(stderr.string).to include("fork failed: rate limit exceeded")
    end

    it "exits 1 with the auth-login hint when fork_op returns Failure(:unauthenticated)" do
      allow(fork_op).to receive(:call).and_return(Failure(:unauthenticated))

      expect(cli.run(["sidekiq"])).to eq(1)
      expect(stderr.string).to include("auth login")
    end
  end

  describe "#bootstrap (the shared primitive)" do
    it "calls the fork op then the clone op and returns Success([path, fork_info])" do
      allow(fork_op).to receive(:call).and_return(Success(fork_info))
      allow(clone_op).to receive(:call).and_return(Success(clone_info))

      result = cli.bootstrap(adapter, project)

      expect(result).to be_success
      path, info = result.value!
      expect(path).to eq(target_path)
      expect(info).to eq(fork_info)
      expect(clone_op).to have_received(:call).with(
        adapter: adapter, project: project,
        fork_clone_url: fork_info.clone_url, root: clone_root
      )
    end

    it "short-circuits and returns the fork_op Failure without calling clone_op" do
      allow(fork_op).to receive(:call).and_return(Failure([:adapter_error, "fork timed out"]))
      allow(clone_op).to receive(:call)

      result = cli.bootstrap(adapter, project)

      expect(result).to eq(Failure([:adapter_error, "fork timed out"]))
      expect(clone_op).not_to have_received(:call)
    end

    it "propagates a clone_op Failure" do
      allow(fork_op).to receive(:call).and_return(Success(fork_info))
      allow(clone_op).to receive(:call).and_return(Failure([:adapter_error, "git clone failed"]))

      result = cli.bootstrap(adapter, project)

      expect(result).to eq(Failure([:adapter_error, "git clone failed"]))
    end

    it "prints reuse messaging when both ops report reused: true" do
      reused_fork = fork_info.with(reused: true)
      reused_clone = GemContribute::Operations::Clone::Result.new(path: target_path, reused: true)
      allow(fork_op).to receive(:call).and_return(Success(reused_fork))
      allow(clone_op).to receive(:call).and_return(Success(reused_clone))

      cli.bootstrap(adapter, project)

      expect(stdout.string).to include("Reusing existing fork at alice/sidekiq")
      expect(stdout.string).to include("Reusing existing clone at #{target_path}")
    end

    it "prints owned-upstream message when viewer is the project owner" do
      owned_fork = fork_info.with(reused: true, owned_upstream: true)
      allow(fork_op).to receive(:call).and_return(Success(owned_fork))
      allow(clone_op).to receive(:call).and_return(Success(clone_info))

      cli.bootstrap(adapter, project)

      expect(stdout.string).to include("You own sidekiq/sidekiq upstream. Cloning directly; no fork needed.")
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
