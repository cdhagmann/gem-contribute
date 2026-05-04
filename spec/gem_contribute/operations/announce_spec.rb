# frozen_string_literal: true

require "dry/monads"

RSpec.describe GemContribute::Operations::Announce do
  include Dry::Monads[:result]

  let(:adapter) { instance_double(GemContribute::HostAdapters::GitHubAdapter) }
  let(:project) do
    GemContribute::Project.new(
      gem_name: "sidekiq", host: "github.com",
      owner: "sidekiq", repo: "sidekiq", metadata: {}
    )
  end
  let(:operation) { described_class.new }

  describe "#call" do
    it "returns Success(:skipped) immediately when allow: false" do
      result = operation.call(adapter: adapter, project: project, issue: "1", allow: false)

      expect(result).to eq(Success(:skipped))
      expect(adapter).not_to have_received(:comment) if defined?(adapter.comment)
    end

    it "returns Success(:skipped) when the marker is already present in earlier comments" do
      allow(adapter).to receive(:issue_comments).and_return(
        [{ "body" => "Random earlier comment" },
         { "body" => "#{described_class::WORKING_MARKER}\nSomeone already claimed." }]
      )

      result = operation.call(adapter: adapter, project: project, issue: "1234", allow: true)

      expect(result).to eq(Success(:skipped))
    end

    it "posts the WORKING_BODY and returns Success(:posted) when no marker is present" do
      allow(adapter).to receive_messages(issue_comments: [], comment: { "id" => 1 })

      result = operation.call(adapter: adapter, project: project, issue: "1234", allow: true)

      expect(result).to eq(Success(:posted))
      expect(adapter).to have_received(:comment)
        .with(project, issue: "1234", body: a_string_including(described_class::WORKING_MARKER))
    end

    it "treats a comment-list AdapterError as 'not announced' and still posts" do
      allow(adapter).to receive(:issue_comments)
        .and_raise(GemContribute::AdapterError, "GitHub returned 500")
      allow(adapter).to receive(:comment).and_return("id" => 2)

      result = operation.call(adapter: adapter, project: project, issue: "1234", allow: true)

      expect(result).to eq(Success(:posted))
    end

    it "returns Failure([:announce_failed, message]) when the post raises AdapterError" do
      allow(adapter).to receive_messages(issue_comments: [])
      allow(adapter).to receive(:comment)
        .and_raise(GemContribute::AdapterError, "GitHub returned 422")

      result = operation.call(adapter: adapter, project: project, issue: "1234", allow: true)

      expect(result).to eq(Failure([:announce_failed, "GitHub returned 422"]))
    end
  end
end
