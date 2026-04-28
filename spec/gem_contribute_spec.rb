# frozen_string_literal: true

RSpec.describe GemContribute do
  it "has a version number" do
    expect(GemContribute::VERSION).to match(/\A\d+\.\d+\.\d+/)
  end
end
