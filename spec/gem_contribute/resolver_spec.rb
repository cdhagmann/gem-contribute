# frozen_string_literal: true

RSpec.describe GemContribute::Resolver do
  let(:cache) { GemContribute::Cache.new(root: Dir.mktmpdir, ttl: { "gems" => 3600 }) }
  let(:resolver) { described_class.new(cache: cache) }

  def stub_rubygems(name, body)
    stub_request(:get, "https://rubygems.org/api/v1/gems/#{name}.json")
      .to_return(status: 200, body: JSON.dump(body), headers: { "Content-Type" => "application/json" })
  end

  def lockfile_gem(name, source_type: :rubygems)
    GemContribute::LockedGem.new(
      name: name,
      version: "1.0.0",
      source_type: source_type,
      source_uri: "https://rubygems.org/"
    )
  end

  it "prefers bug_tracker_uri over source_code_uri" do
    stub_rubygems("sidekiq",
                  "name" => "sidekiq",
                  "bug_tracker_uri" => "https://github.com/sidekiq/sidekiq/issues",
                  "source_code_uri" => "https://github.com/sidekiq/sidekiq",
                  "homepage_uri" => "https://sidekiq.org")

    project = resolver.resolve(lockfile_gem("sidekiq"))
    expect(project).to have_attributes(host: "github.com", owner: "sidekiq", repo: "sidekiq")
    expect(project.metadata[:picked_from]).to eq("bug_tracker_uri")
  end

  it "falls back to source_code_uri when bug_tracker_uri is nil" do
    stub_rubygems("rake",
                  "source_code_uri" => "https://github.com/ruby/rake",
                  "homepage_uri" => "https://github.com/ruby/rake")

    project = resolver.resolve(lockfile_gem("rake"))
    expect(project).to have_attributes(owner: "ruby", repo: "rake")
    expect(project.metadata[:picked_from]).to eq("source_code_uri")
  end

  it "falls back to homepage_uri when both bug and source URIs are nil" do
    stub_rubygems("oldgem", "homepage_uri" => "https://github.com/example/oldgem")

    project = resolver.resolve(lockfile_gem("oldgem"))
    expect(project).to have_attributes(owner: "example", repo: "oldgem")
    expect(project.metadata[:picked_from]).to eq("homepage_uri")
  end

  it "strips trailing /issues from a bug_tracker_uri path" do
    # Common pattern: bug_tracker_uri = .../issues. We still want owner=sidekiq, repo=sidekiq.
    stub_rubygems("sidekiq",
                  "bug_tracker_uri" => "https://github.com/sidekiq/sidekiq/issues",
                  "source_code_uri" => "https://github.com/sidekiq/sidekiq")

    project = resolver.resolve(lockfile_gem("sidekiq"))
    expect(project.repo).to eq("sidekiq")
  end

  it "strips a trailing .git from the repo segment" do
    stub_rubygems("foo", "source_code_uri" => "https://github.com/example/foo.git")
    project = resolver.resolve(lockfile_gem("foo"))
    expect(project.repo).to eq("foo")
  end

  it "marks gitlab.com and codeberg.org as known hosts" do
    stub_rubygems("gl",
                  "source_code_uri" => "https://gitlab.com/group/project")
    stub_rubygems("cb",
                  "source_code_uri" => "https://codeberg.org/group/project")

    expect(resolver.resolve(lockfile_gem("gl")).host).to eq("gitlab.com")
    expect(resolver.resolve(lockfile_gem("cb")).host).to eq("codeberg.org")
  end

  it "returns an :unknown project for non-rubygems sources without hitting the network" do
    project = resolver.resolve(lockfile_gem("vendored", source_type: :path))
    expect(project.host).to eq(:unknown)
    expect(project.metadata[:reason]).to eq(GemContribute::Resolver::REASON_NON_RUBYGEMS_SOURCE)
    expect(WebMock).not_to have_requested(:get, /rubygems/)
  end

  it "returns an :unknown project with reason :api_not_found on a 404" do
    stub_request(:get, "https://rubygems.org/api/v1/gems/ghost.json").to_return(status: 404)
    project = resolver.resolve(lockfile_gem("ghost"))
    expect(project.host).to eq(:unknown)
    expect(project.metadata[:reason]).to eq(GemContribute::Resolver::REASON_API_NOT_FOUND)
  end

  it "returns an :unknown project with reason :no_usable_uri when metadata has none" do
    stub_rubygems("sparse", "name" => "sparse")
    project = resolver.resolve(lockfile_gem("sparse"))
    expect(project.metadata[:reason]).to eq(GemContribute::Resolver::REASON_NO_USABLE_URI)
  end

  it "returns an :unknown project with reason :unknown_host for non-supported hosts" do
    stub_rubygems("internal",
                  "bug_tracker_uri" => "https://bugs.internal.example/internal")

    project = resolver.resolve(lockfile_gem("internal"))
    expect(project.metadata[:reason]).to eq(GemContribute::Resolver::REASON_UNKNOWN_HOST)
    expect(project.metadata[:source_url]).to eq("https://bugs.internal.example/internal")
  end

  it "raises ResolveError on a non-200/404 status" do
    stub_request(:get, "https://rubygems.org/api/v1/gems/exploded.json").to_return(status: 500)
    expect { resolver.resolve(lockfile_gem("exploded")) }
      .to raise_error(GemContribute::ResolveError, /500/)
  end

  it "caches RubyGems metadata across calls" do
    stub_rubygems("rake", "source_code_uri" => "https://github.com/ruby/rake")

    resolver.resolve(lockfile_gem("rake"))
    resolver.resolve(lockfile_gem("rake"))

    expect(WebMock).to have_requested(:get, "https://rubygems.org/api/v1/gems/rake.json").once
  end
end
