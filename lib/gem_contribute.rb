# frozen_string_literal: true

require "zeitwerk"
require_relative "gem_contribute/version"
require_relative "gem_contribute/errors"

loader = Zeitwerk::Loader.for_gem
loader.ignore("#{__dir__}/gem_contribute/version.rb")
loader.ignore("#{__dir__}/gem_contribute/errors.rb")
loader.setup

module GemContribute
  SELF_PROJECT = Project.new(
    gem_name: "gem-contribute",
    host: "github.com",
    owner: "cdhagmann",
    repo: "gem-contribute",
    metadata: { self_injected: true }
  ).freeze
end
