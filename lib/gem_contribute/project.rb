# frozen_string_literal: true

module GemContribute
  # A gem resolved to a host repository.
  #
  # `host` is one of: "github.com", "gitlab.com", "codeberg.org", or :unknown.
  # When :unknown, owner/repo are nil and `metadata` may carry whatever URI we
  # found so the user can at least see it.
  Project = Data.define(:gem_name, :host, :owner, :repo, :metadata) do
    def known_host?
      host.is_a?(String)
    end

    def url
      return metadata[:source_url] if metadata && !known_host?
      return nil unless owner && repo

      "https://#{host}/#{owner}/#{repo}"
    end
  end
end
