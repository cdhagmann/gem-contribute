# frozen_string_literal: true

# Integration test against the real GitHub API. Gated on the env var so the
# normal `bin/rspec` run stays hermetic.
#
# Usage:
#   GEM_CONTRIBUTE_INTEGRATION=1 bin/rspec spec/integration/
#
# Requires:
#   - GEM_CONTRIBUTE_CLIENT_ID set to your registered OAuth App's Client ID
#   - GEM_CONTRIBUTE_TOKEN     set to a real GitHub token (the value cached
#                              by `gem-contribute auth login`); never check in
#
# Target gem: mailcatcher (see docs/design.md). Small, friendly, GitHub-hosted.
# This spec only exercises read methods so it doesn't pollute anything; the
# fork/clone/branch live demo is the human-driven step the prep plan
# explicitly leaves to Chris.

return unless ENV["GEM_CONTRIBUTE_INTEGRATION"] == "1"

WebMock.disable!

RSpec.describe "live GitHub integration", :integration do
  let(:cache) { GemContribute::Cache.new(root: Dir.mktmpdir) }
  let(:token) { ENV.fetch("GEM_CONTRIBUTE_TOKEN", nil) }
  let(:adapter) { GemContribute::HostAdapters::GitHubAdapter.new(cache: cache, token: token) }
  let(:resolver) { GemContribute::Resolver.new(cache: cache) }

  let(:project) do
    gem = GemContribute::LockedGem.new(
      name: "mailcatcher", version: "*", source_type: :rubygems,
      source_uri: "https://rubygems.org/"
    )
    resolver.resolve(gem)
  end

  it "resolves mailcatcher to its GitHub coordinates via RubyGems" do
    expect(project.host).to eq("github.com")
    expect(project.owner).to be_a(String)
    expect(project.repo).to eq("mailcatcher")
  end

  it "fetches the open issue list (anonymous)" do
    issues = adapter.issues(project)
    expect(issues).to be_an(Array)
  end

  it "fetches the community profile (anonymous)" do
    profile = adapter.community_profile(project)
    expect(profile).to include("files")
  end

  context "with a token" do
    before { skip "set GEM_CONTRIBUTE_TOKEN to run authenticated checks" if token.nil? || token.empty? }

    it "looks up the viewer login via /user" do
      expect(adapter.viewer_login).to be_a(String)
    end
  end
end
