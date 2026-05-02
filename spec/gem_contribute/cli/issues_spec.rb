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

  before { allow(resolver).to receive(:resolve).and_return(project) }
  # Default: footer is a no-op unless a test explicitly returns a RateLimit.
  before { allow(adapter).to receive(:rate_limit).and_return(nil) }

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

  it "lists issues with number, title, and URL" do
    allow(adapter).to receive(:issues).and_return(
      [issue(1234, "Fix trailing whitespace cop"),
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
    allow(adapter).to receive(:issues).and_return([])

    expect(cli.run(["rubocop"])).to eq(0)
    expect(stdout.string).to include("0 open")
    expect(stdout.string).to include("none")
  end

  it "exits 1 and prints an error when the adapter raises" do
    allow(adapter).to receive(:issues).and_raise(GemContribute::AdapterError, "rate limited")

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
      allow(adapter).to receive(:issues).with(rake_project, anything).and_return(
        [issue(99, "Fix task", owner: "ruby", repo: "rake")]
      )
      allow(adapter).to receive(:issues).with(sidekiq_project, anything).and_return([])

      expect(cli.run(["all"])).to eq(0)
      out = stdout.string
      expect(out).to include("rake")
      expect(out).to include("#99")
    end

    it "prints a summary message when no gems have issues" do
      allow(adapter).to receive(:issues).and_return([])

      expect(cli.run(["all"])).to eq(0)
      expect(stdout.string).to include("no good first issues found")
    end

    it "skips gems whose adapter call fails and continues" do
      allow(adapter).to receive(:issues).with(rake_project, anything).and_raise(
        GemContribute::AdapterError, "rate limited"
      )
      allow(adapter).to receive(:issues).with(sidekiq_project, anything).and_return(
        [issue(42, "Improve batching", owner: "sidekiq", repo: "sidekiq")]
      )

      expect(cli.run(["all"])).to eq(0)
      expect(stderr.string).to include("warning")
      expect(stdout.string).to include("#42")
    end
  end

  describe "rate-limit footer" do
    it "appends the footer after `issues <gem>` when adapter recorded one" do
      allow(adapter).to receive(:issues).and_return([issue(1, "x")])
      allow(adapter).to receive(:rate_limit).and_return(
        Struct.new(:limit, :remaining, :reset_at).new(5000, 4587, Time.utc(2026, 4, 30, 14, 32, 0))
      )

      expect(cli.run(["rubocop"])).to eq(0)
      expect(stdout.string).to include("GitHub rate limit: 4,587 / 5,000 remaining · resets at 14:32 UTC")
    end

    it "appends the footer after `issues all` when adapter recorded one" do
      allow(adapter).to receive(:issues).and_return([])
      allow(adapter).to receive(:rate_limit).and_return(
        Struct.new(:limit, :remaining, :reset_at).new(60, 12, Time.utc(2026, 4, 30, 9, 5, 0))
      )

      expect(cli.run(["all"])).to eq(0)
      expect(stdout.string).to include("GitHub rate limit: 12 / 60 remaining · resets at 09:05 UTC")
    end

    it "prints nothing extra when the adapter has no rate-limit data" do
      allow(adapter).to receive(:issues).and_return([])
      # rate_limit defaults to nil via the spec's top-level before block.

      expect(cli.run(["all"])).to eq(0)
      expect(stdout.string).not_to include("GitHub rate limit")
    end
  end
end
