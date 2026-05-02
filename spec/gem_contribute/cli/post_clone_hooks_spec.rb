# frozen_string_literal: true

require "stringio"

RSpec.describe GemContribute::CLI::PostCloneHooks do
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }
  let(:runs) { { editor: [], ai: [] } }
  let(:config) { instance_double(GemContribute::Config, editor: nil, ai_tool: nil) }
  let(:hooks) do
    described_class.new(
      stdout: stdout, stderr: stderr,
      config: config,
      editor_runner: ->(cmd, path) { runs[:editor] << [cmd, path] },
      ai_runner: ->(cmd, path) { runs[:ai] << [cmd, path] }
    )
  end
  let(:path) { "/tmp/oss/sidekiq/sidekiq" }

  describe "open_editor (-e)" do
    context "when editor is configured" do
      let(:config) { instance_double(GemContribute::Config, editor: "code", ai_tool: nil) }

      it "calls editor_runner with the editor and path" do
        hooks.call(path, editor: true, ai_tool: false)
        expect(runs[:editor]).to eq([["code", path]])
      end
    end

    context "when only $EDITOR is set" do
      around do |example|
        original = ENV.fetch("EDITOR", nil)
        ENV["EDITOR"] = "vim"
        example.run
        ENV["EDITOR"] = original
      end

      it "falls back to $EDITOR" do
        hooks.call(path, editor: true, ai_tool: false)
        expect(runs[:editor]).to eq([["vim", path]])
      end
    end

    context "when neither editor nor $EDITOR is set" do
      around do |example|
        original = ENV.fetch("EDITOR", nil)
        ENV.delete("EDITOR")
        example.run
        ENV["EDITOR"] = original
      end

      it "prints a hint and skips" do
        hooks.call(path, editor: true, ai_tool: false)
        expect(stderr.string).to include("no editor configured")
        expect(runs[:editor]).to be_empty
      end
    end

    it "skips when the editor flag is false" do
      hooks.call(path, editor: false, ai_tool: false)
      expect(runs[:editor]).to be_empty
    end
  end

  describe "launch_ai (-a)" do
    context "when ai_tool is configured" do
      let(:config) { instance_double(GemContribute::Config, editor: nil, ai_tool: "claude .") }

      it "calls ai_runner with the configured command and path" do
        hooks.call(path, editor: false, ai_tool: true)
        expect(runs[:ai]).to eq([["claude .", path]])
      end
    end

    context "when ai_tool is not configured" do
      it "prints a hint and skips" do
        hooks.call(path, editor: false, ai_tool: true)
        expect(stderr.string).to include("no ai_tool configured")
        expect(runs[:ai]).to be_empty
      end
    end

    it "skips when the ai flag is false" do
      hooks.call(path, editor: false, ai_tool: false)
      expect(runs[:ai]).to be_empty
    end
  end

  context "when both flags are set" do
    let(:config) { instance_double(GemContribute::Config, editor: "code", ai_tool: "claude .") }

    it "runs editor first, then ai_tool" do
      hooks.call(path, editor: true, ai_tool: true)
      expect(runs[:editor]).to eq([["code", path]])
      expect(runs[:ai]).to eq([["claude .", path]])
    end
  end
end
