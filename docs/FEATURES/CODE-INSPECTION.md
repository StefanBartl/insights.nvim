# Code analysis

## Symbol index

Ripgrep-based symbol search across 11 languages, plus Tree-sitter Lua
scanners for table constructors/dot-index paths and unique string
literals. Results open in a telescope/fzf-lua/scratch picker, `cwd`- or
buffer-scoped.

```vim
:Insights symbols                  " cwd scope, best available picker
:Insights symbols buffer functions " current buffer, functions (default kind)
:Insights symbols cwd tables       " Lua table definitions across cwd
:Insights symbols cwd strings      " Lua string literals across cwd
:Insights symbols rebuild          " force cache rebuild, then open picker
```

`tables`/`strings` require `nvim-treesitter` with the `lua` parser. In the
picker: `<Enter>` jumps to definition, `<C-p>` toggles preview (telescope),
`gf` follows `path:line` in the scratch view.

- **Module:** `symbols/open.lua` (the single dispatch both the command and
  the keymaps go through -- scope/type/UI resolution, the empty-result guard,
  and the token lists that drive completion *and* keymap-config validation),
  `symbols/init.lua`, `symbols/rg_index.lua`,
  `symbols/ts_lua.lua`, `symbols/ts_lua_tables.lua`,
  `symbols/ts_lua_strings.lua`, `symbols/parser.lua`, `symbols/patterns.lua`
- **Usercmds:** `:Insights symbols [cwd|buffer] [functions|tables|strings]
  [telescope|fzf|scratch|rebuild]`
- **Keymaps:** `<leader>ps` (telescope), `<leader>pS` (fzf-lua). Each accepts
  either a plain lhs string or `{ lhs, scope?, type?, rebuild? }`, so a
  mapping can ask for something other than the cwd/functions default. Added
  2026-08-24, closing the flag/option audit's entry: before this the two
  mappings hardcoded cwd + functions and scanned and opened a picker
  themselves, which is how they had come to be missing the empty-result guard
  and `rebuild` that the command path has. Both now dispatch through
  `symbols/open.lua`, so that cannot drift again. Side effect: the picker
  title from a keymap now names the type as well (`Symbols (cwd functions)`),
  matching what the command has always shown.
- **Config:** `opts.symbols.enable` (default `true`),
  `opts.symbols.languages.*` (11 languages, all default `true`),
  `opts.symbols.use_treesitter_for_lua` (default `false`),
  `opts.symbols.indexing.{exclude_patterns,max_file_size_kb,
  follow_symlinks}`

## Symbol cache

A CWD-keyed JSON cache for the symbol index, TTL-based and mtime-aware, so
repeated `:Insights symbols` calls in the same project don't re-run
ripgrep every time.

- **Module:** `scan/cache.lua`
- **Usercmds:** `:Insights cache build`, `:Insights cache info`,
  `:Insights cache clear`
- **Config:** `opts.symbols.cache.enabled` (default `true`),
  `opts.symbols.cache.dir` (default
  `stdpath("cache") .. "/insights/symbols"`),
  `opts.symbols.cache.ttl_seconds` (default `3600`)

## Code metrics

Lua file statistics — lines (code/comments/no-annotation/annotation/blank)
and words, per file and per folder, with folder-level ratio analysis
(comment %, annotation %, doc %, avg lines/file) and deviation-from-average
highlighting. Also covers Markdown/TXT/JSON documentation files.

```vim
:Insights metrics                        " full report for cwd
:Insights metrics --ratios --deviations  " emphasize ratio analysis
:Insights metrics --lua-only --no-top    " Lua only, skip top-N lists
:Insights metrics --current              " analyze current buffer only
```

Written to `metrics.output_file` (default `{state}/insights/metrics.md`);
ending it in `.pdf` routes through the optional
[pdfport.nvim](https://github.com/StefanBartl/pdfport.nvim) dependency
instead of plain text.

- **Module:** `metrics/analyzer.lua`, `metrics/report.lua`, `metrics/misc.lua`
- **Usercmds:** `:Insights metrics [--flags...] [dir]`
- **Config:** `opts.metrics.enable` (default `true`), plus per-section
  toggles (`show_file_tables`, `show_folder_tables`, `show_ratios`,
  `show_deviations`, `show_top_lists`, ...), `opts.metrics.percent_mode`
  (`"both"|"percent"|"numbers"`), `opts.metrics.top_n` (default `50`)

## Import/require analysis

Counts and lists import/require statements across Lua, Python, JS/TS, Go,
Rust, and C/C++ — Tree-sitter-accurate for Lua, regex/text scan for the
rest — with per-module counts, every occurrence (`path:line`, imported
name/field), prefix/group/language filters, a reverse ("who imports X")
view, an unused-import heuristic, and an optional Graphviz dependency
graph rendered inline via images.nvim.

```vim
:Insights imports                  " all languages
:Insights imports python           " language filter (aliases: py)
:Insights imports lib              " named group filter (opts.imports.groups)
:Insights imports reverse <module> " every file that imports <module>
:Insights imports unused           " bound import names never referenced again
:Insights imports graph            " Graphviz PNG via images.nvim (needs `dot`)
```

On the Lua-only scratch report, `gd` reveals the definition behind the
`require()` on the current line (jump or float, per
`imports.definition.view`), `gp` always previews it.

- **Tab:** true
- **Module:** `imports/init.lua`, `imports/resolve.lua`,
  `imports/definition.lua`, `imports/graph.lua`, `imports/ts_requires.lua`,
  `imports/langs/{lua,python,javascript,go,rust,c}.lua`
- **Usercmds:** `:Insights imports [filter/lang...] [telescope|fzf|graph]`,
  `:Insights imports reverse <module>`,
  `:Insights imports unused [filter/lang...]`
- **Keymaps:** `gd` (`imports.definition.keymaps.jump`), `gp`
  (`imports.definition.keymaps.preview`) — imports scratch buffer only
- **Config:** `opts.imports.enable` (default `true`), `opts.imports.engine`
  (`"auto"|"treesitter"|"ripgrep"`, Lua backend only),
  `opts.imports.languages.*`, `opts.imports.groups` (named prefix-list
  shortcuts), `opts.imports.classify_external` (default `true`),
  `opts.imports.graph.{include_external,outdir,layout}`
