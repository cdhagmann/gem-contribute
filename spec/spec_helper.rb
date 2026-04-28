# frozen_string_literal: true

require "fileutils"
require "securerandom"
require "tempfile"
require "tmpdir"
require "vcr"
require "webmock/rspec"

# GemContribute::Auth::CLIENT_ID is read from this env var at module load
# time. If it's unset when auth.rb autoloads, the constant freezes to the
# placeholder sentinel and every later spec that exercises auth fails. Set
# a benign test-only value before the autoload window opens.
ENV["GEM_CONTRIBUTE_CLIENT_ID"] ||= "Iv1.testid"

require "gem_contribute"

VCR.configure do |config|
  config.cassette_library_dir = File.expand_path("cassettes", __dir__)
  config.hook_into :webmock
  config.default_cassette_options = {
    record: :once,
    match_requests_on: %i[method uri]
  }
  config.configure_rspec_metadata!
  # Don't let env-leaked tokens land in cassettes.
  config.filter_sensitive_data("<GITHUB_TOKEN>") { ENV.fetch("GITHUB_TOKEN", nil) }
end

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed

  # Each example gets its own cache root so tests stay hermetic.
  config.around do |example|
    Dir.mktmpdir("gem-contribute-spec-") do |tmp|
      ENV["XDG_CACHE_HOME"] = tmp
      example.run
    ensure
      ENV.delete("XDG_CACHE_HOME")
    end
  end
end
