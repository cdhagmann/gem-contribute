# frozen_string_literal: true

module GemContribute
  module CLI
    # `gem-contribute open <gem>` — print the gem's GitHub URL and try to open
    # it in the default browser.
    #
    # Resolves `<gem>` the same way `issues` and `fix` do (RubyGems → Project,
    # with the `gem-contribute` self short-circuit). The browser opener is the
    # same platform-aware helper used by `auth login` and `submit`. As in those
    # verbs, the opener is injected at construction so specs never shell out.
    class Open
      include PlatformTools
      include Workflow

      USAGE = "Usage: gem-contribute open <gem>"

      def initialize(stdout: $stdout, stderr: $stderr, output: nil,
                     resolver: Resolver.new,
                     browser_opener: nil)
        @output = output || Output::Standard.new(out: stdout, err: stderr)
        @resolver = resolver
        @browser_opener = browser_opener || method(:default_browser_opener)
      end

      def run(argv)
        target = argv.shift
        if target.nil?
          @output.error(USAGE)
          return 2
        end

        project = resolve_target(target, verb: "open")
        return 1 if project.nil?

        url = "https://github.com/#{project.owner}/#{project.repo}"
        opened = @browser_opener.call(url)
        @output.info(opened ? "Opened browser to:" : "Open this URL in your browser:")
        @output.info("  #{url}")
        0
      end
    end
  end
end
