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
| `ui_fzf_spec.lua` | the fzf-lua adapter's "backend missing" guard, the entries-to-lines shape it hands `fzf.fzf_exec`, and its default action's own `path:line` parsing |

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

## Bugs found here

Seven real defects have been found across this suite: four while it was first
written, three more in a later re-audit that went back over every skip
reason and checked the four recurring bug shapes this campaign keeps finding
elsewhere. **All seven are now fixed**; the assertions that pinned them
stayed on as regression guards.

1. **`symbols/parser.lua` discarded every match on Windows — fixed.**
   `parse_vimgrep_line` split on the first three colons, so a drive letter's
   own colon consumed the `filename` field. `rg_index.build` passes
   `vim.fn.getcwd()` as the search root, which on Windows is `E:\repos\…`, so
   every line ripgrep printed was counted as unparseable and `:Insights
   symbols` found nothing at all — silently, since the error list is counted,
   not shown. The scan for the first field separator now starts past a
   `^%a:[/\\]` drive prefix; relative and POSIX paths are untouched.
   `ui/scratch.lua`'s follow key had the same blind spot in its own
   `^([^:]+):(%d+)` pattern and was fixed with it, otherwise the jump out of a
   report with absolute paths stayed dead. Both are now regression assertions
   in `symbols_patterns_parser_spec.lua` and `ui_fileinfo_spec.lua`.

2. **`symbols/ts_lua.lua`'s assignment branch was dead code — fixed.** It read
   the target and value through `node:field("left")` / `node:field("right")`,
   but tree-sitter-lua exposes `variable_list` and `expression_list` as typed
   *children*, not as named fields, so both calls always returned an empty
   list. With `symbols.use_treesitter_for_lua = true`, a module written as
   `M.foo = function() … end` used to contribute no symbols at all. The module
   now carries its own `child_of_type` helper, the same one
   `imports/ts_requires.lua`/`imports/definition.lua` already used for the
   same reason. Pinned in `symbols_ts_lua_spec.lua`.

3. **`symbols/ts_lua_tables.lua` never prefixed a nested table field — fixed.**
   Same root cause, second call site: `par:field("variable_list")[1]` was
   always nil, so a field inside `local cfg = { inner = {} }` was listed as
   `inner` rather than `cfg.inner`. Pinned in `symbols_ts_lua_spec.lua`.

4. **`tree/init.lua`'s Windows exclusions never matched — fixed.** The
   glob-to-regex translation escaped metacharacters with Lua's `%` rather than
   the `\` the .NET regex engine understands, so the default `*/.git/*` became
   `.*[\/]%.git[\/].*` and matched no real path. On Windows, `:Insights tree`
   and `:Insights count` used to include everything under `.git/`.
   `node_modules`, which contains no metacharacter, survives untouched and
   does work. The Unix branch passes the globs to `find -not -path` verbatim
   and is unaffected. Pinned in `compress_tree_spec.lua`.

Found in a later re-audit, after the four above were already fixed:

5. **`health.lua`'s final line crashed the whole report — fixed.** `M.check()`
   closed with an unguarded
   `require("lib.nvim.bindings.usercmd.composer").checkhealth(...)`. Earlier in
   the same report, `check_lib()` already handles that exact dependency being
   missing with a friendly `err_s()` — but the closing call required it again
   with no `pcall`, so a genuinely missing composer crashed `:checkhealth
   insights` right after warning about it, instead of degrading the way every
   other guard in the file does. Now `pcall`-guarded like `check_lib_deps()`
   already was. Pinned in `health_init_spec.lua`.

6. **`ui/fzf.lua`'s default action had the same colon blind spot as (1),
   unfixed — fixed.** `sel[1]:match("^([^:]+):(%d+)")` stops at a Windows
   drive letter's own colon, same as `symbols/parser.lua` and (until it was
   fixed alongside (1)) `ui/scratch.lua`'s follow key. `e.filename` here comes
   straight from rg's own output via `symbols/rg_index.lua`, so it hits this
   exactly the same way — picking a result in the fzf-lua picker silently did
   nothing on Windows. This one was missed the first time because the whole
   `insights.ui.fzf` module is stubbed out everywhere it is *called*
   (`symbols_open_spec.lua`, `imports_report_spec.lua`); nothing exercised the
   module's own body. Fixed the same way as (1), and now covered by its own
   spec, `ui_fzf_spec.lua`.

7. **`symbols/ts_lua.lua`, `ts_lua_tables.lua` and `ts_lua_strings.lua`'s
   `scan_cwd` ignore list matched nothing on Windows — fixed.** All three carry
   an identical copy of a "skip `.git/`, `node_modules/`, `.cache/`, `build/`,
   `dist/`, `target/`" filter, matched with Lua patterns hardcoded to `/`
   against whatever `vim.fn.globpath` returns — native separators, so `\` on
   Windows. Unnormalized, none of those patterns ever matched, and a `cwd`
   Tree-sitter scan (`symbols.use_treesitter_for_lua = true`, or `get_tables`/
   `get_strings` with `scope = "cwd"`) walked straight into every one of them.
   This file used to claim the same logic was "covered through
   `metrics.analyzer.list_files`" — true of the *shape* of the fix, not of the
   code: that module normalizes to `/` before its own ignore check and always
   had; these three never did, so the claim had rotted into covering nothing.
   All three now match against a forward-slash copy instead of the raw path.
   Pinned in `symbols_ts_lua_spec.lua`, against a real (small) fixture tree.

One further quirk is pinned as documented behaviour rather than as a bug:
`go.lua` reports every entry of a grouped `import ( … )` block one line early
(`imports_langs_detail_spec.lua`).

## What is deliberately not here

- **`ui/telescope.lua` beyond its "backend missing" guard.** A single call
  into a picker that is not a dependency of this plugin and is not checked out
  in CI, whose action reads `sel.filename`/`sel.lnum` straight off telescope's
  own selection struct — no parsing of its own, so no branch here worth a
  fixture. The entry shape it is handed is pinned where it is built, in
  `symbols_open_spec.lua` and `imports_report_spec.lua`. (`ui/fzf.lua` looked
  the same at a glance, but its default action parses `path:line` back out of
  a display string by hand; that turned out to have its own bug, #6 above, and
  now has its own spec, `ui_fzf_spec.lua`.)
- **`config/@types/init.lua`.** `---@meta` annotations; no runtime code.
- **`plugin/insights.lua`.** A three-line `vim.g.loaded_insights` guard with no
  branch worth a fixture.
- **`ts_lua*.scan_cwd`'s file walk.** Each loads every `.lua` file under the
  working directory into a buffer — a measurement of the machine, not of the
  scanner. The per-buffer scan they call in a loop is covered exhaustively
  instead. Their ignore-list *filter* (a few lines of real branching logic,
  not a file walk) is a different matter and now has its own block in
  `symbols_ts_lua_spec.lua`, after #7 above showed it was not actually
  equivalent to `metrics.analyzer.list_files`'s own ignore check.
- **`devserver.kill_tree` against a real process tree**, and the real Graphviz,
  pandoc, git, tar and ripgrep invocations. Every branch *around* them is
  covered; only the spawn itself is not.
