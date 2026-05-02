# frozen_string_literal: true

source "https://rubygems.org"

gemspec

group :development, :test do
  gem "irb"
  # Keep parallel on the 1.x line so dev/CI work on Ruby 3.2 (the floor
  # in the gemspec). parallel 2.x requires Ruby 3.3+.
  gem "parallel", "< 2"
  gem "rake", "~> 13.0"
  gem "rspec", "~> 3.13"
  gem "rubocop", "~> 1.60"
  gem "rubocop-rake", "~> 0.6"
  gem "rubocop-rspec", "~> 3.0"
  gem "vcr", "~> 6.3"
  gem "webmock", "~> 3.23"
end
