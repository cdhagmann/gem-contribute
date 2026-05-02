# frozen_string_literal: true

require "stringio"

RSpec.describe GemContribute::CLI::Init do
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }
  let(:tmpdir) { Dir.mktmpdir("gem-contribute-cli-init-") }
  let(:config) { GemContribute::Config.new(path: File.join(tmpdir, "config.yml")) }
  let(:store) { GemContribute::TokenStore.new(path: File.join(tmpdir, "auth.json")) }
  let(:auth) { instance_double(GemContribute::CLI::Auth) }
  let(:inputs) { [""] }
  let(:cli) do
    described_class.new(
      stdout: stdout, stderr: stderr,
      config: config, store: store, auth: auth,
      gets: -> { inputs.shift }
    )
  end

  before { allow(auth).to receive(:run).and_return(0) }
  after { FileUtils.rm_rf(tmpdir) }

  context "when already authenticated" do
    before { store.store("github.com", access_token: "gho_test") }

    it "writes the default suggestion when the user accepts with Enter" do
      expect(cli.run([])).to eq(0)
      expect(stdout.string).to include("[~/code/oss]")
      expect(config.clone_root).to eq(File.expand_path("~/code/oss"))
      expect(stdout.string).to include("Clone root set to")
      expect(stdout.string).to include("already authenticated")
      expect(auth).not_to have_received(:run)
    end

    context "with a custom path" do
      let(:inputs) { ["~/projects/oss\n"] }

      it "writes the user-supplied path" do
        expect(cli.run([])).to eq(0)
        expect(config.clone_root).to eq(File.expand_path("~/projects/oss"))
      end
    end

    context "when re-run with a value already set" do
      before { config.set("clone_root", "/srv/oss") }

      it "shows the existing value as the default" do
        expect(cli.run([])).to eq(0)
        expect(stdout.string).to include("[/srv/oss]")
      end

      context "when the user accepts the existing value" do
        let(:inputs) { [""] }

        it "keeps the existing value" do
          expect(cli.run([])).to eq(0)
          expect(config.clone_root).to eq("/srv/oss")
        end
      end

      context "when the user supplies a new value" do
        let(:inputs) { ["/new/path\n"] }

        it "overwrites the existing value" do
          expect(cli.run([])).to eq(0)
          expect(config.clone_root).to eq("/new/path")
        end
      end
    end
  end

  context "when not authenticated" do
    context "when the user accepts the auth prompt with Enter" do
      let(:inputs) { ["", ""] }

      it "runs auth login" do
        expect(cli.run([])).to eq(0)
        expect(auth).to have_received(:run).with(["login"])
      end
    end

    context "when the user accepts the auth prompt with 'y'" do
      let(:inputs) { ["", "y"] }

      it "runs auth login" do
        expect(cli.run([])).to eq(0)
        expect(auth).to have_received(:run).with(["login"])
      end
    end

    context "when the user declines with 'n'" do
      let(:inputs) { ["", "n"] }

      it "skips auth login and prints a hint" do
        expect(cli.run([])).to eq(0)
        expect(auth).not_to have_received(:run)
        expect(stdout.string).to include("Skipping auth")
      end
    end

    context "when the user declines with 'no'" do
      let(:inputs) { ["", "no"] }

      it "skips auth login" do
        expect(cli.run([])).to eq(0)
        expect(auth).not_to have_received(:run)
      end
    end
  end

  it "prints usage on --help" do
    expect(cli.run(["--help"])).to eq(0)
    expect(stdout.string).to include("Usage:")
  end
end
