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

  describe "#progress" do
    it "without a block falls back to plain #info-style puts" do
      output.progress("doing the thing...")
      expect(out.string).to eq("doing the thing...\n")
    end

    it "in non-TTY context (StringIO) puts the message and yields the block" do
      result = output.progress("doing the thing...") { 42 }
      expect(out.string).to eq("doing the thing...\n")
      expect(result).to eq(42)
    end

    it "in TTY context runs tty-spinner during the block and returns the block's value" do
      tty = instance_double(IO, tty?: true)
      allow(tty).to receive(:puts)
      tty_output = described_class.new(out: tty, err: err)
      spinner = instance_double(TTY::Spinner)
      allow(TTY::Spinner).to receive(:new).and_return(spinner)
      allow(spinner).to receive(:auto_spin)
      allow(spinner).to receive(:stop)

      result = tty_output.progress("forking...") { :work_done }

      expect(result).to eq(:work_done)
      expect(spinner).to have_received(:auto_spin)
      expect(spinner).to have_received(:stop)
    end

    it "stops the spinner even if the block raises" do
      tty = instance_double(IO, tty?: true)
      allow(tty).to receive(:puts)
      tty_output = described_class.new(out: tty, err: err)
      spinner = instance_double(TTY::Spinner)
      allow(TTY::Spinner).to receive(:new).and_return(spinner)
      allow(spinner).to receive(:auto_spin)
      allow(spinner).to receive(:stop)

      expect { tty_output.progress("forking...") { raise "boom" } }.to raise_error("boom")
      expect(spinner).to have_received(:stop)
    end
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
