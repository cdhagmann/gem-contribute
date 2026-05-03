# frozen_string_literal: true

require "stringio"

RSpec.describe GemContribute::CLI::IssueAnnouncer do
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }
  let(:adapter) { instance_double(GemContribute::HostAdapters::GitHubAdapter) }
  let(:project) do
    GemContribute::Project.new(
      gem_name: "sidekiq", host: "github.com",
      owner: "sidekiq", repo: "sidekiq", metadata: {}
    )
  end

  describe ".announce_working" do
    it "posts a comment and returns :posted when no marker is present" do
      allow(adapter).to receive_messages(issue_comments: [], comment: { "id" => 1 })

      result = described_class.announce_working(
        adapter: adapter, project: project, issue: "1234",
        stdout: stdout, stderr: stderr
      )

      expect(result).to eq(:posted)
      expect(adapter).to have_received(:comment)
        .with(project, issue: "1234", body: a_string_including(described_class::WORKING_MARKER))
      expect(stdout.string).to include("Posted 'working on this' comment to issue #1234")
    end

    it "skips the post and returns :skipped when the marker is present" do
      allow(adapter).to receive(:issue_comments).and_return(
        [{ "body" => "Random earlier comment" },
         { "body" => "#{described_class::WORKING_MARKER}\nI've started working on this." }]
      )

      result = described_class.announce_working(
        adapter: adapter, project: project, issue: "1234",
        stdout: stdout, stderr: stderr
      )

      expect(result).to eq(:skipped)
      expect(adapter).not_to have_received(:comment) if defined?(adapter.comment)
    end

    it "soft-fails to :failed when the post raises AdapterError" do
      allow(adapter).to receive(:issue_comments).and_return([])
      allow(adapter).to receive(:comment)
        .and_raise(GemContribute::AdapterError, "GitHub returned 422")

      result = described_class.announce_working(
        adapter: adapter, project: project, issue: "1234",
        stdout: stdout, stderr: stderr
      )

      expect(result).to eq(:failed)
      expect(stderr.string).to include("couldn't post 'working on this' comment")
      expect(stderr.string).to include("Continuing.")
    end

    it "treats an AdapterError on the comment-listing call as 'not announced' and still posts" do
      allow(adapter).to receive(:issue_comments)
        .and_raise(GemContribute::AdapterError, "GitHub returned 500")
      allow(adapter).to receive(:comment).and_return("id" => 2)

      result = described_class.announce_working(
        adapter: adapter, project: project, issue: "1234",
        stdout: stdout, stderr: stderr
      )

      expect(result).to eq(:posted)
      expect(adapter).to have_received(:comment)
    end
  end

  describe ".fetch_claim_index" do
    let(:claim_adapter) { instance_double(GemContribute::HostAdapters::GitHubAdapter) }

    it "groups search hits into a {owner/repo => [numbers]} hash" do
      hits = [
        { "html_url" => "https://github.com/sidekiq/sidekiq/issues/7" },
        { "html_url" => "https://github.com/sidekiq/sidekiq/issues/12" },
        { "html_url" => "https://github.com/rubocop/rubocop/issues/100" }
      ]
      allow(claim_adapter).to receive(:search_issues).and_return(hits)

      index = described_class.fetch_claim_index(claim_adapter)
      expect(index["sidekiq/sidekiq"]).to contain_exactly(7, 12)
      expect(index["rubocop/rubocop"]).to contain_exactly(100)
    end

    it "returns an empty hash when the search raises AdapterError" do
      allow(claim_adapter).to receive(:search_issues)
        .and_raise(GemContribute::AdapterError, "rate limit exceeded")

      expect(described_class.fetch_claim_index(claim_adapter)).to eq({})
    end

    it "skips entries whose html_url isn't a recognizable issue URL" do
      hits = [
        { "html_url" => "https://example.com/something/weird" },
        { "html_url" => "https://github.com/foo/bar/issues/9" }
      ]
      allow(claim_adapter).to receive(:search_issues).and_return(hits)

      index = described_class.fetch_claim_index(claim_adapter)
      expect(index).to eq("foo/bar" => [9])
    end
  end
end
