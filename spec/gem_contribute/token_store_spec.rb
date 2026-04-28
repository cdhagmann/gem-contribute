# frozen_string_literal: true

RSpec.describe GemContribute::TokenStore do
  let(:tmpdir) { Dir.mktmpdir("gem-contribute-token-") }
  let(:path) { File.join(tmpdir, "auth.json") }
  let(:store) { described_class.new(path: path, clock: -> { 1_234_567 }) }

  after { FileUtils.rm_rf(tmpdir) }

  it "returns nil for a host with no cached token" do
    expect(store.token_for("github.com")).to be_nil
  end

  it "round-trips a token per host" do
    store.store("github.com", access_token: "gho_abc", scope: "public_repo")
    expect(store.token_for("github.com")).to eq("gho_abc")
    expect(store.entry_for("github.com")).to include(
      "access_token" => "gho_abc",
      "scope" => "public_repo",
      "stored_at" => 1_234_567
    )
  end

  it "writes the file with mode 0600" do
    store.store("github.com", access_token: "gho_abc")
    expect(File.stat(path).mode & 0o777).to eq(0o600)
  end

  it "creates the parent directory if it doesn't exist" do
    nested = described_class.new(path: File.join(tmpdir, "nested", "deep", "auth.json"))
    nested.store("github.com", access_token: "gho_abc")
    expect(File.exist?(File.join(tmpdir, "nested", "deep", "auth.json"))).to be(true)
  end

  it "keeps tokens for other hosts when storing one" do
    store.store("github.com", access_token: "gho_abc")
    store.store("gitlab.com", access_token: "glpat_xyz")
    expect(store.token_for("github.com")).to eq("gho_abc")
    expect(store.token_for("gitlab.com")).to eq("glpat_xyz")
    expect(store.hosts).to contain_exactly("github.com", "gitlab.com")
  end

  it "deletes a host entry and leaves others alone" do
    store.store("github.com", access_token: "gho_abc")
    store.store("gitlab.com", access_token: "glpat_xyz")
    store.delete("github.com")
    expect(store.token_for("github.com")).to be_nil
    expect(store.token_for("gitlab.com")).to eq("glpat_xyz")
  end

  it "treats a corrupt file as empty rather than crashing" do
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "{not valid json")
    expect(store.token_for("github.com")).to be_nil
  end

  describe ".default_path" do
    it "honors XDG_CONFIG_HOME" do
      ENV["XDG_CONFIG_HOME"] = "/tmp/xdg-config-test"
      expect(described_class.default_path).to eq("/tmp/xdg-config-test/gem-contribute/auth.json")
    ensure
      ENV.delete("XDG_CONFIG_HOME")
    end
  end
end
