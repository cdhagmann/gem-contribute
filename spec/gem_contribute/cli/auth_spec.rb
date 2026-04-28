# frozen_string_literal: true

require "stringio"

RSpec.describe GemContribute::CLI::Auth do
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }
  let(:tmpdir) { Dir.mktmpdir("gem-contribute-cli-auth-") }
  let(:store) { GemContribute::TokenStore.new(path: File.join(tmpdir, "auth.json")) }
  let(:sleeper) { ->(_secs) {} }
  let(:cli) { described_class.new(stdout: stdout, stderr: stderr, store: store, sleeper: sleeper) }

  before { stub_const("ENV", ENV.to_h.merge("GEM_CONTRIBUTE_CLIENT_ID" => "Iv1.testid")) }
  after { FileUtils.rm_rf(tmpdir) }

  describe "login" do
    def stub_device_code
      stub_request(:post, "https://github.com/login/device/code")
        .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                   body: JSON.dump("device_code" => "abc123", "user_code" => "WXYZ-1234",
                                   "verification_uri" => "https://github.com/login/device",
                                   "expires_in" => 900, "interval" => 5))
    end

    it "prints the user code, polls until success, and persists the token" do
      stub_device_code
      stub_request(:post, "https://github.com/login/oauth/access_token")
        .to_return(
          { status: 200, headers: { "Content-Type" => "application/json" },
            body: JSON.dump("error" => "authorization_pending") },
          { status: 200, headers: { "Content-Type" => "application/json" },
            body: JSON.dump("access_token" => "gho_real", "scope" => "public_repo") }
        )

      expect(cli.run(["login"])).to eq(0)

      out = stdout.string
      expect(out).to include("WXYZ-1234")
      expect(out).to include("https://github.com/login/device")
      expect(out).to include("Authenticated.")
      expect(store.token_for("github.com")).to eq("gho_real")
      expect(store.entry_for("github.com")["scope"]).to eq("public_repo")
    end

    it "extends the polling interval on slow_down" do
      stub_device_code
      stub_request(:post, "https://github.com/login/oauth/access_token")
        .to_return(
          { status: 200, headers: { "Content-Type" => "application/json" },
            body: JSON.dump("error" => "slow_down") },
          { status: 200, headers: { "Content-Type" => "application/json" },
            body: JSON.dump("access_token" => "gho_real", "scope" => "public_repo") }
        )

      sleeps = []
      cli = described_class.new(stdout: stdout, stderr: stderr, store: store,
                                sleeper: ->(s) { sleeps << s })

      expect(cli.run(["login"])).to eq(0)
      expect(sleeps).to eq([5, 10]) # initial 5s, then bumped to 10s after slow_down
    end

    it "exits 1 with a clear message on access_denied" do
      stub_device_code
      stub_request(:post, "https://github.com/login/oauth/access_token")
        .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                   body: JSON.dump("error" => "access_denied"))

      expect(cli.run(["login"])).to eq(1)
      expect(stderr.string).to include("Authorization denied")
    end

    it "exits 1 if the device code request itself fails" do
      stub_request(:post, "https://github.com/login/device/code").to_return(status: 503)
      expect(cli.run(["login"])).to eq(1)
      expect(stderr.string).to include("auth login failed")
    end
  end

  describe "status" do
    it "exits 1 with a clear message when no token is cached" do
      expect(cli.run(["status"])).to eq(1)
      expect(stdout.string).to include("Not authenticated")
    end

    it "validates the cached token by hitting GET /user and prints the login" do
      store.store("github.com", access_token: "gho_real", scope: "public_repo")
      stub_request(:get, "https://api.github.com/user")
        .with(headers: { "Authorization" => "Bearer gho_real" })
        .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                   body: JSON.dump("login" => "alice"))

      expect(cli.run(["status"])).to eq(0)
      expect(stdout.string).to include("Authenticated as @alice")
      expect(stdout.string).to include("public_repo")
    end

    it "exits 1 when the cached token is no longer valid" do
      store.store("github.com", access_token: "gho_stale")
      stub_request(:get, "https://api.github.com/user").to_return(status: 401)

      expect(cli.run(["status"])).to eq(1)
      expect(stderr.string).to include("verification failed")
    end
  end

  describe "logout" do
    it "drops the cached token and reports success" do
      store.store("github.com", access_token: "gho_real")
      expect(cli.run(["logout"])).to eq(0)
      expect(stdout.string).to include("Logged out")
      expect(store.token_for("github.com")).to be_nil
    end

    it "is a no-op if no token was cached" do
      expect(cli.run(["logout"])).to eq(0)
      expect(stdout.string).to include("No cached token")
    end
  end

  describe "help" do
    it "prints usage when given no subcommand" do
      expect(cli.run([])).to eq(0)
      expect(stdout.string).to include("login")
      expect(stdout.string).to include("status")
      expect(stdout.string).to include("logout")
    end
  end
end
