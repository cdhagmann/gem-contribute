# frozen_string_literal: true

require "stringio"

RSpec.describe GemContribute::CLI::Issues do
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }
  let(:resolver) { instance_double(GemContribute::Resolver) }
  let(:adapter) { instance_double(GemContribute::HostAdapters::GitHubAdapter) }
  let(:fixtures) { File.expand_path("../../fixtures", __dir__) }
  let(:lockfile) { File.join(fixtures, "Gemfile.simple.lock") }
  let(:cli) do
    described_class.new(stdout: stdout, stderr: stderr,
                        resolver: resolver, adapter: adapter,
                        lockfile_path: lockfile)
  end

  let(:project) do
    GemContribute::Project.new(
      gem_name: "rubocop", host: "github.com", owner: "rubocop", repo: "rubocop",
      metadata: {}
    )
  end

  def issue(number, title, owner: "rubocop", repo: "rubocop")
    {
      "number" => number,
      "title" => title,
      "html_url" => "https://github.com/#{owner}/#{repo}/issues/#{number}"
    }
  end

  before do
    allow(resolver).to receive(:resolve).and_return(project)
    allow(adapter).to receive(:rate_limit).and_return(nil)
    allow(GemContribute::CLI::IssueAnnouncer).to receive(:fetch_claim_index).and_return({})
  end

  it "exits 2 with usage when no gem name is given" do
    expect(cli.run([])).to eq(2)
    expect(stderr.string).to include("Usage:")
  end

  it "exits 1 when the gem does not resolve to github.com" do
    other = GemContribute::Project.new(
      gem_name: "internal", host: :unknown, owner: nil, repo: nil, metadata: {}
    )
    allow(resolver).to receive(:resolve).and_return(other)

    expect(cli.run(["internal"])).to eq(1)
    expect(stderr.string).to include("only github.com is supported")
  end

  it "prefixes claimed issues with a [claimed] label" do
    allow(adapter).to receive(:issues_matching_labels).and_return(
      "rubocop/rubocop" => [issue(1234, "Fresh title"), issue(5678, "Already-being-worked-on")]
    )
    allow(GemContribute::CLI::IssueAnnouncer).to receive(:fetch_claim_index)
      .and_return("rubocop/rubocop" => [5678])

    expect(cli.run(["rubocop"])).to eq(0)
    out = stdout.string
    expect(out).to match(/#1234  Fresh title/)
    expect(out).to match(/#5678  \[claimed\] Already-being-worked-on/)
  end

  it "lists issues with number, title, and URL" do
    allow(adapter).to receive(:issues_matching_labels).and_return(
      "rubocop/rubocop" => [issue(1234, "Fix trailing whitespace cop"),
                            issue(5678, "Add config option for XYZ")]
    )

    expect(cli.run(["rubocop"])).to eq(0)
    out = stdout.string
    expect(out).to include("#1234")
    expect(out).to include("Fix trailing whitespace cop")
    expect(out).to include("https://github.com/rubocop/rubocop/issues/1234")
    expect(out).to include("#5678")
    expect(out).to include("fix rubocop/<issue#>")
  end

  it "prints a friendly message when no issues are found" do
    allow(adapter).to receive(:issues_matching_labels).and_return({})

    expect(cli.run(["rubocop"])).to eq(0)
    expect(stdout.string).to include("0 open")
    expect(stdout.string).to include("none")
  end

  it "exits 1 and prints an error when the adapter raises" do
    allow(adapter).to receive(:issues_matching_labels).and_raise(GemContribute::AdapterError, "rate limited")

    expect(cli.run(["rubocop"])).to eq(1)
    expect(stderr.string).to include("rate limited")
  end

  describe "all" do
    # Fixture lockfile contains: rake, sidekiq, connection_pool, logger, rack
    let(:rake_project) do
      GemContribute::Project.new(
        gem_name: "rake", host: "github.com", owner: "ruby", repo: "rake", metadata: {}
      )
    end
    let(:sidekiq_project) do
      GemContribute::Project.new(
        gem_name: "sidekiq", host: "github.com", owner: "sidekiq", repo: "sidekiq", metadata: {}
      )
    end

    before do
      allow(resolver).to receive(:resolve) do |gem|
        case gem.name
        when "rake"    then rake_project
        when "sidekiq" then sidekiq_project
        else
          GemContribute::Project.new(gem_name: gem.name, host: :unknown,
                                     owner: nil, repo: nil, metadata: {})
        end
      end
    end

    it "iterates all github.com gems and prints only those with issues" do
      allow(adapter).to receive(:issues_matching_labels).and_return(
        "ruby/rake" => [issue(99, "Fix task", owner: "ruby", repo: "rake")]
      )

      expect(cli.run(["all"])).to eq(0)
      out = stdout.string
      expect(out).to include("rake")
      expect(out).to include("#99")
    end

    it "prints a summary message when no gems have issues" do
      allow(adapter).to receive(:issues_matching_labels).and_return({})

      expect(cli.run(["all"])).to eq(0)
      expect(stdout.string).to include("no contributable issues found")
    end

    it "warns and exits 0 when the batch search fails" do
      allow(adapter).to receive(:issues_matching_labels).and_raise(
        GemContribute::AdapterError, "rate limited"
      )

      expect(cli.run(["all"])).to eq(0)
      expect(stderr.string).to include("warning")
      expect(stderr.string).to include("rate limited")
    end
  end

  # rubocop:disable RSpec/MultipleMemoizedHelpers
  describe "preferred_labels" do
    let(:tmpdir) { Dir.mktmpdir("gem-contribute-issues-config-") }
    let(:config) { GemContribute::Config.new(path: File.join(tmpdir, "config.yml")) }
    let(:cli_with_config) do
      described_class.new(stdout: stdout, stderr: stderr,
                          resolver: resolver, adapter: adapter,
                          lockfile_path: lockfile, config: config)
    end

    after { FileUtils.rm_rf(tmpdir) }

    it "passes all preferred_labels to issues_matching_labels in a single call" do
      allow(adapter).to receive(:issues_matching_labels)
        .with(anything, labels: ["good first issue", "good-first-issue", "help wanted"])
        .and_return("rubocop/rubocop" => [issue(1234, "Shared issue"), issue(5678, "Other issue")])

      expect(cli_with_config.run(["rubocop"])).to eq(0)
      expect(stdout.string).to include("#1234")
      expect(stdout.string).to include("#5678")
      expect(adapter).to have_received(:issues_matching_labels).once
    end

    it "uses custom preferred_labels from config instead of defaults" do
      config.set("preferred_labels", "help wanted")
      allow(adapter).to receive(:issues_matching_labels)
        .with(anything, labels: ["help wanted"])
        .and_return("rubocop/rubocop" => [issue(99, "Help wanted issue")])

      expect(cli_with_config.run(["rubocop"])).to eq(0)
      expect(stdout.string).to include("#99")
      expect(adapter).not_to have_received(:issues_matching_labels)
        .with(anything, labels: array_including("good first issue"))
    end
  end
  # rubocop:enable RSpec/MultipleMemoizedHelpers

  describe "rate-limit footer" do
    it "appends the footer after `issues <gem>` when adapter recorded one" do
      allow(adapter).to receive_messages(
        issues_matching_labels: { "rubocop/rubocop" => [issue(1, "x")] },
        rate_limit: Struct.new(:limit, :remaining, :reset_at).new(
          5000, 4587, Time.utc(2026, 4, 30, 14, 32, 0)
        )
      )

      expect(cli.run(["rubocop"])).to eq(0)
      expect(stdout.string).to include("GitHub rate limit: 4,587 / 5,000 remaining · resets at 14:32 UTC")
    end

    it "appends the footer after `issues all` when adapter recorded one" do
      allow(adapter).to receive_messages(
        issues_matching_labels: {},
        rate_limit: Struct.new(:limit, :remaining, :reset_at).new(
          60, 12, Time.utc(2026, 4, 30, 9, 5, 0)
        )
      )

      expect(cli.run(["all"])).to eq(0)
      expect(stdout.string).to include("GitHub rate limit: 12 / 60 remaining · resets at 09:05 UTC")
    end

    it "prints nothing extra when the adapter has no rate-limit data" do
      allow(adapter).to receive(:issues_matching_labels).and_return({})

      expect(cli.run(["all"])).to eq(0)
      expect(stdout.string).not_to include("GitHub rate limit")
    end
  end
end
