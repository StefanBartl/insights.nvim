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

A project-analysis plugin for Neovim. Combines ripgrep-based symbol indexing,
Tree-sitter Lua scanning, code metrics, file tree utilities, and buffer info
into a single unified command.

---

## Quickstart

Requires Neovim ≥ 0.9, [`lib.nvim`](https://github.com/StefanBartl/lib.nvim),
and `rg` (ripgrep). See [Installation](docs/installation.md) for full
requirements and other package managers.

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
  config = function()
    require("insights").setup()
  end,
}
```

```vim
:Insights symbols     " open the symbol picker for the current project
:Insights metrics     " Lua code metrics report
:Insights tree        " write the project file tree to a file
```

---

## Documentation

- [Features](docs/features.md) — overview of every module and what it does.
- [Installation](docs/installation.md) — requirements, package-manager setup, health check.
- [Commands](docs/commands.md) — full `:Insights` subcommand reference, flags, and symbol types.
- [Automatic triggers](docs/automatic-triggers.md) — the `conflicts`, `unimported`, and `devserver` autocmds, and how dev-server tracking works.
- [Configuration](docs/configuration.md) — full `setup()` reference with defaults.
- [Architecture](docs/architecture.md) — source tree layout and module responsibilities.
- [Bindings reference](docs/BINDINGS.md) — every keymap, user command, and autocmd registered by the plugin.
- [Roadmap](docs/ROADMAP.md) — planned and proposed work.
