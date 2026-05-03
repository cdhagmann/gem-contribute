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
  let(:git) { instance_double(GemContribute::CLI::Git) }
  let(:post_clone_hooks) { instance_double(GemContribute::CLI::PostCloneHooks, call: nil) }
  let(:clone_root) { File.join(tmpdir, "code", "oss") }
  let(:project) do
    GemContribute::Project.new(
      gem_name: "sidekiq", host: "github.com",
      owner: "sidekiq", repo: "sidekiq", metadata: {}
    )
  end
  let(:target_path) { File.join(clone_root, "sidekiq", "sidekiq") }
  let(:cli) do
    described_class.new(
      stdout: stdout, stderr: stderr,
      resolver: resolver, store: store,
      adapter_factory: ->(**) { adapter },
      git: git, clone_root: clone_root,
      sleeper: ->(_s) {},
      post_clone_hooks: post_clone_hooks
    )
  end

  after { FileUtils.rm_rf(tmpdir) }

  describe "#run (CLI verb)" do
    before do
      store.store("github.com", access_token: "gho_test")
      allow(resolver).to receive(:resolve).and_return(project)
      # Stub the primitive on the test subject so CLI behavior tests don't
      # have to set up adapter/git plumbing — that's the primitive's spec.
      allow(cli).to receive(:call).and_return(target_path)
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
        sleeper: ->(_s) {},
        post_clone_hooks: post_clone_hooks
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

      expect(cli.run(["sidekiq"])).to eq(0)
      expect(stdout.string).to include("Forked and cloned")
      expect(stdout.string).to include("default branch")
      expect(stdout.string).to include(target_path)
      expect(post_clone_hooks).to have_received(:call).with(target_path, editor: false, ai_tool: false)
    end

    it "passes -e and -a flags through to post_clone_hooks" do
      allow(adapter).to receive(:viewer_login).and_return("alice")

      expect(cli.run(["sidekiq", "-e", "-a"])).to eq(0)
      expect(post_clone_hooks).to have_received(:call).with(target_path, editor: true, ai_tool: true)
    end

    it "accepts owner/repo form and skips RubyGems resolution" do
      allow(adapter).to receive(:viewer_login).and_return("alice")
      allow(cli).to receive(:call).and_return(File.join(clone_root, "rubyevents", "rubyevents"))

      expect(cli.run(["rubyevents/rubyevents"])).to eq(0)
      expect(resolver).not_to have_received(:resolve)
      expect(cli).to have_received(:call).with(
        adapter,
        have_attributes(owner: "rubyevents", repo: "rubyevents", host: "github.com"),
        "alice"
      )
    end
  end

  describe "#call (the primitive)" do
    before { allow(git).to receive_messages(clone: nil, add_remote: nil) }

    context "when the user already has a fork" do
      before { allow(adapter).to receive(:already_forked?).with(project).and_return(true) }

      it "skips the fork API call and clones from the viewer's existing fork" do
        result = cli.call(adapter, project, "alice")

        expect(result).to eq(target_path)
        expect(git).to have_received(:clone).with("https://github.com/alice/sidekiq.git", target_path)
        expect(git).to have_received(:add_remote)
          .with(target_path, "upstream", "https://github.com/sidekiq/sidekiq.git")
        expect(stdout.string).to include("already have a fork")
      end
    end

    context "when no fork exists yet" do
      before do
        allow(adapter).to receive_messages(
          already_forked?: false,
          fork: { "clone_url" => "https://github.com/alice/sidekiq.git" },
          fork_ready?: true
        )
      end

      it "POSTs the fork, polls until ready, clones, and adds upstream" do
        result = cli.call(adapter, project, "alice")

        expect(result).to eq(target_path)
        expect(adapter).to have_received(:fork).with(project)
        expect(git).to have_received(:clone).with("https://github.com/alice/sidekiq.git", target_path)
      end
    end

    context "when the local clone already exists" do
      before do
        allow(adapter).to receive(:already_forked?).with(project).and_return(true)
        FileUtils.mkdir_p(File.join(target_path, ".git"))
      end

      it "reuses the existing clone without calling git.clone" do
        result = cli.call(adapter, project, "alice")

        expect(result).to eq(target_path)
        expect(git).not_to have_received(:clone)
        expect(stdout.string).to include("Reusing existing clone")
      end
    end

    it "raises AdapterError when fork_ready? never returns true" do
      allow(adapter).to receive_messages(
        already_forked?: false,
        fork: { "clone_url" => "https://github.com/alice/sidekiq.git" },
        fork_ready?: false
      )

      expect { cli.call(adapter, project, "alice") }
        .to raise_error(GemContribute::AdapterError, /not reachable/)
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
