# frozen_string_literal: true

require "stringio"

RSpec.describe GemContribute::Operations::Fork do
  let(:stdout) { StringIO.new }
  let(:adapter) { instance_double(GemContribute::HostAdapters::GitHubAdapter) }
  let(:project) do
    GemContribute::Project.new(
      gem_name: "sidekiq", host: "github.com",
      owner: "sidekiq", repo: "sidekiq", metadata: {}
    )
  end
  let(:operation) { described_class.new(stdout: stdout) }

  before do
    allow(adapter).to receive(:repo_url).with("sidekiq", "sidekiq")
                                        .and_return("https://github.com/sidekiq/sidekiq")
  end

  it "delegates to adapter.fork and packages the result with upstream_url" do
    allow(adapter).to receive(:fork).with(project).and_return(
      GemContribute::HostAdapter::ForkResult.new(
        clone_url: "https://github.com/alice/sidekiq.git",
        fork_url: "https://github.com/alice/sidekiq",
        viewer: "alice", reused: false
      )
    )

    result = operation.call(adapter: adapter, project: project)

    expect(result).to have_attributes(
      clone_url: "https://github.com/alice/sidekiq.git",
      fork_url: "https://github.com/alice/sidekiq",
      upstream_url: "https://github.com/sidekiq/sidekiq",
      viewer: "alice", reused: false
    )
  end

  it "prints a 'Forked' line when the fork was just created" do
    allow(adapter).to receive(:fork).and_return(
      GemContribute::HostAdapter::ForkResult.new(
        clone_url: "x", fork_url: "y", viewer: "alice", reused: false
      )
    )

    operation.call(adapter: adapter, project: project)
    expect(stdout.string).to include("Forking sidekiq/sidekiq")
    expect(stdout.string).to include("Forked → alice/sidekiq")
  end

  it "prints a 'Reusing existing fork' line when the fork already existed" do
    allow(adapter).to receive(:fork).and_return(
      GemContribute::HostAdapter::ForkResult.new(
        clone_url: "x", fork_url: "y", viewer: "alice", reused: true
      )
    )

    operation.call(adapter: adapter, project: project)
    expect(stdout.string).to include("Reusing existing fork at alice/sidekiq")
  end
end
