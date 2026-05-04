# frozen_string_literal: true

RSpec.describe GemContribute::CLI::IssueAnnouncer do
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

    it "uses the same WORKING_MARKER constant as Operations::Announce" do
      expect(described_class::MARKER).to eq(GemContribute::Operations::Announce::WORKING_MARKER)
    end
  end
end
