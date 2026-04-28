# frozen_string_literal: true

RSpec.describe GemContribute::LockfileParser do
  let(:fixtures) { File.expand_path("../fixtures", __dir__) }

  describe ".parse" do
    it "returns LockedGem objects with name, version, and source classification" do
      gems = described_class.parse(File.join(fixtures, "Gemfile.simple.lock"))

      expect(gems.map(&:name)).to contain_exactly(
        "rake", "sidekiq", "connection_pool", "logger", "rack"
      )
      expect(gems).to all(be_a(GemContribute::LockedGem))
      expect(gems).to all(have_attributes(source_type: :rubygems))
    end

    it "returns the gem version as a string" do
      gems = described_class.parse(File.join(fixtures, "Gemfile.simple.lock"))

      sidekiq = gems.find { |g| g.name == "sidekiq" }
      expect(sidekiq.version).to eq("7.3.0")
    end

    it "tracks the rubygems remote URI for rubygems-sourced gems" do
      gems = described_class.parse(File.join(fixtures, "Gemfile.simple.lock"))

      rake = gems.find { |g| g.name == "rake" }
      expect(rake.source_uri).to eq("https://rubygems.org/")
      expect(rake).to be_resolvable
    end

    it "classifies git and path sources distinctly from rubygems", :aggregate_failures do
      gems = described_class.parse(File.join(fixtures, "Gemfile.mixed.lock"))

      some_gem = gems.find { |g| g.name == "some_gem" }
      local_gem = gems.find { |g| g.name == "local_gem" }
      rake = gems.find { |g| g.name == "rake" }

      expect(some_gem.source_type).to eq(:git)
      expect(some_gem.source_uri).to eq("https://github.com/example/some_gem.git")
      expect(some_gem).not_to be_resolvable

      expect(local_gem.source_type).to eq(:path)
      expect(local_gem).not_to be_resolvable

      expect(rake.source_type).to eq(:rubygems)
      expect(rake).to be_resolvable
    end

    it "raises LockfileNotFound when the file is missing" do
      expect { described_class.parse("/nonexistent/Gemfile.lock") }
        .to raise_error(GemContribute::LockfileNotFound, /no Gemfile.lock/)
    end

    it "returns an empty list for an empty lockfile rather than crashing" do
      # Bundler::LockfileParser is permissive: anything it can't make sense of
      # comes back as zero specs. We mirror that. The user-visible signal is
      # "0 gems" in the scan output, not an exception.
      Tempfile.create("empty-lockfile") do |f|
        f.write("")
        f.flush
        expect(described_class.parse(f.path)).to eq([])
      end
    end
  end
end
