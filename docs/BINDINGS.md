# Bindings Reference

All keymaps, user commands, and autocmds registered by insights.nvim.

---

## Keymaps

### Global (optional, config-driven)

Set the corresponding config key to `false` to disable. All entries carry a
`desc` so `which-key.nvim` picks them up automatically — no extra
integration needed.

| Key | Mode | Config key | Action |
|-----|------|-------------|--------|
| `<leader>fi` | n | `fileinfo.keymap` | Toggle `fs.stat` float for current buffer |
| `<leader>ps` | n | `keymaps.symbols_telescope` | Open symbol picker (telescope) |
| `<leader>pS` | n | `keymaps.symbols_fzf` | Open symbol picker (fzf-lua) |

The two `symbols_*` keys accept either a plain lhs string, or a table that
also picks what the mapping asks for:

```lua
keymaps = {
  symbols_telescope = { lhs = "<leader>ps", scope = "buffer", type = "tables" },
  symbols_fzf       = "<leader>pS",   -- string form: cwd, functions
}
```

`scope` is `cwd`|`buffer`, `type` is `functions`|`tables`|`strings`, and
`rebuild = true` forces a cache rebuild first. There is no `ui` field: the
UI is what distinguishes the two keys. An unknown scope or type is reported
and the default used, rather than passed down to a scanner that would answer
with a confusing "nothing found". The `desc` reflects the resolved choice, so
which-key shows `insights: symbols (telescope, buffer tables)`.

### Buffer-local — scratch report buffer

Registered on every `insights://…` scratch buffer (metrics, symbols,
imports reports, …). Configurable under `ui.close_keys` (list) and
`ui.follow_key` (set to `false` to disable following).

| Key | Config key | Action |
|-----|------------|--------|
| `q`, `<Esc>` | `ui.close_keys` | Close scratch buffer |
| `gf` | `ui.follow_key` | Follow `path:line` on the current line |
| `?` | — (always on) | Show a cheatsheet of the keys actually bound on this buffer (close/follow/any caller-supplied keymaps) |

### Buffer-local — imports report

Additional keymaps on the `:Insights imports` scratch report buffer only
(not the `telescope`/`fzf` picker view). Configurable under
`imports.definition.keymaps`; set a key to `false` to disable it.
Lua-only — on a non-Lua import these just notify that it isn't supported yet.

| Key | Config key | Action |
|-----|------------|--------|
| `gd` | `imports.definition.keymaps.jump` | Reveal the definition behind the Lua `require()` on this line (jump or float, per `imports.definition.view`) |
| `gp` | `imports.definition.keymaps.preview` | Always reveal the definition in a floating preview |

### Buffer-local — fileinfo float

Configurable under `ui.close_keys` (list), shared with the scratch buffer.

| Key | Config key | Action |
|-----|------------|--------|
| `q`, `<Esc>` | `ui.close_keys` | Close the file info float |

---

## User commands

A single dispatcher command with tab-completion at every level, built via
`lib.nvim.bindings.usercmd.composer`:

```vim
:Insights <subcommand> [args]
```

| Subcommand | Args | Description |
|---|---|---|
| `symbols` | `[cwd\|buffer] [functions\|tables\|strings] [telescope\|fzf\|scratch\|rebuild]` | Symbol index / picker |
| `metrics` | `[--flags...] [dir]` | Lua code metrics report |
| `smells` | `[--magic-numbers-only\|--constants-only] [dir]` | Magic numbers + unconfigured behaviour constants |
| `tree` | — | Write project file tree to configured output file |
| `count` | — | Count project files |
| `clipboard` | — | Copy tree file content to system clipboard |
| `fileinfo` | — | Toggle `fs.stat` float for current buffer |
| `cache` | `build\|info\|clear` | Manage the symbol index cache |
| `compress` | `[path] [outdir]` | Compress a project directory |
| `imports` | `[filter/lang...] [telescope\|fzf\|graph]` | Import/require analysis (Lua, Python, JS/TS, Go, Rust, C/C++); `graph` renders it as a Graphviz PNG via images.nvim |
| `imports reverse` | `<module>` | List every file that imports `<module>` |
| `imports unused` | `[filter/lang...]` | Bound import names never referenced again in their file |
| `conflicts` | — | Quickfix unresolved git conflicts |
| `unimported` | — | Check used-but-unimported components in current buffer |
| `devserver` | `[list\|kill]` | List or kill tracked dev servers (default: `list`) |

Set `commands = false` in `setup()` to register no user commands at all.

---

## Autocmds

Registered by `bindings/autocmds.lua`, each gated by its own `enable` key
(all off by default) — see [automatic-triggers.md](automatic-triggers.md)
for the full config knobs (`events` overrides, patterns, prompts).

| Event | Config gate | Action |
|---|---|---|
| `VimEnter` (default; `conflicts.events`) | `conflicts.enable` | Quickfix unresolved git conflicts |
| `BufWritePost` (default; `unimported.events`) | `unimported.enable` | Check used-but-unimported components in the written buffer |
| `TermOpen`, `TermRequest` | `devserver.enable` | Detect a dev server started in a terminal |
| `VimLeavePre` | `devserver.enable` | Kill tracked dev servers on exit |

One more, from elsewhere: `imports/index.lua` creates a `BufWritePost` autocmd
(augroup `InsightsImportIndex`) the first time a scan is remembered, and not
before. It has no config gate because it does nothing you would want to turn
off — it marks the remembered import index **stale**, so the
[hover contribution](hover.md) can say "a file was written since this was
scanned" instead of looking current, and `:Insights imports reverse` knows to
re-scan. Without a scan in this session it does not exist.
