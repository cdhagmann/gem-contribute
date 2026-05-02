# frozen_string_literal: true

require "stringio"

RSpec.describe GemContribute::CLI::Scan do
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }
  let(:resolver) { instance_double(GemContribute::Resolver) }
  let(:adapter) { instance_double(GemContribute::HostAdapters::GitHubAdapter) }
  let(:scan) { described_class.new(stdout: stdout, stderr: stderr, resolver: resolver, adapter: adapter) }
  let(:fixtures) { File.expand_path("../../fixtures", __dir__) }
  let(:lockfile) { File.join(fixtures, "Gemfile.simple.lock") }

  # Default: every adapter mock returns nil from rate_limit so the
  # post-scan footer is a no-op. Tests that exercise the footer
  # explicitly override this.
  before do
    allow(adapter).to receive(:rate_limit).and_return(nil)
    # Default: no claimed issues. Tests that exercise the suffix override.
    allow(GemContribute::CLI::IssueAnnouncer).to receive(:fetch_claim_index).and_return({})
  end

  it "appends a `· N claimed` suffix when the project has claimed issues" do
    allow(resolver).to receive(:resolve) do |gem|
      project(gem.name) if gem.name == "rubocop"
    end
    allow(adapter).to receive(:issues).and_return([{ "number" => 1 }, { "number" => 2 }])
    allow(GemContribute::CLI::IssueAnnouncer).to receive(:fetch_claim_index)
      .and_return("ruby/rubocop" => [1])

    rubocop_only = File.join(fixtures, "Gemfile.rubocop_only.lock")
    File.write(rubocop_only, <<~LOCKFILE)
      GEM
        remote: https://rubygems.org/
        specs:
          rubocop (1.0.0)

      PLATFORMS
        ruby

      DEPENDENCIES
        rubocop
    LOCKFILE
    expect(scan.run([rubocop_only])).to eq(0)
    expect(stdout.string).to include("· 1 claimed")
    File.delete(rubocop_only)
  end

  def project(gem_name, host: "github.com", owner: "ruby", repo: nil)
    GemContribute::Project.new(
      gem_name: gem_name,
      host: host,
      owner: owner,
      repo: repo || gem_name,
      metadata: {}
    )
  end

  def unresolved_project(gem_name, reason: GemContribute::Resolver::REASON_NON_RUBYGEMS_SOURCE)
    GemContribute::Project.new(
      gem_name: gem_name, host: :unknown, owner: nil, repo: nil,
      metadata: { reason: reason }
    )
  end

  it "prints a host summary line and a ranked top-projects list" do
    allow(resolver).to receive(:resolve) do |gem|
      case gem.name
      when "rake" then project("rake", owner: "ruby", repo: "rake")
      when "sidekiq" then project("sidekiq", owner: "sidekiq", repo: "sidekiq")
      when "connection_pool" then project("connection_pool", owner: "mperham", repo: "connection_pool")
      when "logger" then unresolved_project("logger", reason: :unknown_host)
      when "rack" then project("rack", owner: "rack", repo: "rack")
      end
    end
    allow(adapter).to receive(:issues) do |proj, _opts|
      case proj.gem_name
      when "sidekiq" then [{ "number" => 1 }, { "number" => 2 }, { "number" => 3 }, { "number" => 4 },
                           { "number" => 5 }]
      when "rake" then [{ "number" => 10 }]
      when "rack" then [{ "number" => 9 }, { "number" => 11 }]
      else []
      end
    end

    expect(scan.run([lockfile])).to eq(0)

    out = stdout.string
    expect(out).to include("5 gems")
    expect(out).to include("on github.com")
    expect(out).to include("Top contributable projects")
    expect(out).to match(%r{sidekiq\s+5\s+github\.com/sidekiq/sidekiq})
    # rack (2) ranks above rake (1)
    rack_line = out.lines.index { |l| l.include?("rack ") || l.include?("rack  ") }
    rake_line = out.lines.index { |l| l.match?(/rake\s+1\s+/) }
    expect(rack_line).to be < rake_line
  end

  it "prints a no-github message when no lockfile gems resolve to github.com" do
    allow(resolver).to receive(:resolve).and_return(unresolved_project("rake"))
    allow(adapter).to receive(:issues).and_return([])

    expect(scan.run([lockfile])).to eq(0)
    expect(stdout.string).to include("No github.com projects")
  end

  it "auto-injects gem-contribute itself into the ranked list" do
    allow(resolver).to receive(:resolve).and_return(unresolved_project("rake"))
    allow(adapter).to receive(:issues) do |proj, _opts|
      proj.gem_name == "gem-contribute" ? [{ "number" => 1 }, { "number" => 2 }] : []
    end

    expect(scan.run([lockfile])).to eq(0)
    expect(stdout.string).to match(%r{gem-contribute\s+2\s+github\.com/cdhagmann/gem-contribute})
  end

  it "exits 1 with a clear stderr message when the lockfile is missing" do
    expect(scan.run(["/nonexistent/Gemfile.lock"])).to eq(1)
    expect(stderr.string).to include("no Gemfile.lock")
  end

  it "warns on adapter errors but doesn't crash the whole scan" do
    allow(resolver).to receive(:resolve).and_return(project("sidekiq", owner: "sidekiq", repo: "sidekiq"))
    allow(adapter).to receive(:issues).and_raise(GemContribute::AdapterError, "boom")

    expect(scan.run([lockfile])).to eq(0)
    expect(stderr.string).to include("warning: sidekiq")
    expect(stderr.string).to include("boom")
  end

  it "appends the GitHub rate-limit footer when adapter recorded one" do
    allow(resolver).to receive(:resolve).and_return(project("rake", owner: "ruby", repo: "rake"))
    allow(adapter).to receive(:issues).and_return([{ "number" => 1 }])
    allow(adapter).to receive(:rate_limit).and_return(
      Struct.new(:limit, :remaining, :reset_at).new(5000, 4587, Time.utc(2026, 4, 30, 14, 32, 0))
    )

    expect(scan.run([lockfile])).to eq(0)
    expect(stdout.string).to include("GitHub rate limit: 4,587 / 5,000 remaining · resets at 14:32 UTC")
  end

  it "omits the footer when the adapter has no rate-limit data (cache-only run)" do
    allow(resolver).to receive(:resolve).and_return(project("rake", owner: "ruby", repo: "rake"))
    allow(adapter).to receive(:issues).and_return([{ "number" => 1 }])
    # adapter.rate_limit defaults to nil via the top-level before block.

    expect(scan.run([lockfile])).to eq(0)
    expect(stdout.string).not_to include("GitHub rate limit")
  end
end
