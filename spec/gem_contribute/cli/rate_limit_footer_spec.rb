# frozen_string_literal: true

require "stringio"
require "time"

RSpec.describe GemContribute::CLI::RateLimitFooter do
  let(:stdout) { StringIO.new }
  let(:adapter) { instance_double(GemContribute::HostAdapters::GitHubAdapter) }

  def rate_limit(remaining:, limit:, reset_at:)
    Struct.new(:limit, :remaining, :reset_at).new(limit, remaining, reset_at)
  end

  it "prints a one-line footer when adapter has rate-limit data" do
    allow(adapter).to receive(:rate_limit).and_return(
      rate_limit(remaining: 4587, limit: 5000, reset_at: Time.utc(2026, 4, 30, 14, 32, 0))
    )

    described_class.print(adapter: adapter, stdout: stdout)

    expect(stdout.string).to eq(
      "GitHub rate limit: 4,587 / 5,000 remaining · resets at 14:32 UTC\n"
    )
  end

  it "uses thousand-separators for both remaining and limit" do
    allow(adapter).to receive(:rate_limit).and_return(
      rate_limit(remaining: 12_345, limit: 100_000, reset_at: Time.utc(2026, 4, 30, 9, 0, 0))
    )

    described_class.print(adapter: adapter, stdout: stdout)

    expect(stdout.string).to include("12,345 / 100,000 remaining")
  end

  it "prints UTC even when reset_at is in another timezone" do
    # 14:32 UTC = 10:32 EDT; the footer must convert.
    allow(adapter).to receive(:rate_limit).and_return(
      rate_limit(
        remaining: 4587, limit: 5000,
        reset_at: Time.new(2026, 4, 30, 10, 32, 0, "-04:00")
      )
    )

    described_class.print(adapter: adapter, stdout: stdout)

    expect(stdout.string).to include("resets at 14:32 UTC")
  end

  it "prints nothing when adapter.rate_limit is nil (cache-only run)" do
    allow(adapter).to receive(:rate_limit).and_return(nil)

    described_class.print(adapter: adapter, stdout: stdout)

    expect(stdout.string).to eq("")
  end

  it "prints nothing when the adapter does not expose rate_limit at all" do
    bare_adapter = Object.new

    described_class.print(adapter: bare_adapter, stdout: stdout)

    expect(stdout.string).to eq("")
  end
end
