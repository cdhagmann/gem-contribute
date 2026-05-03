# frozen_string_literal: true

require "stringio"

RSpec.describe GemContribute::Operations::Clone do
  let(:stdout) { StringIO.new }
  let(:tmpdir) { Dir.mktmpdir("gem-contribute-clone-op-") }
  let(:git) { instance_double(GemContribute::Git) }
  let(:adapter) { instance_double(GemContribute::HostAdapters::GitHubAdapter) }
  let(:project) do
    GemContribute::Project.new(
      gem_name: "sidekiq", host: "github.com",
      owner: "sidekiq", repo: "sidekiq", metadata: {}
    )
  end
  let(:operation) { described_class.new(git: git, stdout: stdout) }
  let(:target) { File.join(tmpdir, "sidekiq", "sidekiq") }

  before do
    allow(adapter).to receive(:clone_url).with("sidekiq", "sidekiq")
                                         .and_return("https://github.com/sidekiq/sidekiq.git")
    allow(git).to receive(:clone)
    allow(git).to receive(:add_remote)
  end

  after { FileUtils.rm_rf(tmpdir) }

  it "clones the fork into <root>/<owner>/<repo> and adds an upstream remote" do
    result = operation.call(adapter: adapter, project: project,
                            fork_clone_url: "https://github.com/alice/sidekiq.git",
                            root: tmpdir)

    expect(result).to eq(target)
    expect(git).to have_received(:clone).with("https://github.com/alice/sidekiq.git", target)
    expect(git).to have_received(:add_remote)
      .with(target, "upstream", "https://github.com/sidekiq/sidekiq.git")
    expect(stdout.string).to include("Cloning into #{target}")
  end

  it "reuses the existing clone when one is already present" do
    FileUtils.mkdir_p(File.join(target, ".git"))

    result = operation.call(adapter: adapter, project: project,
                            fork_clone_url: "https://github.com/alice/sidekiq.git",
                            root: tmpdir)

    expect(result).to eq(target)
    expect(git).not_to have_received(:clone)
    expect(git).to have_received(:add_remote)
      .with(target, "upstream", "https://github.com/sidekiq/sidekiq.git")
    expect(stdout.string).to include("Reusing existing clone at #{target}")
  end
end
