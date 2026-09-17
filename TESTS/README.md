# TESTS/

Headless spec suite. Every spec drives a module directly — no picker, no
window, no project scan of anything but its own fixtures.

```
nvim --headless -u NONE -c "set rtp+=." -l TESTS/run.lua
```

Exit 0 is a pass; the runner prints one line per spec and exits non-zero on the
first failure. CI runs exactly this command.

## lib.nvim

Several modules require lib.nvim at module load, so the suite cannot run
without it. `run.lua` resolves it in this order:

1. `$LIB_NVIM_PATH`
2. a sibling checkout, `../lib.nvim`
3. the lazy.nvim-managed copy under `stdpath("data")/lazy/lib.nvim`

A sibling wins over the plugin-manager copy on purpose: that one is often older
than the working checkout, and testing against a stale lib.nvim gives
misleading failures.

**ui.nvim is deliberately not resolved.** It is a real dependency of two
modules (`ui/scratch.lua` requires `ui.kit` at load, `devserver` lazily for its
prompt), but CI checks out lib.nvim only. Both are covered against a stand-in
`ui.kit` placed in `package.loaded` before the module under test is required —
so the suite runs identically with and without ui.nvim installed.

## No subprocesses, no network

Nothing in this suite spawns `rg`, `git`, `dot`, `tar`, `zip`, PowerShell, or a
dev server. Each of those reaches the outside world through exactly one seam,
and the seam is replaced *before* the module under test is required:

| what would spawn | the seam that is replaced | where |
| --- | --- | --- |
| ripgrep, during an index build | `insights.scan.rg` | `symbols_index_spec` |
| ripgrep, during an imports scan | `vim.fn.executable`, forcing the glob path | `imports_report_spec` |
| ripgrep itself | `vim.system` | `scan_rg_spec` |
| git | `vim.system` + `lib.nvim.cross.executable` | `conflicts_spec` |
| tar / zip / PowerShell / find | `insights.util.platform` | `compress_tree_spec` |
| `taskkill` / `kill` | `vim.system` | `devserver_extra_spec` |
| Graphviz | only the "not installed" branch is driven | `imports_graph_spec` |
| pandoc, via pdfport.nvim | a stand-in `pdfport` module | `metrics_init_spec` |

The two exceptions are deliberate and harmless: `devserver_spec` and
`devserver_extra_spec` start a real `nvim --headless -c qa!` job, because
`track()` resolves a channel to an OS pid and a fabricated channel number
records nothing.

Tree-sitter is *not* stubbed. The Lua parser ships with Neovim, and the
scanners built on it are driven against it for real — see "Tree-sitter" below.

## The specs

### imports

| | |
| --- | --- |
| `import_util_spec.lua` | byte-offset to line-number mapping, and the depth-aware splitter the grouped-import forms need |
| `imports_langs_contract_spec.lua` | the shared `ImportLang` contract, checked once against all six scanners: declared metadata, degenerate input, line numbers, `is_external`, and that only Lua claims a Tree-sitter path |
| `imports_langs_detail_spec.lua` | where the six scanners actually differ — Python's parenthesised multi-line form, JavaScript's five passes, Go's go.mod lookup, Rust's brace expansion, C deciding `external` at scan time |
| `lua_imports_spec.lua` | which `require` calls the Lua regex scanner reports, internal vs external, and what a dynamic require currently does |
| `imports_ts_requires_spec.lua` | the AST scanner: bindings, trailing fields, multiple assignment, and that a `require` in a comment or a string is not an import |
| `imports_resolve_spec.lua` | module path → file, and that a project file wins over the runtimepath |
| `imports_definition_spec.lua` | "go to definition": the Tree-sitter and regex finders, and both reveal views |
| `imports_graph_spec.lua` | the Graphviz `digraph`: node/edge selection, de-duplication, deterministic order, DOT quoting, and the two "no layout engine" guards |
| `import_index_spec.lua` | the remembered import scan: cold answers nil, a warm index answers, staleness after a write, and the chunked `build_unused_report` re-read pass |
| `imports_report_spec.lua` | `insights.imports` end to end against a fixture tree: the scan, the filter language (languages, aliases, groups, prefix boundaries), all four reports, the writers, and `run`/`run_reverse`/`run_unused` |
| `hover_spec.lua` | the hover.nvim contribution: dotted-name detection, cold/warm/stale answers, and graceful decline without hover.nvim |

### symbols

| | |
| --- | --- |
| `symbols_patterns_parser_spec.lua` | pattern/extension selection, language detection, `func_type` inference, and the `--vimgrep` reader (including signature balancing and truncation) |
| `scan_rg_spec.lua` | the rg command builder, and `exec_sync`/`run` against a replaced `vim.system`: success, "no matches", a real failure, and the timeout |
| `scan_cache_spec.lua` | the on-disk JSON cache and every invalidation reason (version, cwd, TTL, source mtime) |
| `symbols_ts_lua_spec.lua` | the three Tree-sitter Lua scanners — functions, tables, strings — against real buffers |
| `symbols_index_spec.lua` | `rg_index.build`/`get`/`rebuild` against a fake ripgrep and an in-memory cache, plus `insights.symbols`' scope/type dispatch |
| `symbols_open_spec.lua` | the keymap-config normaliser, and which scanner and UI adapter each `open()` option reaches |

### metrics and smells

| | |
| --- | --- |
| `metrics_analyzer_spec.lua` | the per-file line/word counter (including the overlapping buckets), the file lister's ignore rules, and every ratio helper |
| `metrics_report_spec.lua` | every ASCII table builder, the ordering they promise, and the Markdown/TXT/JSON section |
| `metrics_init_spec.lua` | the folder aggregation, option resolution, both writers (including the pdfport contract), and which sections each flag produces |
| `smells_spec.lua` | magic-number and hardcoded-constant detection, and that `run()` tolerates an empty config surface |
| `smells_run_spec.lua` | the report `:Insights smells` opens, and the two `--…-only` flags |

### the remaining features

| | |
| --- | --- |
| `unimported_spec.lua` | which component tags count as referenced, what counts as a binding, and the frontier rule that keeps `ButtonGroup` from satisfying `Button` |
| `conflicts_spec.lua` | the blocking and non-blocking scans against a fake git, every failure mode, and the quickfix payload |
| `compress_tree_spec.lua` | all three compression engines and both tree backends (Unix and Windows), built and inspected rather than run |
| `devserver_spec.lua` | the pattern match that decides whether a terminal job is a dev server, and the tracking ledger |
| `devserver_extra_spec.lua` | `consider`/`ask`/`kill_all`/`chan_cmd`, and `kill_tree`'s fallback from the process group to the plain pid |
| `ui_fileinfo_spec.lua` | the scratch buffer (keymaps, the `?` cheatsheet, the follow key, the sidebar guard), the file-info float, and the platform helpers |

### config and wiring

| | |
| --- | --- |
| `config_spec.lua` | the merge, that `DEFAULTS` survives it unmutated, and the path expansion |
| `bindings_spec.lua` | the keymaps (registered for real), the autocmd groups, and `:Insights` — completion at every position plus a dispatch check per subcommand and per feature gate |
| `health_init_spec.lua` | `:checkhealth insights` against recorded `vim.health` calls, and `setup()` end to end including the "no hover.nvim, no lib.nvim.deps" path and the public façade |

Adding one: write `TESTS/<name>_spec.lua` returning `function(H) ... end`, then
list it in `run.lua`. `H` is the harness — `eq`, `ok`, `falsy`, `contains`,
`excludes`, `read` and `fixture`.

## Tree-sitter

`ts_requires`, `ts_lua`, `ts_lua_tables` and `ts_lua_strings` are driven
against the real grammar. That is deliberate, and so is the fact that several
assertions look like they are only checking a happy path: **a Tree-sitter
query naming a node the grammar no longer has does not fail loudly.**
`pcall(ts.query.parse, …)` returns false, the scanner answers `{}`, and the
report says there are no symbols — indistinguishable from a file that has
none. Every assertion expecting a non-empty result is therefore also a check
that the node names are still current. Verified against Neovim 0.12.2's
bundled tree-sitter-lua on 2026-09-17.

Each of those specs skips itself, with a printed note, if the Lua parser is
unavailable.

## Bugs pinned here, not fixed

Four real defects were found while writing this suite. Each is pinned with a
`BUG:`-marked assertion so the current behaviour cannot change silently;
fixing them is a separate, deliberate change.

1. **`symbols/parser.lua` discards every match on Windows.**
   `parse_vimgrep_line` splits on the first three colons, so a drive letter's
   own colon consumes the `filename` field. `rg_index.build` passes
   `vim.fn.getcwd()` as the search root, which on Windows is `E:\repos\…`, so
   every line ripgrep prints is counted as unparseable and `:Insights symbols`
   finds nothing at all. The failure is silent — the error list is counted,
   not shown. Pinned in `symbols_patterns_parser_spec.lua`.

2. **`symbols/ts_lua.lua`'s assignment branch is dead code.** It reads the
   target and value through `node:field("left")` / `node:field("right")`, but
   tree-sitter-lua exposes `variable_list` and `expression_list` as typed
   *children*, not as named fields. With
   `symbols.use_treesitter_for_lua = true`, a module written as
   `M.foo = function() … end` contributes no symbols at all. Pinned in
   `symbols_ts_lua_spec.lua`.

3. **`symbols/ts_lua_tables.lua` never prefixes a nested table field.** Same
   root cause, second call site: `par:field("variable_list")[1]` is always
   nil, so a field inside `local cfg = { inner = {} }` is listed as `inner`
   rather than `cfg.inner`. Pinned in `symbols_ts_lua_spec.lua`.
   Both `imports/ts_requires.lua` and `imports/definition.lua` already carry a
   `child_of_type` helper whose comment says exactly this.

4. **`tree/init.lua`'s Windows exclusions never match.** The glob-to-regex
   translation escapes metacharacters with Lua's `%` rather than the `\` the
   .NET regex engine understands, so the default `*/.git/*` becomes
   `.*[\/]%.git[\/].*` and matches no real path. On Windows, `:Insights tree`
   and `:Insights count` therefore include everything under `.git/`.
   `node_modules`, which contains no metacharacter, survives untouched and
   does work. The Unix branch passes the globs to `find -not -path` verbatim
   and is unaffected. Pinned in `compress_tree_spec.lua`.

Two further quirks are pinned as documented behaviour rather than as bugs:
`go.lua` reports every entry of a grouped `import ( … )` block one line early
(`imports_langs_detail_spec.lua`), and `ui/scratch.lua`'s follow key cannot
follow an absolute Windows path — the same colon blind spot as (1), though the
imports report's paths are relative, so it does not show there
(`ui_fileinfo_spec.lua`).

## What is deliberately not here

- **`ui/fzf.lua` and `ui/telescope.lua` beyond their "backend missing" guard.**
  Each is a single call into a picker that is not a dependency of this plugin
  and is not checked out in CI. The entry shape they are handed is pinned where
  it is built, in `symbols_open_spec.lua` and `imports_report_spec.lua`.
- **`config/@types/init.lua`.** `---@meta` annotations; no runtime code.
- **`plugin/insights.lua`.** A three-line `vim.g.loaded_insights` guard with no
  branch worth a fixture.
- **`ts_lua*.scan_cwd`.** Each walks every `.lua` file under the working
  directory and loads it into a buffer — a measurement of the machine, not of
  the scanner. The per-buffer scan they call in a loop is covered exhaustively
  instead, and the same file-walk-and-ignore logic is covered through
  `metrics.analyzer.list_files`.
- **`devserver.kill_tree` against a real process tree**, and the real Graphviz,
  pandoc, git, tar and ripgrep invocations. Every branch *around* them is
  covered; only the spawn itself is not.
