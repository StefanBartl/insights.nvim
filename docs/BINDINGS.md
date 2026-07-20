# Bindings Reference

All keymaps, user commands, and autocmds registered by project-insight.nvim.

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

### Buffer-local — scratch report buffer

Registered on every `project-insight://…` scratch buffer (metrics, symbols,
imports reports, …). Configurable under `ui.close_keys` (list) and
`ui.follow_key` (set to `false` to disable following).

| Key | Config key | Action |
|-----|------------|--------|
| `q`, `<Esc>` | `ui.close_keys` | Close scratch buffer |
| `gf` | `ui.follow_key` | Follow `path:line` on the current line |

### Buffer-local — imports report

Additional keymaps on the `:ProjectInsight imports` report buffer only.
Configurable under `imports.definition.keymaps`; set a key to `false` to
disable it.

| Key | Config key | Action |
|-----|------------|--------|
| `gd` | `imports.definition.keymaps.jump` | Reveal the definition behind the `require()` on this line (jump or float, per `imports.definition.view`) |
| `gp` | `imports.definition.keymaps.preview` | Always reveal the definition in a floating preview |

### Buffer-local — fileinfo float

Configurable under `ui.close_keys` (list), shared with the scratch buffer.

| Key | Config key | Action |
|-----|------------|--------|
| `q`, `<Esc>` | `ui.close_keys` | Close the file info float |

---

## User commands

A single dispatcher command with tab-completion at every level, built via
`lib.nvim.usercmd.composer`:

```vim
:ProjectInsight <subcommand> [args]
```

| Subcommand | Args | Description |
|---|---|---|
| `symbols` | `[cwd\|buffer] [functions\|tables\|strings] [telescope\|fzf\|scratch\|rebuild]` | Symbol index / picker |
| `metrics` | `[--flags...] [dir]` | Lua code metrics report |
| `tree` | — | Write project file tree to configured output file |
| `count` | — | Count project files |
| `clipboard` | — | Copy tree file content to system clipboard |
| `fileinfo` | — | Toggle `fs.stat` float for current buffer |
| `cache` | `build\|info\|clear` | Manage the symbol index cache |
| `compress` | `[path] [outdir]` | Compress a project directory |
| `imports` | `[filter...]` | `require()` analysis report |
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
