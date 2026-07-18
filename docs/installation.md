# Installation

## Requirements

| Tool | Required | Purpose |
|------|----------|---------|
| Neovim | **≥ 0.9** | core |
| [`lib.nvim`](https://github.com/StefanBartl/lib.nvim) | **yes** | shared notify, cross-platform helpers, `ui.kit` dev-server prompt |
| `rg` (ripgrep) | **yes** | symbol indexing |
| `git` | optional | conflict scan (`conflicts`) |
| `telescope.nvim` | optional | telescope picker |
| `fzf-lua` | optional | fzf picker |
| `nvim-treesitter` | optional | TS-based Lua scanner + accurate import analysis |

## Installation

project-insight.nvim is lazy by design: `plugin/project_insight.lua` only sets
a load guard, and every command runs through the single `:ProjectInsight`
entry point. Load it on `cmd = "ProjectInsight"` — there is no benefit to
loading it eagerly.

> **If you use the automatic triggers**, load the plugin at startup
> (`lazy = false`) instead. The `conflicts`, `unimported`, and `devserver`
> autocmds are registered by `setup()`, so lazy-loading on `cmd` means they
> never fire — nothing would register until you ran `:ProjectInsight` by hand.
> Keep `cmd = "ProjectInsight"` only if all three are `enable = false`.
> See [Automatic triggers](automatic-triggers.md).

### lazy.nvim

```lua
{
  "StefanBartl/project-insight.nvim",
  dependencies = { "StefanBartl/lib.nvim" },
  cmd = "ProjectInsight",
  keys = {
    { "<leader>ps", desc = "Project symbols (telescope)" },
    { "<leader>pS", desc = "Project symbols (fzf)" },
  },
  config = function()
    require("project_insight").setup()
  end,
}
```

### packer.nvim

```lua
use {
  "StefanBartl/project-insight.nvim",
  requires = { "StefanBartl/lib.nvim" },
  cmd = "ProjectInsight",
  config = function()
    require("project_insight").setup()
  end,
}
```

### vim-plug

```vim
Plug 'StefanBartl/lib.nvim'
Plug 'StefanBartl/project-insight.nvim'
```

```lua
" after plug#end()
require("project_insight").setup()
```

vim-plug has no built-in lazy-loading by command; the `setup()` call itself
is cheap (no external process is spawned until a command runs).

## Health check

```vim
:checkhealth project_insight
```

Reports: Neovim version, `rg` availability, picker plugins, Tree-sitter,
configuration summary, and cache status.
