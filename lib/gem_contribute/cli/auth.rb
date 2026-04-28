# frozen_string_literal: true

module GemContribute
  module CLI
    # `gem-contribute auth <subcommand>` — Stage 2 entry point for OAuth.
    #
    # Subcommands:
    #   login   — start device flow, poll for completion, persist the token
    #   status  — show whether a token is cached for github.com (and try to
    #             validate it by hitting /user)
    #   logout  — drop the cached token for github.com
    class Auth
      USAGE = <<~USAGE
        Usage: gem-contribute auth <subcommand>

        Subcommands:
          login    Authenticate with GitHub via OAuth device flow.
          status   Show whether you're authenticated.
          logout   Remove the cached token for github.com.
      USAGE

      DEFAULT_HOST = "github.com"

      def initialize(stdout: $stdout, stderr: $stderr, store: TokenStore.new,
                     sleeper: ->(s) { Kernel.sleep(s) },
                     browser_opener: nil, clipper: nil)
        @stdout = stdout
        @stderr = stderr
        @store = store
        @sleeper = sleeper
        @browser_opener = browser_opener || method(:default_browser_opener)
        @clipper = clipper || method(:default_clipper)
      end

      def run(argv)
        case argv.shift
        when "login"  then login
        when "status" then status
        when "logout" then logout
        when nil, "help", "-h", "--help"
          @stdout.puts USAGE
          0
        else
          @stderr.puts "gem-contribute: unknown auth subcommand"
          @stderr.puts USAGE
          2
        end
      end

      private

      def login
        device_code = GemContribute::Auth.request_device_code(GemContribute::Auth::CLIENT_ID)
        prompt_user(device_code)
        result = poll_loop(device_code)
        persist_or_report(result)
      rescue GemContribute::Auth::AuthError => e
        @stderr.puts "auth login failed: #{e.message}"
        1
      end

      def prompt_user(device_code)
        copied = @clipper.call(device_code.user_code)
        code_suffix = copied ? " (copied to clipboard)" : ""
        @stdout.puts "Your one-time code#{code_suffix}: #{device_code.user_code}"

        opened = @browser_opener.call(device_code.verification_uri)
        url_prefix = opened ? "Browser opened to" : "Visit"
        @stdout.puts "#{url_prefix}: #{device_code.verification_uri}"

        @stdout.puts "Waiting for you to authorize..."
      end

      def poll_loop(device_code)
        loop do
          if device_code.expired?
            return GemContribute::Auth::Result.new(status: :expired, token: nil, scope: nil, error_message: nil)
          end

          @sleeper.call(device_code.interval)
          result = GemContribute::Auth.poll(device_code, GemContribute::Auth::CLIENT_ID)

          case result.status
          when :pending then next
          when :slow_down then device_code = device_code.with_interval(device_code.interval + 5)
          else return result
          end
        end
      end

      def persist_or_report(result)
        case result.status
        when :ok
          @store.store(DEFAULT_HOST, access_token: result.token, scope: result.scope)
          @stdout.puts "Authenticated. Token saved to #{TokenStore.default_path} (mode 0600)."
          0
        when :expired
          @stderr.puts "Device code expired. Run `gem-contribute auth login` again."
          1
        when :denied
          @stderr.puts "Authorization denied."
          1
        else
          @stderr.puts "auth login failed: #{result.error_message}"
          1
        end
      end

      def status
        entry = @store.entry_for(DEFAULT_HOST)
        if entry.nil?
          @stdout.puts "Not authenticated. Run `gem-contribute auth login`."
          return 1
        end

        verify_and_print(entry)
      end

      def verify_and_print(entry)
        adapter = HostAdapters::GitHubAdapter.new(token: entry["access_token"])
        login_name = adapter.viewer_login
        @stdout.puts "Authenticated as @#{login_name} on #{DEFAULT_HOST} (scope: #{entry["scope"] || "unknown"})"
        0
      rescue GemContribute::AuthRequired, GemContribute::AdapterError => e
        @stderr.puts "Token cached for #{DEFAULT_HOST} but verification failed: #{e.message}"
        @stderr.puts "Run `gem-contribute auth login` to refresh."
        1
      end

      def logout
        if @store.delete(DEFAULT_HOST)
          @stdout.puts "Logged out of #{DEFAULT_HOST}."
        else
          @stdout.puts "No cached token for #{DEFAULT_HOST}."
        end
        0
      end

      def default_browser_opener(uri)
        cmd = case RbConfig::CONFIG["host_os"]
              when /darwin/           then "open"
              when /linux/            then "xdg-open"
              when /mswin|mingw|cygwin/ then "start"
              end
        cmd && Kernel.system(cmd, uri)
      rescue StandardError
        false
      end

      def default_clipper(text)
        case RbConfig::CONFIG["host_os"]
        when /darwin/
          IO.popen("pbcopy", "w") { |p| p.write(text) }
          true
        when /linux/
          IO.popen(["xclip", "-selection", "clipboard"], "w") { |p| p.write(text) }
          true
        end
      rescue StandardError
        false
      end
    end
  end
end
