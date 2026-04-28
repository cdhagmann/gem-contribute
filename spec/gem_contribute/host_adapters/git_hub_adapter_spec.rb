# frozen_string_literal: true

RSpec.describe GemContribute::HostAdapters::GitHubAdapter do
  let(:cache) { GemContribute::Cache.new(root: Dir.mktmpdir, ttl: { "issues" => 3600, "repos" => 3600, "files" => 3600 }) }
  let(:adapter) { described_class.new(cache: cache) }
  let(:project) do
    GemContribute::Project.new(
      gem_name: "sidekiq",
      host: "github.com",
      owner: "sidekiq",
      repo: "sidekiq",
      metadata: {}
    )
  end

  describe "#issues" do
    it "fetches open issues for a project and filters out pull requests", :vcr do
      VCR.use_cassette("github/issues_sidekiq") do
        issues = adapter.issues(project)
        numbers = issues.map { |i| i["number"] }
        expect(numbers).to contain_exactly(6543, 6500) # PR #6542 dropped
      end
    end

    it "supports a labels filter that round-trips to the GitHub query string" do
      VCR.use_cassette("github/issues_sidekiq") do
        issues = adapter.issues(project, labels: ["good first issue"])
        expect(issues.first).to include("number" => 6400)
      end
    end

    it "caches by (owner, repo, sorted labels) so repeat calls don't hit the API" do
      stub_request(:get, %r{api\.github\.com/repos/foo/bar/issues})
        .to_return(status: 200, body: "[]",
                   headers: { "Content-Type" => "application/json", "X-RateLimit-Limit" => "60",
                              "X-RateLimit-Remaining" => "59", "X-RateLimit-Reset" => "1714510800" })

      foo = GemContribute::Project.new(gem_name: "foo", host: "github.com", owner: "foo", repo: "bar", metadata: {})
      adapter.issues(foo)
      adapter.issues(foo)
      expect(WebMock).to have_requested(:get, %r{api\.github\.com/repos/foo/bar/issues}).once
    end

    it "raises AdapterError when the project's host is not github.com" do
      gitlab_project = GemContribute::Project.new(
        gem_name: "x", host: "gitlab.com", owner: "x", repo: "y", metadata: {}
      )
      expect { adapter.issues(gitlab_project) }.to raise_error(GemContribute::AdapterError, /github/i)
    end

    it "records rate limit headers from the response" do
      VCR.use_cassette("github/issues_sidekiq") do
        adapter.issues(project)
      end
      expect(adapter.rate_limit).to have_attributes(limit: 60, remaining: 57)
    end
  end

  describe "#community_profile" do
    it "returns the parsed community profile and caches it", :vcr do
      VCR.use_cassette("github/community_profile_sidekiq") do
        profile = adapter.community_profile(project)
        expect(profile["files"]["contributing"]["html_url"]).to include("CONTRIBUTING.md")
      end
    end
  end

  describe "#fork without a token" do
    it "raises AuthRequired with host github.com" do
      expect { adapter.fork(project) }.to raise_error(GemContribute::AuthRequired) do |err|
        expect(err.host).to eq("github.com")
      end
    end
  end

  describe "#already_forked? without a token" do
    it "raises AuthRequired" do
      expect { adapter.already_forked?(project) }.to raise_error(GemContribute::AuthRequired)
    end
  end

  context "with a token" do
    let(:adapter) { described_class.new(cache: cache, token: "gho_test") }

    describe "#fork" do
      it "POSTs to /repos/:owner/:repo/forks and returns the parsed body" do
        stub_request(:post, "https://api.github.com/repos/sidekiq/sidekiq/forks")
          .with(headers: { "Authorization" => "Bearer gho_test" })
          .to_return(
            status: 202,
            headers: { "Content-Type" => "application/json" },
            body: JSON.dump("name" => "sidekiq", "owner" => { "login" => "alice" },
                            "clone_url" => "https://github.com/alice/sidekiq.git",
                            "default_branch" => "main")
          )

        body = adapter.fork(project)
        expect(body["clone_url"]).to eq("https://github.com/alice/sidekiq.git")
        expect(body["owner"]["login"]).to eq("alice")
      end
    end

    describe "#already_forked?" do
      before do
        stub_request(:get, "https://api.github.com/user")
          .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                     body: JSON.dump("login" => "alice"))
      end

      it "returns true when GET /repos/:viewer/:repo succeeds" do
        stub_request(:get, "https://api.github.com/repos/alice/sidekiq")
          .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                     body: JSON.dump("name" => "sidekiq"))
        expect(adapter.already_forked?(project)).to be(true)
      end

      it "returns false on 404" do
        stub_request(:get, "https://api.github.com/repos/alice/sidekiq").to_return(status: 404)
        expect(adapter.already_forked?(project)).to be(false)
      end
    end

    describe "#viewer_login" do
      it "returns the authenticated user's login from GET /user" do
        stub_request(:get, "https://api.github.com/user")
          .with(headers: { "Authorization" => "Bearer gho_test" })
          .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                     body: JSON.dump("login" => "alice"))
        expect(adapter.viewer_login).to eq("alice")
      end
    end

    describe "#fork_ready?" do
      it "returns true when GET /repos/:viewer/:name returns 200" do
        stub_request(:get, "https://api.github.com/repos/alice/sidekiq")
          .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                     body: JSON.dump("name" => "sidekiq"))
        expect(adapter.fork_ready?("alice", "sidekiq")).to be(true)
      end

      it "returns false on 404 (still propagating)" do
        stub_request(:get, "https://api.github.com/repos/alice/sidekiq").to_return(status: 404)
        expect(adapter.fork_ready?("alice", "sidekiq")).to be(false)
      end
    end
  end

  describe "non-200 from a public endpoint" do
    it "raises AdapterError with the status" do
      stub_request(:get, %r{api\.github\.com/repos/sidekiq/sidekiq/issues})
        .to_return(status: 502)
      expect { adapter.issues(project) }.to raise_error(GemContribute::AdapterError, /502/)
    end
  end
end
