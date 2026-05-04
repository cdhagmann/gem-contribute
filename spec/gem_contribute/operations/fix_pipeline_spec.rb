# frozen_string_literal: true

require "dry/monads"

RSpec.describe GemContribute::Operations::FixPipeline do
  include Dry::Monads[:result]

  let(:adapter) { instance_double(GemContribute::HostAdapters::GitHubAdapter) }
  let(:project) do
    GemContribute::Project.new(
      gem_name: "sidekiq", host: "github.com",
      owner: "sidekiq", repo: "sidekiq", metadata: {}
    )
  end

  let(:fork_op) { instance_double(GemContribute::Operations::Fork) }
  let(:clone_op) { instance_double(GemContribute::Operations::Clone) }
  let(:branch_op) { instance_double(GemContribute::Operations::Branch) }
  let(:announce_op) { instance_double(GemContribute::Operations::Announce) }

  let(:fork_result) do
    GemContribute::Operations::Fork::Result.new(
      clone_url: "https://github.com/alice/sidekiq.git",
      fork_url: "https://github.com/alice/sidekiq",
      upstream_url: "https://github.com/sidekiq/sidekiq",
      viewer: "alice", reused: false
    )
  end
  let(:clone_result) do
    GemContribute::Operations::Clone::Result.new(path: "/clones/sidekiq/sidekiq", reused: false)
  end
  let(:branch_result) { GemContribute::Operations::Branch::Result.new(name: "gem-contribute/issue-1234") }

  let(:pipeline) do
    described_class.new(fork: fork_op, clone: clone_op, branch: branch_op, announce: announce_op)
  end

  it "wires Fork → Clone → Branch → Announce and returns Success({fork:, clone:, branch:, announce:})",
     :aggregate_failures do
    allow(fork_op).to receive(:call).and_return(Success(fork_result))
    allow(clone_op).to receive(:call).and_return(Success(clone_result))
    allow(branch_op).to receive(:call).and_return(Success(branch_result))
    allow(announce_op).to receive(:call).and_return(Success(:posted))

    result = pipeline.call(adapter: adapter, project: project, issue: "1234",
                           root: "/clones", allow_announce: true)

    expect(result).to be_success
    expect(result.value!).to eq(
      fork: fork_result,
      clone: clone_result,
      branch: branch_result,
      announce: Success(:posted)
    )
    expect(fork_op).to have_received(:call).with(adapter: adapter, project: project)
    expect(clone_op).to have_received(:call).with(
      adapter: adapter, project: project,
      fork_clone_url: fork_result.clone_url, root: "/clones"
    )
    expect(branch_op).to have_received(:call).with(path: clone_result.path, issue: "1234")
  end

  it "passes allow: false to Announce when the viewer owns the upstream (fork.viewer == project.owner)" do
    fork_self = fork_result.with(viewer: "sidekiq")
    allow(fork_op).to receive(:call).and_return(Success(fork_self))
    allow(clone_op).to receive(:call).and_return(Success(clone_result))
    allow(branch_op).to receive(:call).and_return(Success(branch_result))
    allow(announce_op).to receive(:call).and_return(Success(:skipped))

    pipeline.call(adapter: adapter, project: project, issue: "1234",
                  root: "/clones", allow_announce: true)

    expect(announce_op).to have_received(:call).with(
      adapter: adapter, project: project, issue: "1234", allow: false
    )
  end

  it "passes allow: false to Announce when allow_announce: false" do
    allow(fork_op).to receive(:call).and_return(Success(fork_result))
    allow(clone_op).to receive(:call).and_return(Success(clone_result))
    allow(branch_op).to receive(:call).and_return(Success(branch_result))
    allow(announce_op).to receive(:call).and_return(Success(:skipped))

    pipeline.call(adapter: adapter, project: project, issue: "1234",
                  root: "/clones", allow_announce: false)

    expect(announce_op).to have_received(:call).with(
      adapter: adapter, project: project, issue: "1234", allow: false
    )
  end

  it "short-circuits with Fork's Failure and never calls Clone/Branch/Announce" do
    allow(fork_op).to receive(:call).and_return(Failure([:adapter_error, "fork timed out"]))
    allow(clone_op).to receive(:call)
    allow(branch_op).to receive(:call)
    allow(announce_op).to receive(:call)

    result = pipeline.call(adapter: adapter, project: project, issue: "1234",
                           root: "/clones", allow_announce: true)

    expect(result).to eq(Failure([:adapter_error, "fork timed out"]))
    expect(clone_op).not_to have_received(:call)
    expect(branch_op).not_to have_received(:call)
    expect(announce_op).not_to have_received(:call)
  end

  it "short-circuits with Branch's Failure and does not call Announce" do
    allow(fork_op).to receive(:call).and_return(Success(fork_result))
    allow(clone_op).to receive(:call).and_return(Success(clone_result))
    allow(branch_op).to receive(:call).and_return(Failure([:adapter_error, "branch exists"]))
    allow(announce_op).to receive(:call)

    result = pipeline.call(adapter: adapter, project: project, issue: "1234",
                           root: "/clones", allow_announce: true)

    expect(result).to eq(Failure([:adapter_error, "branch exists"]))
    expect(announce_op).not_to have_received(:call)
  end

  it "still returns Success when Announce returns Failure (announce is informational)" do
    allow(fork_op).to receive(:call).and_return(Success(fork_result))
    allow(clone_op).to receive(:call).and_return(Success(clone_result))
    allow(branch_op).to receive(:call).and_return(Success(branch_result))
    allow(announce_op).to receive(:call).and_return(Failure([:announce_failed, "GitHub 422"]))

    result = pipeline.call(adapter: adapter, project: project, issue: "1234",
                           root: "/clones", allow_announce: true)

    expect(result).to be_success
    expect(result.value![:announce]).to eq(Failure([:announce_failed, "GitHub 422"]))
  end
end
