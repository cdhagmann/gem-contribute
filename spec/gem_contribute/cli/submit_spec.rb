# frozen_string_literal: true

require "stringio"

RSpec.describe GemContribute::CLI::Submit do
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }
  let(:tmpdir) { Dir.mktmpdir("gem-contribute-submit-") }
  let(:store) { GemContribute::TokenStore.new(path: File.join(tmpdir, "auth.json")) }
  let(:git) { instance_double(GemContribute::Git) }
  let(:adapter) { GemContribute::HostAdapters::GitHubAdapter.new(token: "gho_test") }
  let(:opener) { instance_double(Proc) }
  let(:cli) do
    described_class.new(
      stdout: stdout, stderr: stderr,
      git: git, store: store,
      adapter_factory: ->(**) { adapter },
      browser_opener: opener,
      working_dir: tmpdir
    )
  end

  before do
    store.store("github.com", access_token: "gho_test")
    allow(opener).to receive(:call).and_return(true)
    allow(git).to receive(:push)
    # Real `git` invocations from Submit#current_branch and #parse_remote
    # need to succeed against `tmpdir`. Initialize a real repo with the
    # remotes and branch the spec wants.
    Dir.chdir(tmpdir) do
      system("git init -q -b gem-contribute/issue-42")
      system("git remote add origin git@github.com:alice/sidekiq.git")
      system("git remote add upstream https://github.com/sidekiq/sidekiq.git")
    end
  end

  after { FileUtils.rm_rf(tmpdir) }

  it "exits 1 if the current branch isn't a gem-contribute branch" do
    Dir.chdir(tmpdir) { system("git checkout -q -b some-other-branch") }

    expect(cli.run([])).to eq(1)
    expect(stderr.string).to include("doesn't match")
  end

  it "falls back to a same-repo compare URL when no upstream remote is configured" do
    Dir.chdir(tmpdir) { system("git remote remove upstream") }
    allow(adapter).to receive(:issue)
      .with(have_attributes(owner: "alice", repo: "sidekiq"), 42)
      .and_return("title" => "Improve batching")

    expect(cli.run([])).to eq(0)

    expect(opener).to have_received(:call) do |url|
      # Same-repo form: no `<owner>:` prefix on the head ref.
      expect(url).to start_with("https://github.com/alice/sidekiq/compare/gem-contribute/issue-42?")
      expect(url).not_to include("alice:gem-contribute/issue-42")
    end
  end

  it "exits 1 if the origin remote isn't configured" do
    Dir.chdir(tmpdir) { system("git remote remove origin") }

    expect(cli.run([])).to eq(1)
    expect(stderr.string).to include("`origin` remote")
  end

  it "pushes the branch, builds a compare URL with title prefilled, and opens the browser",
     :aggregate_failures do
    allow(adapter).to receive(:issue)
      .with(have_attributes(owner: "sidekiq", repo: "sidekiq"), 42)
      .and_return("title" => "Improve batching")

    expect(cli.run([])).to eq(0)
    expect(git).to have_received(:push).with(tmpdir, "origin", "gem-contribute/issue-42")

    expect(opener).to have_received(:call) do |url|
      expect(url).to start_with("https://github.com/sidekiq/sidekiq/compare/alice:gem-contribute/issue-42?")
      expect(url).to include("expand=1")
      expect(url).to include(URI.encode_www_form_component("Fix #42: Improve batching"))
      expect(url).to include(URI.encode_www_form_component("Closes #42"))
    end

    expect(stdout.string).to include("Opened browser to:")
    expect(stdout.string).to include("/compare/")
  end

  it "still proceeds with a generic title if the issue lookup fails" do
    allow(adapter).to receive(:issue).and_raise(GemContribute::AdapterError, "rate limited")

    expect(cli.run([])).to eq(0)
    expect(stderr.string).to include("couldn't fetch issue title")
    expect(opener).to have_received(:call) do |url|
      expect(url).to include(URI.encode_www_form_component("Fix #42"))
    end
  end

  it "prints the URL when the browser fails to open" do
    allow(adapter).to receive(:issue).and_return("title" => "x")
    allow(opener).to receive(:call).and_return(false)

    expect(cli.run([])).to eq(0)
    expect(stdout.string).to include("Open this URL to file the PR:")
  end
end
