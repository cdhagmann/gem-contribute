# frozen_string_literal: true

RSpec.describe GemContribute::Auth do
  let(:client_id) { "Iv1.testid" }
  let(:fixed_now) { Time.utc(2026, 4, 28, 12, 0, 0) }
  let(:clock) { -> { fixed_now } }

  before { stub_const("ENV", ENV.to_h.merge("GEM_CONTRIBUTE_CLIENT_ID" => client_id)) }

  describe ".request_device_code" do
    it "POSTs client_id and scope to GitHub's device-code endpoint and returns a DeviceCode" do
      stub_request(:post, "https://github.com/login/device/code")
        .with(body: hash_including("client_id" => client_id, "scope" => "public_repo"))
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.dump(
            "device_code" => "abc123",
            "user_code" => "WXYZ-ABCD",
            "verification_uri" => "https://github.com/login/device",
            "expires_in" => 900,
            "interval" => 5
          )
        )

      result = described_class.request_device_code(client_id, clock: clock)

      expect(result.device_code).to eq("abc123")
      expect(result.user_code).to eq("WXYZ-ABCD")
      expect(result.verification_uri).to eq("https://github.com/login/device")
      expect(result.expires_at).to eq(fixed_now + 900)
      expect(result.interval).to eq(5)
    end

    it "raises AuthError on a non-200 response" do
      stub_request(:post, "https://github.com/login/device/code").to_return(status: 503, body: "")
      expect { described_class.request_device_code(client_id, clock: clock) }
        .to raise_error(GemContribute::Auth::AuthError, /HTTP 503/)
    end

    it "raises AuthError when GitHub returns an error body" do
      stub_request(:post, "https://github.com/login/device/code")
        .to_return(status: 200, body: JSON.dump("error" => "device_flow_disabled"),
                   headers: { "Content-Type" => "application/json" })

      expect { described_class.request_device_code(client_id, clock: clock) }
        .to raise_error(GemContribute::Auth::AuthError, /device_flow_disabled/)
    end

    it "raises AuthError when CLIENT_ID is the placeholder sentinel" do
      expect { described_class.request_device_code("FILL_ME_IN_FROM_MAINTAINER_MD") }
        .to raise_error(GemContribute::Auth::AuthError, /MAINTAINER.md/)
    end
  end

  describe ".poll" do
    let(:device_code) do
      GemContribute::Auth::DeviceCode.new(
        device_code: "abc123",
        user_code: "WXYZ-ABCD",
        verification_uri: "https://github.com/login/device",
        expires_at: fixed_now + 900,
        interval: 5
      )
    end

    def stub_token(body)
      stub_request(:post, "https://github.com/login/oauth/access_token")
        .with(body: hash_including("client_id" => client_id, "device_code" => "abc123"))
        .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: JSON.dump(body))
    end

    it "returns :ok with token and scope when GitHub issues an access_token" do
      stub_token("access_token" => "gho_abc", "token_type" => "bearer", "scope" => "public_repo")
      result = described_class.poll(device_code, client_id)
      expect(result.status).to eq(:ok)
      expect(result.token).to eq("gho_abc")
      expect(result.scope).to eq("public_repo")
    end

    it "returns :pending while the user has not completed the flow" do
      stub_token("error" => "authorization_pending")
      expect(described_class.poll(device_code, client_id).status).to eq(:pending)
    end

    it "returns :slow_down so the caller can extend the polling interval" do
      stub_token("error" => "slow_down")
      expect(described_class.poll(device_code, client_id).status).to eq(:slow_down)
    end

    it "returns :expired when the device code has timed out server-side" do
      stub_token("error" => "expired_token")
      expect(described_class.poll(device_code, client_id).status).to eq(:expired)
    end

    it "returns :denied when the user rejected the prompt" do
      stub_token("error" => "access_denied")
      expect(described_class.poll(device_code, client_id).status).to eq(:denied)
    end

    it "returns :error on unknown error codes" do
      stub_token("error" => "incorrect_device_code")
      result = described_class.poll(device_code, client_id)
      expect(result.status).to eq(:error)
      expect(result.error_message).to eq("incorrect_device_code")
    end

    it "returns :error on a non-200 response" do
      stub_request(:post, "https://github.com/login/oauth/access_token").to_return(status: 502)
      result = described_class.poll(device_code, client_id)
      expect(result.status).to eq(:error)
      expect(result.error_message).to match(/502/)
    end
  end

  describe "DeviceCode#expired?" do
    let(:dc) do
      GemContribute::Auth::DeviceCode.new(
        device_code: "x", user_code: "X", verification_uri: "x",
        expires_at: fixed_now + 60, interval: 5
      )
    end

    it "is false before expiry" do
      expect(dc.expired?(now: fixed_now + 30)).to be(false)
    end

    it "is true at expiry exactly" do
      expect(dc.expired?(now: fixed_now + 60)).to be(true)
    end

    it "is true after expiry" do
      expect(dc.expired?(now: fixed_now + 61)).to be(true)
    end
  end

  describe "DeviceCode#with_interval" do
    let(:dc) do
      GemContribute::Auth::DeviceCode.new(
        device_code: "x", user_code: "X", verification_uri: "x",
        expires_at: fixed_now + 60, interval: 5
      )
    end

    it "returns a new DeviceCode with the new interval and other fields preserved" do
      bumped = dc.with_interval(10)
      expect(bumped.interval).to eq(10)
      expect(bumped.device_code).to eq(dc.device_code)
      expect(bumped.expires_at).to eq(dc.expires_at)
    end
  end
end
