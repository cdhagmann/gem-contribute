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
  let(:pipeline) { instance_double(GemContribute::Operations::FixPipeline) }
  let(:clone_root) { File.join(tmpdir, "code", "oss") }
  let(:config) { GemContribute::Config.new(path: File.join(tmpdir, "config.yml")) }
  let(:cli) do
    described_class.new(
      stdout: stdout, stderr: stderr,
      resolver: resolver, store: store,
      adapter_factory: ->(**) { adapter },
      git: git, clone_root: clone_root,
      config: config, pipeline: pipeline
    )
  end

  let(:project) do
    GemContribute::Project.new(
      gem_name: "sidekiq", host: "github.com", owner: "sidekiq", repo: "sidekiq",
      metadata: {}
    )
  end
  let(:target) { File.join(clone_root, "sidekiq", "sidekiq") }
  let(:fork_data) do
    GemContribute::Operations::Fork::Result.new(
      clone_url: "https://github.com/alice/sidekiq.git",
      fork_url: "https://github.com/alice/sidekiq",
      upstream_url: "https://github.com/sidekiq/sidekiq",
      viewer: "alice", reused: false
    )
  end
  let(:clone_data) { GemContribute::Operations::Clone::Result.new(path: target, reused: false) }
  let(:branch_data) { GemContribute::Operations::Branch::Result.new(name: "gem-contribute/issue-1234", reused: false) }
  let(:pipeline_success) do
    Success(fork: fork_data, clone: clone_data, branch: branch_data, announce: Success(:posted))
  end

  before do
    store.store("github.com", access_token: "gho_test")
    allow(resolver).to receive(:resolve).and_return(project)
    allow(pipeline).to receive(:call).and_return(pipeline_success)
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
      pipeline: pipeline
    )
    expect(cli_no_clone_root.run(["sidekiq/1"])).to eq(1)
    expect(stderr.string).to include("gem-contribute init")
  end

  it "delegates to FixPipeline and prints a summary", :aggregate_failures do
    expect(cli.run(["sidekiq/1234"])).to eq(0)
    expect(pipeline).to have_received(:call).with(
      adapter: adapter, project: project, issue: "1234",
      root: clone_root, allow_announce: true
    )
    expect(stdout.string).to include(target)
    expect(stdout.string).to include("gem-contribute/issue-1234")
    expect(stdout.string).to include(fork_data.upstream_url)
    expect(stdout.string).to include(fork_data.fork_url)
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

  it "surfaces a Failure([:adapter_error, ...]) from the pipeline with a friendly message" do
    allow(pipeline).to receive(:call)
      .and_return(Failure([:adapter_error, "fork not reachable after 60s"]))

    expect(cli.run(["sidekiq/1"])).to eq(1)
    expect(stderr.string).to include("fix failed: fork not reachable")
  end

  it "surfaces a Failure(:unauthenticated) from the pipeline with the auth-login hint" do
    allow(pipeline).to receive(:call).and_return(Failure(:unauthenticated))

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
        config: config, pipeline: pipeline
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

  describe "announce gating (allow_announce passed to FixPipeline)" do
    it "passes allow_announce: true by default" do
      cli.run(["sidekiq/1234"])
      expect(pipeline).to have_received(:call)
        .with(hash_including(allow_announce: true))
    end

    it "passes allow_announce: false when --no-comment is given" do
      cli.run(["sidekiq/1234", "--no-comment"])
      expect(pipeline).to have_received(:call)
        .with(hash_including(allow_announce: false))
    end

    it "passes allow_announce: false when comment_on_fix is disabled in config" do
      config.set("comment_on_fix", "false")
      cli.run(["sidekiq/1234"])
      expect(pipeline).to have_received(:call)
        .with(hash_including(allow_announce: false))
    end

    it "passes allow_announce: false when a per-repo override turns it off" do
      File.write(File.join(tmpdir, "config.yml"),
                 YAML.dump("comment_on_fix" => true,
                           "comment_on_fix_overrides" => { "sidekiq/sidekiq" => false }))
      cli.run(["sidekiq/1234"])
      expect(pipeline).to have_received(:call)
        .with(hash_including(allow_announce: false))
    end
  end

  describe "announce outcome rendering" do
    it "prints the 'Posted' line when pipeline returns Success(:posted)" do
      cli.run(["sidekiq/1234"])
      expect(stdout.string).to include("Posted 'working on this' comment to issue #1234")
    end

    it "stays silent when pipeline returns Success(:skipped)" do
      allow(pipeline).to receive(:call).and_return(
        Success(fork: fork_data, clone: clone_data, branch: branch_data, announce: Success(:skipped))
      )
      cli.run(["sidekiq/1234"])
      expect(stdout.string).not_to include("Posted")
    end

    it "prints the soft-failure 'Note' on stderr when announce returned Failure" do
      allow(pipeline).to receive(:call).and_return(
        Success(fork: fork_data, clone: clone_data, branch: branch_data,
                announce: Failure([:announce_failed, "GitHub returned 422"]))
      )

      expect(cli.run(["sidekiq/1234"])).to eq(0)
      expect(stderr.string).to include("Note: couldn't post 'working on this' comment to issue #1234")
      expect(stderr.string).to include("GitHub returned 422")
      expect(stderr.string).to include("Continuing.")
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
