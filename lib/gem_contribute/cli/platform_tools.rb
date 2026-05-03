# frozen_string_literal: true

module GemContribute
  module CLI
    module PlatformTools
      private

      def default_browser_opener(uri)
        cmd = case RbConfig::CONFIG["host_os"]
              when /darwin/             then "open"
              when /linux/              then "xdg-open"
              when /mswin|mingw|cygwin/ then "start"
              end
        cmd && Kernel.system(cmd, uri)
      rescue StandardError
        false
      end

      def default_clipper(text)
        cmd = case RbConfig::CONFIG["host_os"]
              when /darwin/ then "pbcopy"
              when /linux/  then ["xclip", "-selection", "clipboard"]
              end
        return false unless cmd

        IO.popen(cmd, "w") { |p| p.write(text) }
        true
      rescue StandardError
        false
      end
    end
  end
end
