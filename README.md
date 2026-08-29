# insights.nvim

```
 _         _      _   _
(_)_ _  __(_)__ _| |_| |_ ___
| | ' \(_-< / _` | ' \  _(_-<
|_|_||_/__/_\__, |_||_\__/__/
            |___/
```

> Pairs well with [buffer-ctx.nvim](https://github.com/StefanBartl/buffer-ctx.nvim) —
> insert or copy the current buffer's path, module name, or other context that
> complements the module-path resolution used by `:Insights imports`.

![version](https://img.shields.io/badge/version-0.1.0-blue.svg)
![status](https://img.shields.io/badge/status-beta-orange.svg)
![Neovim](https://img.shields.io/badge/Neovim-0.9%2B-success.svg)
![Lua](https://img.shields.io/badge/language-Lua-yellow.svg)
![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20Windows-lightgrey.svg)

A project-analysis plugin for Neovim. Combines ripgrep/Tree-sitter symbol
indexing, multi-language import/require analysis (usage reports, reverse
lookup, unused-import detection, dependency graphs), Lua code metrics, file
tree utilities, directory compression, buffer file info, and automatic
checks for git conflicts, unused imports, and dev servers — into a single
unified command.

---

## Table of contents

- [Capabilities](#capabilities)
- [Quickstart](#quickstart)
- [Documentation](#documentation)

---

## Capabilities

| Capability | What it does | Details |
|---|---|---|
| `:Insights symbols` | ripgrep/Tree-sitter symbol index + picker (functions, Lua tables, string literals) | [Commands](docs/commands.md#symbol-index) |
| `:Insights metrics` | Lua code metrics report | [Commands](docs/commands.md#code-metrics) |
| `:Insights smells` | Magic numbers + unconfigured behaviour constants | [Commands](docs/commands.md#code-smells) |
| `:Insights imports` | Import/require usage report across Lua, Python, JS/TS, Go, Rust, C/C++ | [Commands](docs/commands.md#imports) |
| `:Insights imports reverse <module>` | List every file that imports a given module | [Commands](docs/commands.md#reverse-view) |
| `:Insights imports unused` | Bound import names never referenced again in their file | [Commands](docs/commands.md#unused-imports) |
| `:Insights imports graph` | Render the dependency graph as a PNG (via images.nvim) | [Commands](docs/commands.md#graph-view) |
| `:Insights tree` / `count` / `clipboard` | Write, count, or clipboard-copy the project file tree | [Commands](docs/commands.md#file-tree) |
| `:Insights fileinfo` | Toggle an `fs.stat` float for the current buffer | [Commands](docs/commands.md#buffer-file-info) |
| `:Insights cache build` / `info` / `clear` | Rebuild, inspect, or clear the symbol cache | [Commands](docs/commands.md#symbol-cache) |
| `:Insights compress [path] [outdir]` | Archive a directory (tar/zip/PowerShell, engine auto-detected) | [Commands](docs/commands.md#compress) |
| `:Insights conflicts` | Quickfix unresolved git conflicts (also runs automatically on `VimEnter`) | [Automatic triggers](docs/automatic-triggers.md) |
| `:Insights unimported` | Flag used-but-unimported components in the current buffer | [Commands](docs/commands.md#unimported) |
| `:Insights devserver list` / `kill` | List or kill dev servers started from Neovim | [Commands](docs/commands.md#devserver) |

---

## Quickstart

Requires Neovim ≥ 0.9, [`lib.nvim`](https://github.com/StefanBartl/lib.nvim),
and `rg` (ripgrep). See [Installation](docs/installation.md) for full
requirements and other package managers.

`rg` and, optionally, `dot` (graphviz, for the import-graph layout) are
declared in [`docs/install.json`](docs/install.json), parsed by lib.nvim's
[`deps` module](https://github.com/StefanBartl/lib.nvim/blob/main/lua/lib/nvim/deps/README.md)
— a popup explains what's missing the first time `setup()` runs after
installing insights.nvim, `:Lib deps show insights.nvim` repeats it any
time, and it's also folded into `:checkhealth insights`. Disable it
**right in this plugin's own spec**:
`require("insights").setup({ deps_popup = false })`.
`vim.g.lib_nvim_deps_disable_first_run = true` (every plugin) /
`vim.g.lib_nvim_deps_disabled_plugins = { "insights.nvim" }` also still
work, for turning it off without touching any plugin's config.

```lua
-- lazy.nvim
{
  "StefanBartl/insights.nvim",
  dependencies = { "StefanBartl/lib.nvim" },
  cmd = "Insights",
  keys = {
    { "<leader>ps", desc = "Project symbols (telescope)" },
    { "<leader>pS", desc = "Project symbols (fzf)" },
  },
  opts = {},
}
```

```vim
:Insights symbols     " open the symbol picker for the current project
:Insights metrics     " Lua code metrics report
:Insights imports     " import/require usage report (multi-language)
:Insights tree        " write the project file tree to a file
```

See [Capabilities](#capabilities) for the full command surface.

---

## Documentation

- [Features](docs/features.md) — overview of every module and what it does.
- [Installation](docs/installation.md) — requirements, package-manager setup, health check.
- [Commands](docs/commands.md) — full `:Insights` subcommand reference, flags, and symbol types.
- [Automatic triggers](docs/automatic-triggers.md) — the `conflicts`, `unimported`, and `devserver` autocmds, and how dev-server tracking works.
- [Configuration](docs/configuration.md) — full `setup()` reference with defaults.
- [Architecture](docs/architecture.md) — source tree layout and module responsibilities.
- [Bindings reference](docs/BINDINGS.md) — every keymap, user command, and autocmd registered by the plugin.
