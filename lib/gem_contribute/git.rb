# frozen_string_literal: true

require "open3"

module GemContribute
  # Thin wrapper around the `git` CLI so callers can substitute a fake in
  # tests without shelling out. Uses Open3 with arg-list invocation (no shell)
  # so there's no injection surface.
  class Git
    def clone(url, target)
      run!(["git", "clone", url, target])
    end

    def checkout_branch(path, branch)
      run!(["git", "-C", path, "checkout", "-b", branch])
    end

    def add_remote(path, name, url)
      # Idempotent: if the remote already exists (e.g. reusing a clone)
      # we silently succeed rather than fail the whole flow.
      return if remote_exists?(path, name)

      run!(["git", "-C", path, "remote", "add", name, url])
    end

    def push(path, remote, branch)
      run!(["git", "-C", path, "push", "-u", remote, branch])
    end

    def remote_exists?(path, name)
      out, _err, status = Open3.capture3("git", "-C", path, "remote")
      status.success? && out.split("\n").include?(name)
    end

    def branch_exists?(path, branch)
      _out, _err, status = Open3.capture3("git", "-C", path,
                                          "rev-parse", "--verify", "--quiet",
                                          "refs/heads/#{branch}")
      status.success?
    end

    def run!(argv)
      _stdout, stderr_str, status = Open3.capture3(*argv)
      return if status.success?

      raise GemContribute::AdapterError, "git #{argv[1..].join(" ")} failed: #{stderr_str.strip}"
    end
  end
end
