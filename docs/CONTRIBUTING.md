# Contributing to insights.nvim

Thank you for your interest! Bugs, ideas and questions are welcome in the
[issue tracker](https://github.com/StefanBartl/insights.nvim/issues); pull
requests very welcome.

## Getting the repository into a session

Clone it and either symlink the checkout into your plugin directory or add it to
the runtime path directly:

```lua
vim.opt.rtp:prepend("/path/to/insights.nvim")
require("insights").setup({})
```

`rg` has to be on `PATH` for anything to scan.

## Ground rules

- Lua only, idiomatic Neovim Lua. 2-space indentation.
- **This plugin reads source text and says so.** It cannot see a callback, a
  dynamic dispatch, or anything reached without a call site naming it. Where an
  analysis could be read as "this is dead", it has to report what it actually
  measured — "no call site found in the scanned tree", not "unused".
  [runtime-analysis.nvim](https://github.com/StefanBartl/runtime-analysis.nvim)
  is the counter-check, and the honesty is what makes the pair useful.
- **A cold index says nothing.** No analysis starts a scan behind the user's
  back, least of all from a hover. Silence is the correct answer to a question
  the cache cannot answer yet — the reasoning is [`hover.md`](hover.md), and it
  applies to any new passive contribution.
- **A module nobody imports is silence, not a zero.** A confident "0 importers"
  from an index that never saw the file is worse than no answer.
- External tools are optional except `rg`. Declare new ones in
  [`install.json`](install.json), report on them in `health.lua`, and let their
  absence cost one feature rather than the plugin.
- Scoping goes through `insights.metrics.analyzer.get_lua_files` — do not
  reimplement a file walk. Anything that regex-scans one project's source belongs
  here rather than in a sibling plugin.
- Commands are registered through `lib.nvim.bindings.usercmd.composer`.
- Descriptive commit messages.

## Project layout

| Path | Contains |
| --- | --- |
| `lua/insights/scan/` | The ripgrep layer every analysis is built on |
| `lua/insights/symbols/` | The symbol index, its cache, and the picker front ends |
| `lua/insights/imports/` | Multi-language import analysis: usage, reverse, unused, graph |
| `lua/insights/metrics/` | Lua code metrics, and the shared file walk |
| `lua/insights/smells/` | Magic numbers and unconfigured behaviour constants |
| `lua/insights/tree/`, `compress/`, `fileinfo/` | The project utilities |
| `lua/insights/conflicts/`, `unimported/`, `devserver/` | The automatic checks |
| `lua/insights/bindings/` | The `:Insights` route tree, keymaps and autocmds |
| `lua/insights/config/` | Defaults and `setup()` validation |
| `lua/insights/ui/`, `util/` | Rendering and shared helpers |
| `docs/` | Everything the README links to |
| `TESTS/` | The spec suite |

## Adding an analysis

1. Build it on `lua/insights/scan/` and the shared file walk, not on a new one.
2. Return findings as data; render separately. A report that writes straight to a
   buffer cannot be tested or reused by the hover contribution.
3. Say what it measured, not what it concluded. See the ground rules above.
4. If it needs an external tool, declare it in [`install.json`](install.json) and
   report on it in `health.lua`.
5. Route it in `lua/insights/bindings/` with completion.
6. Add a spec under `TESTS/` against a fixture tree.
7. Document it in [`commands.md`](commands.md), the matching page under
   [`FEATURES/`](FEATURES/README.md), and [`BINDINGS.md`](BINDINGS.md).

## Tests

`TESTS/` is a [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
busted-style suite over fixture trees.
[GitHub Actions](../.github/workflows/ci.yml) runs it on every push and PR to
`main`.

## Workflow

1. Fork the repository.
2. Branch as `feature/<name>`.
3. Make the change, add a spec, update the affected pages under `docs/`.
4. Open a PR with a clear description of what changed and why.
