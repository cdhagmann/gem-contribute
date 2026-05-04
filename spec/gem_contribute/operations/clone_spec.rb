# frozen_string_literal: true

require "dry/monads"

RSpec.describe GemContribute::Operations::Clone do
  include Dry::Monads[:result]

  let(:tmpdir) { Dir.mktmpdir("gem-contribute-clone-op-") }
  let(:git) { instance_double(GemContribute::Git) }
  let(:adapter) { instance_double(GemContribute::HostAdapters::GitHubAdapter) }
  let(:project) do
    GemContribute::Project.new(
      gem_name: "sidekiq", host: "github.com",
      owner: "sidekiq", repo: "sidekiq", metadata: {}
    )
  end
  let(:operation) { described_class.new(git: git) }
  let(:target) { File.join(tmpdir, "sidekiq", "sidekiq") }

  before do
    allow(adapter).to receive(:clone_url).with("sidekiq", "sidekiq")
                                         .and_return("https://github.com/sidekiq/sidekiq.git")
    allow(git).to receive(:clone)
    allow(git).to receive(:add_remote)
  end

  after { FileUtils.rm_rf(tmpdir) }

  it "clones into <root>/<owner>/<repo>, adds an upstream remote, returns Success(reused: false)" do
    result = operation.call(adapter: adapter, project: project,
                            fork_clone_url: "https://github.com/alice/sidekiq.git",
                            root: tmpdir)

    expect(result).to be_success
    expect(result.value!).to have_attributes(path: target, reused: false)
    expect(git).to have_received(:clone).with("https://github.com/alice/sidekiq.git", target)
    expect(git).to have_received(:add_remote)
      .with(target, "upstream", "https://github.com/sidekiq/sidekiq.git")
  end

  it "returns Success(reused: true) and skips git.clone when the clone already exists" do
    FileUtils.mkdir_p(File.join(target, ".git"))

    result = operation.call(adapter: adapter, project: project,
                            fork_clone_url: "https://github.com/alice/sidekiq.git",
                            root: tmpdir)

    expect(result).to be_success
    expect(result.value!).to have_attributes(path: target, reused: true)
    expect(git).not_to have_received(:clone)
    expect(git).to have_received(:add_remote)
      .with(target, "upstream", "https://github.com/sidekiq/sidekiq.git")
  end

  it "returns Failure([:adapter_error, message]) when git raises AdapterError" do
    allow(git).to receive(:clone).and_raise(GemContribute::AdapterError, "git clone failed: 128")

    result = operation.call(adapter: adapter, project: project,
                            fork_clone_url: "https://github.com/alice/sidekiq.git",
                            root: tmpdir)

    expect(result).to eq(Failure([:adapter_error, "git clone failed: 128"]))
  end
end
