# frozen_string_literal: true

require "shellwords"

module GemContribute
  module CLI
    # Optional post-clone hooks invoked by `fix` when the user passes
    # `-e` (open editor) and/or `-a` (launch AI tool). Extracted so the
    # `fix` state machine stays focused on the fork/clone/branch
    # sequence.
    class PostCloneHooks
      def initialize(stdout: $stdout, stderr: $stderr,
                     config: GemContribute::Config.new,
                     editor_runner: ->(cmd, path) { Kernel.system("#{cmd} #{path.shellescape}") },
                     ai_runner: ->(cmd, path) { Kernel.system(cmd, chdir: path) })
        @stdout = stdout
        @stderr = stderr
        @config = config
        @editor_runner = editor_runner
        @ai_runner = ai_runner
      end

      def call(local_path, editor:, ai_tool:)
        open_editor(local_path) if editor
        launch_ai(local_path)   if ai_tool
      end

      private

      def open_editor(local_path)
        editor = @config.editor || ENV.fetch("EDITOR", nil)
        if editor.nil? || editor.empty?
          @stderr.puts "-e: no editor configured. " \
                       "Set with `gem-contribute config set editor <cmd>` or set $EDITOR."
          return
        end
        @editor_runner.call(editor, local_path)
      end

      def launch_ai(local_path)
        ai_tool = @config.ai_tool
        if ai_tool.nil? || ai_tool.empty?
          @stderr.puts "-a: no ai_tool configured. " \
                       "Set with `gem-contribute config set ai_tool \"<cmd>\"`."
          return
        end
        @ai_runner.call(ai_tool, local_path)
      end
    end
  end
end
