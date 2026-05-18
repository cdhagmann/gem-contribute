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

  before do
    allow(adapter).to receive(:rate_limit).and_return(nil)
    allow(GemContribute::CLI::IssueAnnouncer).to receive(:fetch_claim_index).and_return({})
  end

  def project(gem_name, host: "github.com", owner: "ruby", repo: nil)
    GemContribute::Project.new(
      gem_name: gem_name, host: host, owner: owner,
      repo: repo || gem_name, metadata: {}
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
      when "rake"            then project("rake", owner: "ruby", repo: "rake")
      when "sidekiq"         then project("sidekiq", owner: "sidekiq", repo: "sidekiq")
      when "connection_pool" then project("connection_pool", owner: "mperham", repo: "connection_pool")
      when "logger"          then unresolved_project("logger", reason: :unknown_host)
      when "rack"            then project("rack", owner: "rack", repo: "rack")
      end
    end
    allow(adapter).to receive(:issues_matching_labels).and_return(
      "sidekiq/sidekiq" => Array.new(5) { |i| { "number" => i + 1 } },
      "ruby/rake" => [{ "number" => 10 }],
      "rack/rack" => [{ "number" => 9 }, { "number" => 11 }]
    )

    expect(scan.run([lockfile])).to eq(0)

    out = stdout.string
    expect(out).to include("5 gems")
    expect(out).to include("on github.com")
    expect(out).to include("Top contributable projects")
    expect(out).to match(%r{sidekiq\s+5\s+github\.com/sidekiq/sidekiq})
    rack_line = out.lines.index { |l| l.include?("rack ") || l.include?("rack  ") }
    rake_line = out.lines.index { |l| l.match?(/rake\s+1\s+/) }
    expect(rack_line).to be < rake_line
  end

  it "prints a no-github message when no lockfile gems resolve to github.com" do
    allow(resolver).to receive(:resolve).and_return(unresolved_project("rake"))
    allow(adapter).to receive(:issues_matching_labels).and_return({})

    expect(scan.run([lockfile])).to eq(0)
    expect(stdout.string).to include("No github.com projects")
  end

  it "auto-injects gem-contribute itself into the ranked list" do
    allow(resolver).to receive(:resolve).and_return(unresolved_project("rake"))
    allow(adapter).to receive(:issues_matching_labels).and_return(
      "cdhagmann/gem-contribute" => [{ "number" => 1 }, { "number" => 2 }]
    )

    expect(scan.run([lockfile])).to eq(0)
    expect(stdout.string).to match(%r{gem-contribute\s+2\s+github\.com/cdhagmann/gem-contribute})
  end

  it "exits 1 with a clear stderr message when the lockfile is missing" do
    expect(scan.run(["/nonexistent/Gemfile.lock"])).to eq(1)
    expect(stderr.string).to include("no Gemfile.lock")
  end

  it "warns when the search fails but doesn't crash the scan" do
    allow(resolver).to receive(:resolve).and_return(project("sidekiq", owner: "sidekiq", repo: "sidekiq"))
    allow(adapter).to receive(:issues_matching_labels).and_raise(GemContribute::AdapterError, "boom")

    expect(scan.run([lockfile])).to eq(0)
    expect(stderr.string).to include("issue search failed")
    expect(stderr.string).to include("boom")
  end

  it "appends the GitHub rate-limit footer when adapter recorded one" do
    allow(resolver).to receive(:resolve).and_return(project("rake", owner: "ruby", repo: "rake"))
    allow(adapter).to receive_messages(
      issues_matching_labels: { "ruby/rake" => [{ "number" => 1 }] },
      rate_limit: Struct.new(:limit, :remaining, :reset_at).new(
        5000, 4587, Time.utc(2026, 4, 30, 14, 32, 0)
      )
    )

    expect(scan.run([lockfile])).to eq(0)
    expect(stdout.string).to include("GitHub rate limit: 4,587 / 5,000 remaining · resets at 14:32 UTC")
  end

  it "omits the footer when the adapter has no rate-limit data (cache-only run)" do
    allow(resolver).to receive(:resolve).and_return(project("rake", owner: "ruby", repo: "rake"))
    allow(adapter).to receive(:issues_matching_labels).and_return({ "ruby/rake" => [{ "number" => 1 }] })

    expect(scan.run([lockfile])).to eq(0)
    expect(stdout.string).not_to include("GitHub rate limit")
  end

  it "appends a `· N claimed` suffix when the project has claimed issues" do
    allow(resolver).to receive(:resolve) do |gem|
      project(gem.name, owner: "ruby", repo: gem.name) if gem.name == "rubocop"
    end
    allow(adapter).to receive(:issues_matching_labels).and_return(
      "ruby/rubocop" => [{ "number" => 1 }, { "number" => 2 }]
    )
    allow(GemContribute::CLI::IssueAnnouncer).to receive(:fetch_claim_index)
      .and_return("ruby/rubocop" => [1])

    rubocop_only = File.join(File.expand_path("../../fixtures", __dir__), "Gemfile.rubocop_only.lock")
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

  describe "preferred_labels" do
    let(:tmpdir) { Dir.mktmpdir("gem-contribute-scan-config-") }
    let(:config) { GemContribute::Config.new(path: File.join(tmpdir, "config.yml")) }
    let(:scan_with_config) do
      described_class.new(stdout: stdout, stderr: stderr,
                          resolver: resolver, adapter: adapter, config: config)
    end

    after { FileUtils.rm_rf(tmpdir) }

    it "passes all preferred_labels to issues_matching_labels in a single call" do
      allow(resolver).to receive(:resolve).and_return(project("rake", owner: "ruby", repo: "rake"))
      allow(adapter).to receive(:issues_matching_labels)
        .with(anything, labels: ["good first issue", "good-first-issue", "help wanted"])
        .and_return({ "ruby/rake" => [{ "number" => 1 }] })

      expect(scan_with_config.run([lockfile])).to eq(0)
      expect(stdout.string).to match(/rake\s+1\s+/)
      expect(adapter).to have_received(:issues_matching_labels).once
    end

    it "uses custom preferred_labels from config" do
      config.set("preferred_labels", "help wanted")
      allow(resolver).to receive(:resolve).and_return(project("rake", owner: "ruby", repo: "rake"))
      allow(adapter).to receive(:issues_matching_labels)
        .with(anything, labels: ["help wanted"])
        .and_return({ "ruby/rake" => [{ "number" => 42 }] })

      expect(scan_with_config.run([lockfile])).to eq(0)
      expect(stdout.string).to match(/rake\s+1\s+/)
      expect(adapter).not_to have_received(:issues_matching_labels)
        .with(anything, labels: array_including("good first issue"))
    end
  end
end
