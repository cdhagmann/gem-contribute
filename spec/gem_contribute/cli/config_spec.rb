# frozen_string_literal: true

require "stringio"

RSpec.describe GemContribute::CLI::Config do
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }
  let(:tmpdir) { Dir.mktmpdir("gem-contribute-cli-config-") }
  let(:config) { GemContribute::Config.new(path: File.join(tmpdir, "config.yml")) }
  let(:cli) { described_class.new(stdout: stdout, stderr: stderr, config: config) }

  after { FileUtils.rm_rf(tmpdir) }

  describe "set" do
    it "persists the value and prints confirmation" do
      expect(cli.run(%w[set clone_root /srv/oss])).to eq(0)
      expect(stdout.string).to include("clone_root = /srv/oss")
      expect(config.clone_root).to eq("/srv/oss")
    end

    it "exits 1 for an unknown key" do
      expect(cli.run(%w[set bad_key val])).to eq(1)
      expect(stderr.string).to include("unknown config key")
    end

    it "exits 2 when key or value is missing" do
      expect(cli.run(%w[set clone_root])).to eq(2)
    end
  end

  describe "get" do
    it "prints the configured value" do
      config.set("clone_root", "/srv/oss")
      expect(cli.run(%w[get clone_root])).to eq(0)
      expect(stdout.string).to include("/srv/oss")
    end

    it "prints a not-set message when the key has no value" do
      expect(cli.run(%w[get clone_root])).to eq(0)
      expect(stdout.string).to include("not set")
    end

    it "exits 1 for an unknown key" do
      expect(cli.run(%w[get bad_key])).to eq(1)
    end

    it "exits 2 when key is missing" do
      expect(cli.run(["get"])).to eq(2)
    end
  end

  describe "list" do
    it "prints the effective clone_root" do
      expect(cli.run(["list"])).to eq(0)
      expect(stdout.string).to include("clone_root")
    end
  end

  describe "help" do
    it "prints usage when given no subcommand" do
      expect(cli.run([])).to eq(0)
      expect(stdout.string).to include("clone_root")
    end
  end
end
