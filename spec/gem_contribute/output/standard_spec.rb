# frozen_string_literal: true

require "stringio"

RSpec.describe GemContribute::Output::Standard do
  let(:out) { StringIO.new }
  let(:err) { StringIO.new }
  let(:output) { described_class.new(out: out, err: err) }

  it "writes #info to stdout with a trailing newline" do
    output.info("hello")
    expect(out.string).to eq("hello\n")
    expect(err.string).to eq("")
  end

  it "writes #progress to stdout (currently a plain line; spinner lands in #30)" do
    output.progress("doing the thing...")
    expect(out.string).to eq("doing the thing...\n")
  end

  it "writes #warn to stderr without prefixing" do
    output.warn("Note: something soft happened")
    expect(err.string).to eq("Note: something soft happened\n")
    expect(out.string).to eq("")
  end

  it "writes #error to stderr without prefixing" do
    output.error("verb failed: reason")
    expect(err.string).to eq("verb failed: reason\n")
    expect(out.string).to eq("")
  end

  it "defaults out: $stdout and err: $stderr when not passed" do
    default = described_class.new
    expect(default.instance_variable_get(:@out)).to be($stdout)
    expect(default.instance_variable_get(:@err)).to be($stderr)
  end
end
