# frozen_string_literal: true

RSpec.describe GemContribute::Output::Null do
  let(:output) { described_class.new }

  it "responds to #info, #progress, #warn, #error and produces nothing" do
    expect(output.info("hi")).to be_nil
    expect(output.progress("hi")).to be_nil
    expect(output.warn("hi")).to be_nil
    expect(output.error("hi")).to be_nil
  end
end
