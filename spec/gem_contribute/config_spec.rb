# frozen_string_literal: true

RSpec.describe GemContribute::Config do
  let(:tmpdir) { Dir.mktmpdir("gem-contribute-config-") }
  let(:path) { File.join(tmpdir, "config.yml") }
  let(:config) { described_class.new(path: path) }

  after { FileUtils.rm_rf(tmpdir) }

  describe "#clone_root" do
    it "returns nil when no config file exists" do
      expect(config.clone_root).to be_nil
    end

    it "returns the configured value with ~ expanded" do
      File.write(path, YAML.dump("clone_root" => "~/Projects/oss"))
      expect(config.clone_root).to eq(File.expand_path("~/Projects/oss"))
    end

    it "returns an absolute path unchanged" do
      File.write(path, YAML.dump("clone_root" => "/srv/oss"))
      expect(config.clone_root).to eq("/srv/oss")
    end
  end

  describe "#set" do
    it "writes the value and makes it readable" do
      config.set("clone_root", "~/code/gems")
      reloaded = described_class.new(path: path)
      expect(reloaded.clone_root).to eq(File.expand_path("~/code/gems"))
    end

    it "raises ArgumentError for unknown keys" do
      expect { config.set("unknown_key", "value") }.to raise_error(ArgumentError, /unknown config key/)
    end
  end

  describe "#to_h" do
    it "returns an empty hash when no config file exists" do
      expect(config.to_h).to eq({})
    end

    it "returns the stored key/value pairs" do
      config.set("clone_root", "/srv/oss")
      expect(config.to_h).to eq("clone_root" => "/srv/oss")
    end
  end

  it "treats a corrupt config file as empty rather than crashing" do
    File.write(path, ":::not valid yaml:::")
    expect { described_class.new(path: path) }.not_to raise_error
    expect(described_class.new(path: path).clone_root).to be_nil
  end
end
