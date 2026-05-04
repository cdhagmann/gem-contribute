# frozen_string_literal: true

require "dry/monads"

RSpec.describe GemContribute::Operations::Branch do
  include Dry::Monads[:result]

  let(:git) { instance_double(GemContribute::Git) }
  let(:operation) { described_class.new(git: git) }

  it "creates a gem-contribute/issue-<N> branch and returns Success(Result(name:))" do
    allow(git).to receive(:checkout_branch)

    result = operation.call(path: "/clone/path", issue: "1234")

    expect(result).to be_success
    expect(result.value!).to have_attributes(name: "gem-contribute/issue-1234")
    expect(git).to have_received(:checkout_branch).with("/clone/path", "gem-contribute/issue-1234")
  end

  it "accepts an integer issue number" do
    allow(git).to receive(:checkout_branch)

    result = operation.call(path: "/clone/path", issue: 7)

    expect(result.value!.name).to eq("gem-contribute/issue-7")
  end

  it "returns Failure([:adapter_error, message]) when git raises AdapterError" do
    allow(git).to receive(:checkout_branch)
      .and_raise(GemContribute::AdapterError, "fatal: branch already exists")

    result = operation.call(path: "/clone/path", issue: "1")

    expect(result).to eq(Failure([:adapter_error, "fatal: branch already exists"]))
  end
end
