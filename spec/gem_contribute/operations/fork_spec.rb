# frozen_string_literal: true

require "dry/monads"

RSpec.describe GemContribute::Operations::Fork do
  include Dry::Monads[:result]

  let(:adapter) { instance_double(GemContribute::HostAdapters::GitHubAdapter) }
  let(:project) do
    GemContribute::Project.new(
      gem_name: "sidekiq", host: "github.com",
      owner: "sidekiq", repo: "sidekiq", metadata: {}
    )
  end
  let(:operation) { described_class.new }

  before do
    allow(adapter).to receive(:repo_url).with("sidekiq", "sidekiq")
                                        .and_return("https://github.com/sidekiq/sidekiq")
  end

  it "returns Success with the fork data and the upstream URL" do
    allow(adapter).to receive(:fork).with(project).and_return(
      GemContribute::HostAdapter::ForkResult.new(
        clone_url: "https://github.com/alice/sidekiq.git",
        fork_url: "https://github.com/alice/sidekiq",
        viewer: "alice", reused: false, owned_upstream: false
      )
    )

    result = operation.call(adapter: adapter, project: project)

    expect(result).to be_success
    expect(result.value!).to have_attributes(
      clone_url: "https://github.com/alice/sidekiq.git",
      fork_url: "https://github.com/alice/sidekiq",
      upstream_url: "https://github.com/sidekiq/sidekiq",
      viewer: "alice", reused: false, owned_upstream: false
    )
  end

  it "preserves the reused flag from the adapter" do
    allow(adapter).to receive(:fork).and_return(
      GemContribute::HostAdapter::ForkResult.new(
        clone_url: "x", fork_url: "y", viewer: "alice", reused: true, owned_upstream: false
      )
    )

    result = operation.call(adapter: adapter, project: project)
    expect(result.value!.reused).to be(true)
  end

  it "preserves owned_upstream: true from the adapter" do
    allow(adapter).to receive(:fork).and_return(
      GemContribute::HostAdapter::ForkResult.new(
        clone_url: "x", fork_url: "y", viewer: "sidekiq", reused: true, owned_upstream: true
      )
    )

    result = operation.call(adapter: adapter, project: project)
    expect(result.value!.owned_upstream).to be(true)
  end

  it "returns Failure(:unauthenticated) when the adapter raises AuthRequired" do
    allow(adapter).to receive(:fork).and_raise(GemContribute::AuthRequired, "github.com")

    result = operation.call(adapter: adapter, project: project)
    expect(result).to eq(Failure(:unauthenticated))
  end

  it "returns Failure([:adapter_error, message]) when the adapter raises AdapterError" do
    allow(adapter).to receive(:fork).and_raise(GemContribute::AdapterError, "rate limit exceeded")

    result = operation.call(adapter: adapter, project: project)
    expect(result).to eq(Failure([:adapter_error, "rate limit exceeded"]))
  end
end
