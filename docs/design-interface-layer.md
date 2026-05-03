# Interface Layer Design

This document describes the multi-interface architecture introduced by [ADR-0012](adr/0012-output-free-service-objects-three-interface-architecture.md). It is the reference for all work that touches the boundary between service objects and the three output vectors: CLI, TUI, and gem plugin. Read it before changing anything in `lib/gem_contribute/cli/` or `lib/gem_contribute/operations/`.

For the broader system architecture — parsers, resolvers, the host adapter interface, caching — see [`design.md`](design.md).

## The problem with the current boundary

`Operations::Fork` and `Operations::Clone` accept `stdout:` and print progress during `call`:

```ruby
def call(adapter:, project:)
  @stdout.puts "Forking #{project.owner}/#{project.repo}..."
  fork = adapter.fork(project)
  @stdout.puts fork.reused ? "  Reusing existing fork." : "  Forked → ..."
  Result.new(...)
end
```

This works for a single CLI, but breaks across three interfaces:

- The **TUI** has no output stream. Progress is model state rendered by `View`, not a string printed to stdout. There is no clean way to route `@stdout.puts` into a Rooibos model update.
- The **gem plugin** needs to own its own output formatting and cannot share stdout injection with the CLI.
- **Tests** must assert on stdout side effects instead of return values, coupling test setup to I/O concerns.

The same problem appears in `Workflow#build_adapter`, which returns `nil` and prints to stderr on failure — two concerns collapsed into one method.

## Target architecture

Three interface layers share one service layer. The service layer produces no output. Each interface layer translates `Result` values into the output appropriate for its medium.

```
                          Service Layer
    ┌────────────────────────────────────────────────────┐
    │  Operations::Fork    Operations::Clone             │
    │  Operations::FixPipeline    Resolver               │
    │  HostAdapter         Auth          Git             │
    │                                                    │
    │  Returns Success(Result) | Failure(reason)         │
    │  No stdout. No stderr. No exceptions across layers.│
    └───────────────┬───────────────────┬────────────────┘
                    │                   │                │
                    ▼                   ▼                ▼
        ┌───────────────┐   ┌───────────────┐   ┌──────────────┐
        │  CLI Pipeline │   │  TUI Pipeline │   │  gem plugin  │
        │               │   │               │   │  Pipeline    │
        │  Output::     │   │  Commands +   │   │              │
        │  Standard     │   │  Update       │   │  reuses CLI  │
        │  tty-spinner  │   │               │   │  pipeline    │
        │  tty-prompt   │   │               │   │              │
        └───────────────┘   └───────────────┘   └──────────────┘
```

The three interface pipelines are entirely separate. A change to CLI output formatting has zero effect on the TUI. A new service object needs no knowledge of any interface.

## Service layer

### Result types

Every operation returns a `dry-monads` `Result`:

- `Success(value)` on the happy path — `value` is a `Data` struct.
- `Failure(reason)` for expected failure conditions — `reason` is a symbol or tagged tuple.

```ruby
Success(Operations::Fork::Result.new(clone_url:, fork_url:, upstream_url:, viewer:, reused:))

Failure(:unauthenticated)
Failure(:adapter_error, "rate limit exceeded")
```

Typed exceptions (`AuthRequired`, `AdapterError`) are not used as cross-layer signals. They may be raised and rescued within a single operation but do not propagate to callers.

### No I/O

Operations accept no `stdout:` or `stderr:` parameter. The `# rubocop:disable Metrics/ParameterLists` suppressions in the current `CLI::Fork` and `CLI::Fix` initializers are a symptom of this pattern — the extra `stdout:` and `stderr:` parameters inflate every constructor. `dry-initializer` replaces the verbose initializer pattern and the suppressions go away:

```ruby
class Operations::Fork
  extend Dry::Initializer
  # No stdout:. No stderr:. Pure computation.
end
```

### Multi-step pipelines

The `fix` flow (fork → clone → branch → announce) is a `dry-operation` pipeline. Each step receives a shared context, enriches it, and returns `Success(enriched)` or `Failure(reason)`. Failure at any step short-circuits the chain — no early returns, no nil checks.

```ruby
class Operations::FixPipeline
  include Dry::Operation

  def call(adapter:, project:, issue:, viewer:)
    fork_result  = step Operations::Fork.new.call(adapter:, project:)
    clone_result = step Operations::Clone.new.call(adapter:, project:, fork_result:)
    branch_name  = step Operations::Branch.new.call(path: clone_result.path, issue:)
    step Operations::Announce.new.call(adapter:, project:, issue:, viewer:, was_resuming: clone_result.reused)
    Success({ fork: fork_result, clone: clone_result, branch: branch_name })
  end
end
```

Both the CLI and TUI call `FixPipeline` rather than wiring the steps themselves.

### `Workflow#build_adapter`

Currently returns `nil` and prints to stderr. Under the new contract:

```ruby
def build_adapter
  token = @store.token_for("github.com")
  return Failure(:unauthenticated) if token.nil?

  Success(@adapter_factory.call(token: token))
end
```

Callers pattern-match on the result; no output side effect in the mixin.

## CLI pipeline

### `Output::Standard`

All CLI verbs use `Output::Standard` instead of raw `@stdout`/`@stderr`. It wraps both streams and exposes a semantic interface:

```ruby
module GemContribute
  module Output
    class Standard
      def initialize(out: $stdout, err: $stderr)
        @out = out
        @err = err
      end

      def info(message)     = @out.puts(message)
      def warn(message)     = @err.puts("warning: #{message}")
      def error(message)    = @err.puts(message)
      def progress(message) # tty-spinner in interactive terminals;
                            # falls back to info when stdout is not a TTY
    end

    class Null
      def info(_) = nil
      def warn(_) = nil
      def error(_) = nil
      def progress(_) = nil
    end
  end
end
```

`#progress` is the one method that behaves differently from a plain `puts`. Long operations (fork, clone) show a spinner in interactive terminals. `tty-spinner` detects non-TTY environments automatically and falls back to a plain line — no caller checks `$stdout.tty?`.

### Interactive prompts

`Init` is the one command that reads input. Its current `stdout.print` + injected `@gets` lambda is replaced by `tty-prompt`:

```ruby
prompt = TTY::Prompt.new(input: @input, output: @output)
chosen  = prompt.ask("Where should I clone repos?", default: DEFAULT_SUGGESTION)
proceed = prompt.yes?("Authenticate with GitHub now?")
```

`TTY::Prompt.new(input:, output:)` provides the same test injection story the current `gets:` lambda provides, with proper default-value display, Y/n handling, and non-TTY fallback built in.

### How CLI verbs change

CLI verbs print around service calls. The operation returns a `Result`; the verb interprets it:

```ruby
def execute(adapter, project, flags)
  @output.progress("Forking #{project.owner}/#{project.repo}...")

  case @fork_op.call(adapter: adapter, project: project)
  in Success(fork_result)
    @output.info(fork_result.reused ? "  Reusing existing fork." : "  Forked.")
    continue_with(fork_result, flags)
  in Failure(:unauthenticated)
    @output.error("Not authenticated. Run `gem-contribute auth login` first.")
    1
  in Failure(:adapter_error, message)
    @output.error(message)
    1
  end
end
```

The `with_workflow_rescues` wrapper in `Workflow` is retired — pattern matching on `Result` replaces it.

## TUI pipeline

The TUI never uses an `Output` object. A Rooibos Command wraps the service call, runs it off-thread, and returns a message to `Update`:

```ruby
def fix_command(adapter:, project:, issue:, viewer:)
  -> {
    result = Operations::FixPipeline.new.call(
      adapter: adapter, project: project, issue: issue, viewer: viewer
    )
    { type: :fix_completed, result: result }
  }
end
```

`Update` pattern-matches on the message:

```ruby
def update(msg, model)
  case msg
  in { type: :fix_completed, result: Success({ fork:, clone:, branch: }) }
    model.with(local_path: clone.path, branch_name: branch, status: :done)
  in { type: :fix_completed, result: Failure(:unauthenticated) }
    [model.with(pending_action: :fix), AuthOverlay.start_command]
  in { type: :fix_completed, result: Failure(:adapter_error, message) }
    model.with(error: message)
  end
end
```

The service object returns a `Result`; the Command wraps it in a typed message; `Update` renders it as model state. No output object, no stdout, no cross-layer exceptions.

## Plugin pipelines

Per [ADR-0014](adr/0014-ship-bundler-and-rubygems-plugins.md), v1 ships three entry points in a single `gem-contribute` gem: the standalone `gem-contribute` binary, a Bundler plugin (`bundle contribute`), and a RubyGems plugin (`gem contribute`). Both plugins are CLI-only; the TUI is a property of the standalone binary.

- **Bundler plugin** — `plugins.rb` at the gem root, per Bundler convention. Registers a `bundle contribute` command and delegates to the same dispatch table the standalone CLI uses.
- **RubyGems plugin** — `rubygems_plugin.rb`, per RubyGems convention. Registers a `Gem::Command` subclass for `gem contribute` and delegates the same way.

Both plugin entry points MUST NOT require Rooibos or `ratatui_ruby`. The TUI gets loaded only by the standalone-binary entry point, which keeps plugin install lightweight and plugin invocations fast.

When `dry-cli` is added (alongside the plugin shims), it replaces the hand-rolled `COMMANDS` dispatch in `cli.rb` with declarative command registration. All three entry points register the same underlying commands against their respective hosts — the commands themselves do not change.

The plugin work is deferred until the service layer and CLI pipeline are clean (this document's Phases 1 and 2) and the TUI lands ([ROADMAP](ROADMAP.md) Phase 3).

## New dependencies

| Gem | Role | Phase |
|---|---|---|
| `dry-monads` | `Success`/`Failure` Result types | 1 |
| `dry-operation` | Multi-step pipeline composition for `fix` | 1 |
| `dry-initializer` | Clean option declarations; removes rubocop suppressions | 1 |
| `tty-spinner` | Spinner in `Output::Standard#progress` | 2 |
| `tty-prompt` | Interactive prompts in `Init` | 2 |
| `dry-cli` | Command registration across all three entry points | 4/5 (with plugin shims) |

Pin all new dependencies to a minor version (`~> x.y`). Bump deliberately; record significant bumps in an ADR note.

## Migration sequence

### Phase 1 — Service layer

1. Add `dry-monads`, `dry-operation`, `dry-initializer` to the gemspec.
2. Remove `stdout:` from `Operations::Fork` and `Operations::Clone`. Add `reused:` to `Clone::Result`.
3. Convert both operations to return `Success(Result)` | `Failure(reason)`.
4. Convert `Workflow#build_adapter` to return `Success(adapter)` | `Failure(:unauthenticated)`.
5. Build `Operations::FixPipeline` using `dry-operation`.
6. Replace long initializers in `CLI::Fork` and `CLI::Fix` with `dry-initializer` option declarations.
7. Update all callers to pattern-match on `Result`. Retire `with_workflow_rescues`.

### Phase 2 — CLI pipeline

1. Introduce `Output::Standard` and `Output::Null`.
2. Replace raw `@stdout`/`@stderr` in all CLI verbs with `@output`.
3. Add `tty-spinner` for `Output::Standard#progress`.
4. Replace `Init`'s `stdout.print` + `@gets` with `tty-prompt`.

### Phases 4 and 5 — Bundler and RubyGems plugins

Per ADR-0014 and the [ROADMAP](ROADMAP.md), the gem-plugin work is split into two ROADMAP phases (one per plugin) and lives within the `gem-contribute` gem rather than as separate `bundler-contribute` / `rubygems-contribute` gems.

1. Add `dry-cli`. Replace the `COMMANDS` dispatch in `cli.rb` with `dry-cli` command registration so multiple entry points can hang off it.
2. Add `plugins.rb` at the gem root (Bundler plugin entry point). Register a `bundle contribute` command that dispatches into the same registration table.
3. Add `rubygems_plugin.rb` (RubyGems plugin entry point). Register a `Gem::Command` subclass that does the same.
4. Smoke-test both plugin install paths in CI.

Each ADR-0012 phase is independently releasable. Phase 1 has no user-visible behaviour change. Phase 2 changes the look of progress output and prompts. The plugin phases add new entry points.

## Testing strategy

**Service layer:** pure function in, `Result` out. Every operation gets unit tests that assert on `Success`/`Failure` values directly. No stdout assertion. No mock needed for output. VCR cassettes for adapter-touching operations; committed to the repo.

**CLI pipeline:** inject `Output::Null` for tests that don't assert on output; inject a capturing double for tests that do. Assert on captured calls to `#info`/`#error`/`#progress`, not on raw stdout strings.

**TUI pipeline:** the Command closure is a plain lambda — call it directly and assert on the returned message hash. `Update` is a pure function — call it with a message and assert on the returned model. Rooibos's snapshot test helpers (per ADR-0008/0013) supplement this for full-flow scenarios.

**gem plugin:** thin entry-point tests only. The CLI pipeline tests cover the behaviour.

## What doesn't change

- The `HostAdapter` interface and `GitHubAdapter` implementation.
- `Resolver`, `LockfileParser`, `TokenStore`, `Cache` — already output-free.
- The Auth flow shape. `CLI::Auth` keeps its existing structure; `Workflow#build_adapter`'s change is internal wiring.
- Caching strategy and TTLs.
- The Rooibos framework choice (ADR-0013, which superseded ADR-0010).
- ADR-0005 (render labels verbatim), ADR-0007 (show CONTRIBUTING), ADR-0009 (namespace). None of these touch the interface boundary.
