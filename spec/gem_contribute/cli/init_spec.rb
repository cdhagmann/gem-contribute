# frozen_string_literal: true

require "stringio"

RSpec.describe GemContribute::CLI::Init do
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }
  let(:tmpdir) { Dir.mktmpdir("gem-contribute-cli-init-") }
  let(:config) { GemContribute::Config.new(path: File.join(tmpdir, "config.yml")) }
  let(:input) { "" }
  let(:cli) do
    described_class.new(
      stdout: stdout, stderr: stderr,
      config: config, gets: -> { input }
    )
  end

  after { FileUtils.rm_rf(tmpdir) }

  it "writes the default suggestion when the user accepts with Enter" do
    expect(cli.run([])).to eq(0)
    expect(stdout.string).to include("[~/code/oss]")
    expect(config.clone_root).to eq(File.expand_path("~/code/oss"))
    expect(stdout.string).to include("Clone root set to")
  end

  context "with a custom path" do
    let(:input) { "~/projects/oss\n" }

    it "writes the user-supplied path" do
      expect(cli.run([])).to eq(0)
      expect(config.clone_root).to eq(File.expand_path("~/projects/oss"))
      expect(stdout.string).to include("Clone root set to #{File.expand_path("~/projects/oss")}")
    end
  end

  context "when re-run with a value already set" do
    before { config.set("clone_root", "/srv/oss") }

    it "shows the existing value as the default" do
      expect(cli.run([])).to eq(0)
      expect(stdout.string).to include("[/srv/oss]")
    end

    context "when the user accepts the existing value" do
      let(:input) { "" }

      it "keeps the existing value" do
        expect(cli.run([])).to eq(0)
        expect(config.clone_root).to eq("/srv/oss")
      end
    end

    context "when the user supplies a new value" do
      let(:input) { "/new/path\n" }

      it "overwrites the existing value" do
        expect(cli.run([])).to eq(0)
        expect(config.clone_root).to eq("/new/path")
      end
    end
  end

  it "prints usage on --help" do
    expect(cli.run(["--help"])).to eq(0)
    expect(stdout.string).to include("Usage:")
  end
end
