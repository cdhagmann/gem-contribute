#!/usr/bin/env ruby
# frozen_string_literal: true

# Validates KICKED_THE_TIRES.yml against the schema documented in its header.
# Used by the auto-merge workflow (.github/workflows/auto-merge-kicked-tires.yml)
# and runnable locally:
#
#   ruby script/lint-kicked-tires.rb              # lint the canonical file
#   ruby script/lint-kicked-tires.rb path.yml     # lint a specific file
#
# Exits 0 on success, 1 on any schema violation, with a clear message.

require "yaml"
require "date"

PATH = ARGV[0] || "KICKED_THE_TIRES.yml"
ALLOWED_KEYS = %w[handle date note location].freeze
REQUIRED_KEYS = %w[handle date].freeze
HANDLE_PATTERN = /\A[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,38}[a-zA-Z0-9])?\z/ # GitHub handle rules
DATE_PATTERN = /\A\d{4}-\d{2}-\d{2}\z/
MAX_BYTES = 100_000 # 100KB — guards against runaway PRs

def fail!(msg)
  warn "✗ #{msg}"
  exit 1
end

fail! "file not found: #{PATH}" unless File.exist?(PATH)
fail! "file is suspiciously large (#{File.size(PATH)} bytes)" if File.size(PATH) > MAX_BYTES

begin
  data = YAML.safe_load_file(PATH, permitted_classes: [Date])
rescue Psych::SyntaxError => e
  fail! "YAML syntax error: #{e.message}"
end

fail! "top-level must be an array" unless data.is_a?(Array)
fail! "must have at least one entry" if data.empty?

handles = []
data.each_with_index do |entry, i|
  num = i + 1
  fail! "entry #{num}: must be a hash, got #{entry.class}" unless entry.is_a?(Hash)

  keys = entry.keys.map(&:to_s)
  unknown = keys - ALLOWED_KEYS
  fail! "entry #{num}: unknown keys: #{unknown.inspect} (allowed: #{ALLOWED_KEYS.inspect})" \
    unless unknown.empty?

  missing = REQUIRED_KEYS - keys
  fail! "entry #{num}: missing required keys: #{missing.inspect}" unless missing.empty?

  handle = entry["handle"]
  fail! "entry #{num}: handle must be a string" unless handle.is_a?(String)
  fail! "entry #{num}: handle must not start with '@' (use just the username)" \
    if handle.start_with?("@")
  fail! "entry #{num}: handle #{handle.inspect} doesn't look like a GitHub username" \
    unless handle.match?(HANDLE_PATTERN)

  date = entry["date"]
  date_ok = date.is_a?(Date) || (date.is_a?(String) && date.match?(DATE_PATTERN))
  fail! "entry #{num}: date must be YYYY-MM-DD" unless date_ok

  fail! "entry #{num}: note must be a string" if entry.key?("note") && !entry["note"].is_a?(String)

  if entry.key?("location") && !entry["location"].is_a?(String)
    fail! "entry #{num}: location must be a string (not a nested object)"
  end

  handles << handle
end

duplicates = handles.group_by(&:itself).select { |_, v| v.size > 1 }.keys
fail! "duplicate handles: #{duplicates.inspect}" unless duplicates.empty?

puts "✓ #{data.size} entries, all valid"
