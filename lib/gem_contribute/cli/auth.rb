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

      def initialize(stdout: $stdout, stderr: $stderr, store: TokenStore.new, sleeper: ->(s) { Kernel.sleep(s) })
        @stdout = stdout
        @stderr = stderr
        @store = store
        @sleeper = sleeper
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
        @stdout.puts "First, copy your one-time code: #{device_code.user_code}"
        @stdout.puts "Then visit: #{device_code.verification_uri}"
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
    end
  end
end
