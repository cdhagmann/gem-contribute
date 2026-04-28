# frozen_string_literal: true

RSpec.describe GemContribute::Cache do
  let(:root) { File.join(Dir.tmpdir, "gem-contribute-cache-#{SecureRandom.hex(4)}") }
  let(:clock) { instance_double(Proc) }
  let(:cache) do
    described_class.new(
      root: root,
      ttl: { "gems" => 100, "issues" => 10 },
      clock: clock
    )
  end

  before { allow(clock).to receive(:call).and_return(1_000) }
  after { FileUtils.rm_rf(root) }

  it "returns nil on a miss" do
    expect(cache.fetch("gems", "rake")).to be_nil
  end

  it "round-trips a payload" do
    cache.write("gems", "rake", { "name" => "rake" })
    expect(cache.fetch("gems", "rake")).to eq({ "name" => "rake" })
  end

  it "expires entries past the namespace TTL" do
    cache.write("issues", "sidekiq/sidekiq", [{ "number" => 1 }])

    allow(clock).to receive(:call).and_return(1_000 + 11) # past 10s TTL
    expect(cache.fetch("issues", "sidekiq/sidekiq")).to be_nil
  end

  it "treats unknown namespaces as never-expiring" do
    odd = described_class.new(root: root, ttl: {}, clock: clock)
    odd.write("misc", "thing", "value")
    allow(clock).to receive(:call).and_return(1_000_000_000)
    expect(odd.fetch("misc", "thing")).to eq("value")
  end

  it "hashes keys with slashes so they stay flat on disk" do
    cache.write("issues", "sidekiq/sidekiq", [])
    files = Dir.glob(File.join(root, "issues", "*"))
    expect(files.size).to eq(1)
    expect(File.basename(files.first)).to match(/\A[0-9a-f]{64}\.json\z/)
  end

  it "ignores corrupt cache files instead of crashing" do
    cache.write("gems", "rake", { "name" => "rake" })
    Dir.glob(File.join(root, "gems", "*")).each { |f| File.write(f, "{not json") }
    expect(cache.fetch("gems", "rake")).to be_nil
  end

  it "wipes all namespaces on clear!" do
    cache.write("gems", "rake", { "x" => 1 })
    cache.write("issues", "sidekiq/sidekiq", [])
    cache.clear!
    expect(File.directory?(root)).to be(false)
  end

  describe ".default_root" do
    it "honors XDG_CACHE_HOME" do
      ENV["XDG_CACHE_HOME"] = "/tmp/xdg-test"
      expect(described_class.default_root).to eq("/tmp/xdg-test/gem-contribute")
    ensure
      ENV.delete("XDG_CACHE_HOME")
    end

    it "falls back to ~/.cache when XDG_CACHE_HOME is unset" do
      ENV.delete("XDG_CACHE_HOME")
      expect(described_class.default_root).to eq(File.expand_path("~/.cache/gem-contribute"))
    end
  end
end
