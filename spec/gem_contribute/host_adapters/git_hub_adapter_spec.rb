# frozen_string_literal: true

RSpec.describe GemContribute::HostAdapters::GitHubAdapter do
  let(:cache) { GemContribute::Cache.new(root: Dir.mktmpdir, ttl: { "issues" => 3600, "repos" => 3600, "files" => 3600 }) }
  let(:sleeper) { ->(_s) {} }
  let(:adapter) { described_class.new(cache: cache, sleeper: sleeper) }
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

  describe "#comment without a token" do
    it "raises AuthRequired" do
      expect { adapter.comment(project, issue: 1, body: "x") }.to raise_error(GemContribute::AuthRequired)
    end
  end

  describe "#issue_comments without a token" do
    it "raises AuthRequired" do
      expect { adapter.issue_comments(project, 1) }.to raise_error(GemContribute::AuthRequired)
    end
  end

  context "with a token" do
    let(:adapter) { described_class.new(cache: cache, sleeper: sleeper, token: "gho_test") }

    before do
      stub_request(:get, "https://api.github.com/user")
        .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                   body: JSON.dump("login" => "alice"))
    end

    describe "#fork" do
      it "skips the POST and returns reused: true when the viewer already owns the fork" do
        stub_request(:get, "https://api.github.com/repos/alice/sidekiq")
          .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                     body: JSON.dump("name" => "sidekiq"))

        result = adapter.fork(project)
        expect(result).to have_attributes(
          clone_url: "https://github.com/alice/sidekiq.git",
          fork_url: "https://github.com/alice/sidekiq",
          viewer: "alice",
          reused: true,
          owned_upstream: false
        )
        expect(WebMock).not_to have_requested(:post, %r{/forks})
      end

      it "returns owned_upstream: true and skips fork_exists? check when viewer is the project owner" do
        owned_project = GemContribute::Project.new(
          gem_name: "gem-contribute", host: "github.com",
          owner: "alice", repo: "gem-contribute", metadata: {}
        )

        result = adapter.fork(owned_project)

        expect(result).to have_attributes(
          clone_url: "https://github.com/alice/gem-contribute.git",
          viewer: "alice",
          reused: true,
          owned_upstream: true
        )
        expect(WebMock).not_to have_requested(:get, %r{/repos/alice/gem-contribute})
        expect(WebMock).not_to have_requested(:post, %r{/forks})
      end

      it "POSTs the fork, polls until ready, and returns reused: false when no fork exists yet",
         :aggregate_failures do
        stub_request(:get, "https://api.github.com/repos/alice/sidekiq")
          .to_return(
            { status: 404 }, # initial existence check
            { status: 404 }, # first readiness poll: still propagating
            { status: 200, headers: { "Content-Type" => "application/json" },
              body: JSON.dump("name" => "sidekiq") } # second poll: live
          )
        stub_request(:post, "https://api.github.com/repos/sidekiq/sidekiq/forks")
          .with(headers: { "Authorization" => "Bearer gho_test" })
          .to_return(
            status: 202,
            headers: { "Content-Type" => "application/json" },
            body: JSON.dump("name" => "sidekiq", "owner" => { "login" => "alice" },
                            "clone_url" => "https://github.com/alice/sidekiq.git",
                            "html_url" => "https://github.com/alice/sidekiq")
          )

        result = adapter.fork(project)
        expect(result.reused).to be(false)
        expect(result.clone_url).to eq("https://github.com/alice/sidekiq.git")
        expect(WebMock).to have_requested(:post, %r{/forks}).once
      end

      it "raises AdapterError when the fork never becomes reachable" do
        stub_request(:get, "https://api.github.com/repos/alice/sidekiq").to_return(status: 404)
        stub_request(:post, "https://api.github.com/repos/sidekiq/sidekiq/forks")
          .to_return(status: 202, headers: { "Content-Type" => "application/json" },
                     body: JSON.dump("clone_url" => "https://github.com/alice/sidekiq.git"))

        expect { adapter.fork(project) }
          .to raise_error(GemContribute::AdapterError, /not reachable/)
      end
    end

    describe "#viewer_login" do
      it "returns the authenticated user's login from GET /user" do
        expect(adapter.viewer_login).to eq("alice")
      end
    end

    describe "#comment" do
      it "POSTs to /repos/:owner/:repo/issues/:n/comments and returns the parsed body" do
        stub_request(:post, "https://api.github.com/repos/sidekiq/sidekiq/issues/1234/comments")
          .with(headers: { "Authorization" => "Bearer gho_test" },
                body: hash_including("body" => "Hello world"))
          .to_return(
            status: 201,
            headers: { "Content-Type" => "application/json" },
            body: JSON.dump("id" => 999, "body" => "Hello world",
                            "html_url" => "https://github.com/sidekiq/sidekiq/issues/1234#issuecomment-999")
          )

        body = adapter.comment(project, issue: 1234, body: "Hello world")
        expect(body["id"]).to eq(999)
        expect(body["body"]).to eq("Hello world")
      end
    end

    describe "#issue_comments" do
      it "GETs the issue comments and returns the parsed array" do
        stub_request(:get, "https://api.github.com/repos/sidekiq/sidekiq/issues/1234/comments")
          .with(headers: { "Authorization" => "Bearer gho_test" })
          .to_return(
            status: 200,
            headers: { "Content-Type" => "application/json" },
            body: JSON.dump([{ "id" => 1, "body" => "first" }, { "id" => 2, "body" => "second" }])
          )

        comments = adapter.issue_comments(project, 1234)
        expect(comments.size).to eq(2)
        expect(comments.first["body"]).to eq("first")
      end
    end
  end

  describe "#search_issues" do
    it "GETs /search/issues with the q param and returns the items array" do
      stub_request(:get, "https://api.github.com/search/issues")
        .with(query: { "q" => "\"<!-- gem-contribute:working v1 -->\"" })
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.dump("total_count" => 1,
                          "items" => [{ "number" => 7,
                                        "html_url" => "https://github.com/sidekiq/sidekiq/issues/7" }])
        )

      items = adapter.search_issues("\"<!-- gem-contribute:working v1 -->\"")
      expect(items.size).to eq(1)
      expect(items.first["number"]).to eq(7)
    end

    it "caches the result by query so repeat calls don't re-hit the API" do
      stub_request(:get, "https://api.github.com/search/issues")
        .with(query: { "q" => "anything" })
        .to_return(status: 200,
                   headers: { "Content-Type" => "application/json" },
                   body: JSON.dump("items" => []))

      adapter.search_issues("anything")
      adapter.search_issues("anything")
      expect(WebMock).to have_requested(:get, %r{api\.github\.com/search/issues}).once
    end
  end

  describe "#issues_matching_labels" do
    def project_for(owner, repo)
      GemContribute::Project.new(gem_name: repo, host: "github.com",
                                 owner: owner, repo: repo, metadata: {})
    end

    def search_stub(items)
      stub_request(:get, %r{api\.github\.com/search/issues})
        .to_return(status: 200,
                   headers: { "Content-Type" => "application/json",
                              "X-RateLimit-Limit" => "30",
                              "X-RateLimit-Remaining" => "29",
                              "X-RateLimit-Reset" => "1714510800" },
                   body: JSON.dump("items" => items))
    end

    def search_item(number, owner, repo)
      {
        "number" => number,
        "title" => "Issue #{number}",
        "html_url" => "https://github.com/#{owner}/#{repo}/issues/#{number}",
        "repository_url" => "https://api.github.com/repos/#{owner}/#{repo}"
      }
    end

    it "returns a hash keyed by owner/repo with issues as values" do
      search_stub([
                    search_item(1, "sidekiq", "sidekiq"),
                    search_item(2, "ruby", "rake")
                  ])
      rake = project_for("ruby", "rake")

      result = adapter.issues_matching_labels([project, rake], labels: ["good first issue"])

      expect(result["sidekiq/sidekiq"].map { |i| i["number"] }).to eq([1])
      expect(result["ruby/rake"].map { |i| i["number"] }).to eq([2])
    end

    it "returns {} immediately when the projects list is empty" do
      result = adapter.issues_matching_labels([], labels: ["good first issue"])
      expect(result).to eq({})
      expect(WebMock).not_to have_requested(:get, %r{api\.github\.com/search})
    end

    it "returns {} immediately when labels is empty" do
      result = adapter.issues_matching_labels([project], labels: [])
      expect(result).to eq({})
      expect(WebMock).not_to have_requested(:get, %r{api\.github\.com/search})
    end

    it "batches repos #{described_class::SEARCH_BATCH_SIZE} at a time" do
      search_stub([])

      projects = (1..11).map { |i| project_for("owner", "gem#{i}") }
      adapter.issues_matching_labels(projects, labels: ["good first issue"])

      expect(WebMock).to have_requested(:get, %r{api\.github\.com/search/issues}).twice
    end

    it "caches by query so repeat calls with the same projects and labels hit the API once" do
      search_stub([search_item(7, "sidekiq", "sidekiq")])

      adapter.issues_matching_labels([project], labels: ["good first issue"])
      adapter.issues_matching_labels([project], labels: ["good first issue"])

      expect(WebMock).to have_requested(:get, %r{api\.github\.com/search/issues}).once
    end

    it "sends OR-combined label terms and repo: qualifiers in the search query" do
      search_stub([])

      adapter.issues_matching_labels([project], labels: ["good first issue", "help wanted"])

      expect(WebMock).to have_requested(:get, %r{api\.github\.com/search/issues})
        .with(query: hash_including(
          "q" => 'is:issue state:open (label:"good first issue" OR label:"help wanted") repo:sidekiq/sidekiq'
        ))
    end
  end

  describe "#pull_request_url" do
    let(:upstream) do
      GemContribute::Project.new(
        gem_name: "sidekiq", host: "github.com",
        owner: "sidekiq", repo: "sidekiq", metadata: {}
      )
    end

    it "uses the cross-fork compare form when head_owner != upstream.owner" do
      url = adapter.pull_request_url(
        upstream,
        head_owner: "alice", head_branch: "gem-contribute/issue-42",
        title: "Fix #42: Improve batching",
        body: "Closes #42."
      )
      expect(url).to start_with("https://github.com/sidekiq/sidekiq/compare/alice:gem-contribute/issue-42?")
      expect(url).to include("expand=1")
      expect(url).to include(URI.encode_www_form_component("Fix #42: Improve batching"))
    end

    it "uses the same-repo compare form when head_owner == upstream.owner" do
      same_repo = GemContribute::Project.new(
        gem_name: "x", host: "github.com", owner: "alice", repo: "sidekiq", metadata: {}
      )
      url = adapter.pull_request_url(
        same_repo,
        head_owner: "alice", head_branch: "gem-contribute/issue-42",
        title: "Fix #42", body: "Closes #42."
      )
      expect(url).to start_with("https://github.com/alice/sidekiq/compare/gem-contribute/issue-42?")
      expect(url).not_to include("alice:gem-contribute/issue-42")
    end

    it "raises AdapterError when the upstream is not on github.com" do
      gitlab = GemContribute::Project.new(
        gem_name: "x", host: "gitlab.com", owner: "x", repo: "y", metadata: {}
      )
      expect do
        adapter.pull_request_url(gitlab, head_owner: "a", head_branch: "b", title: "t", body: "b")
      end.to raise_error(GemContribute::AdapterError, /github/i)
    end
  end

  describe "#clone_url and #repo_url" do
    it "templates the host-specific URLs without auth or network" do
      expect(adapter.clone_url("alice", "sidekiq")).to eq("https://github.com/alice/sidekiq.git")
      expect(adapter.repo_url("alice", "sidekiq")).to eq("https://github.com/alice/sidekiq")
    end
  end

  describe "non-200 from a public endpoint" do
    it "raises AdapterError with the status" do
      stub_request(:get, %r{api\.github\.com/repos/sidekiq/sidekiq/issues})
        .to_return(status: 502)
      expect { adapter.issues(project) }.to raise_error(GemContribute::AdapterError, /502/)
    end
  end

  describe "301 redirect handling" do
    it "follows a single redirect and returns the result from the new location" do
      stub_request(:get, %r{api\.github\.com/repos/sickill/rainbow/issues})
        .to_return(status: 301,
                   headers: { "Location" => "https://api.github.com/repos/ku1ik/rainbow/issues" })
      stub_request(:get, %r{api\.github\.com/repos/ku1ik/rainbow/issues})
        .to_return(status: 200,
                   headers: { "Content-Type" => "application/json" },
                   body: JSON.dump([{ "number" => 1, "title" => "A bug",
                                      "html_url" => "https://github.com/ku1ik/rainbow/issues/1" }]))

      renamed = GemContribute::Project.new(
        gem_name: "rainbow", host: "github.com", owner: "sickill", repo: "rainbow", metadata: {}
      )
      issues = adapter.issues(renamed)
      expect(issues.first["number"]).to eq(1)
    end

    it "re-applies the original query params after the redirect" do
      stub_request(:get, %r{api\.github\.com/repos/old/repo/issues})
        .with(query: hash_including("labels" => "good first issue"))
        .to_return(status: 301,
                   headers: { "Location" => "https://api.github.com/repos/new/repo/issues" })
      stub_request(:get, %r{api\.github\.com/repos/new/repo/issues})
        .with(query: hash_including("labels" => "good first issue"))
        .to_return(status: 200,
                   headers: { "Content-Type" => "application/json" },
                   body: "[]")

      moved = GemContribute::Project.new(
        gem_name: "gem", host: "github.com", owner: "old", repo: "repo", metadata: {}
      )
      expect(adapter.issues(moved, labels: ["good first issue"])).to eq([])
    end

    it "raises AdapterError after exhausting the redirect limit" do
      stub_request(:get, %r{api\.github\.com/repos/loop/repo})
        .to_return(status: 301,
                   headers: { "Location" => "https://api.github.com/repos/loop/repo" })

      looping = GemContribute::Project.new(
        gem_name: "loop", host: "github.com", owner: "loop", repo: "repo", metadata: {}
      )
      expect { adapter.issues(looping) }.to raise_error(GemContribute::AdapterError, /301/)
    end
  end
end
