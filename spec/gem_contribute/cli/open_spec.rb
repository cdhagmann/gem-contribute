# frozen_string_literal: true

require "stringio"

RSpec.describe GemContribute::CLI::Open do
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }
  let(:resolver) { instance_double(GemContribute::Resolver) }
  let(:opened_urls) { [] }
  let(:browser_opener) { ->(url) { opened_urls << url; true } }
  let(:cli) do
    described_class.new(stdout: stdout, stderr: stderr,
                        resolver: resolver, browser_opener: browser_opener)
  end

  let(:project) do
    GemContribute::Project.new(
      gem_name: "rubocop", host: "github.com",
      owner: "rubocop", repo: "rubocop", metadata: {}
    )
  end

  it "exits 2 with a usage message when no gem name is given" do
    expect(cli.run([])).to eq(2)
    expect(stderr.string).to include("Usage: gem-contribute open <gem>")
  end

  it "opens the resolved repo URL in the browser and prints it" do
    allow(resolver).to receive(:resolve).and_return(project)

    expect(cli.run(["rubocop"])).to eq(0)
    expect(opened_urls).to eq(["https://github.com/rubocop/rubocop"])
    out = stdout.string
    expect(out).to include("Opened browser to:")
    expect(out).to include("https://github.com/rubocop/rubocop")
  end

  it "still prints the URL when the browser opener returns false" do
    allow(resolver).to receive(:resolve).and_return(project)
    failing_opener = ->(_url) { false }
    cli = described_class.new(stdout: stdout, stderr: stderr,
                              resolver: resolver, browser_opener: failing_opener)

    expect(cli.run(["rubocop"])).to eq(0)
    out = stdout.string
    expect(out).to include("Open this URL in your browser:")
    expect(out).to include("https://github.com/rubocop/rubocop")
  end

  it "exits 1 with a clear message when the gem resolves to a non-github.com host" do
    other = GemContribute::Project.new(
      gem_name: "internal", host: :unknown, owner: nil, repo: nil, metadata: {}
    )
    allow(resolver).to receive(:resolve).and_return(other)

    expect(cli.run(["internal"])).to eq(1)
    expect(stderr.string).to include("only github.com is supported")
    expect(opened_urls).to be_empty
  end

  it "self-resolves `gem-contribute` without hitting the resolver" do
    expect(resolver).not_to receive(:resolve)

    expect(cli.run(["gem-contribute"])).to eq(0)
    expect(opened_urls).to eq([
                                "https://github.com/#{GemContribute::SELF_PROJECT.owner}/" \
                                "#{GemContribute::SELF_PROJECT.repo}"
                              ])
  end
end
