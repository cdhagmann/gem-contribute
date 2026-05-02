# frozen_string_literal: true

require "stringio"

RSpec.describe GemContribute::CLI::ForkClone do
  let(:stdout) { StringIO.new }
  let(:tmpdir) { Dir.mktmpdir("gem-contribute-forkclone-") }
  let(:adapter) { instance_double(GemContribute::HostAdapters::GitHubAdapter) }
  let(:git) { instance_double(GemContribute::CLI::Git) }
  let(:clone_root) { File.join(tmpdir, "code", "oss") }
  let(:fork_clone) do
    described_class.new(stdout: stdout, git: git, clone_root: clone_root, sleeper: ->(_) {})
  end
  let(:project) do
    GemContribute::Project.new(
      gem_name: "sidekiq", host: "github.com",
      owner: "sidekiq", repo: "sidekiq", metadata: {}
    )
  end
  let(:target) { File.join(clone_root, "sidekiq", "sidekiq") }

  before do
    allow(git).to receive(:clone)
    allow(git).to receive(:add_remote)
  end

  after { FileUtils.rm_rf(tmpdir) }

  context "when the user already has a fork" do
    before { allow(adapter).to receive(:already_forked?).with(project).and_return(true) }

    it "skips the fork API call and clones from the viewer's existing fork" do
      result = fork_clone.call(adapter, project, "alice")

      expect(result).to eq(target)
      expect(git).to have_received(:clone).with("https://github.com/alice/sidekiq.git", target)
      expect(git).to have_received(:add_remote)
        .with(target, "upstream", "https://github.com/sidekiq/sidekiq.git")
      expect(stdout.string).to include("already have a fork")
    end
  end

  context "when no fork exists yet" do
    before do
      allow(adapter).to receive(:already_forked?).with(project).and_return(false)
      allow(adapter).to receive(:fork).with(project)
                                      .and_return("clone_url" => "https://github.com/alice/sidekiq.git")
      allow(adapter).to receive(:fork_ready?).and_return(true)
    end

    it "POSTs the fork, polls until ready, clones, and adds upstream" do
      result = fork_clone.call(adapter, project, "alice")

      expect(result).to eq(target)
      expect(adapter).to have_received(:fork).with(project)
      expect(git).to have_received(:clone).with("https://github.com/alice/sidekiq.git", target)
    end
  end

  context "when the local clone already exists" do
    before do
      allow(adapter).to receive(:already_forked?).with(project).and_return(true)
      FileUtils.mkdir_p(File.join(target, ".git"))
    end

    it "reuses the existing clone without calling git.clone" do
      result = fork_clone.call(adapter, project, "alice")

      expect(result).to eq(target)
      expect(git).not_to have_received(:clone)
      expect(stdout.string).to include("Reusing existing clone")
    end
  end

  it "raises AdapterError when fork_ready? never returns true" do
    allow(adapter).to receive(:already_forked?).with(project).and_return(false)
    allow(adapter).to receive_messages(fork: { "clone_url" => "https://github.com/alice/sidekiq.git" },
                                       fork_ready?: false)

    expect { fork_clone.call(adapter, project, "alice") }
      .to raise_error(GemContribute::AdapterError, /not reachable/)
  end
end
