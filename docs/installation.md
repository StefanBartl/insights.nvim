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

insights.nvim is lazy by design: `plugin/insights.lua` only sets
a load guard, and every command runs through the single `:Insights`
entry point. Load it on `cmd = "Insights"` — there is no benefit to
loading it eagerly.

> **If you use the automatic triggers**, load the plugin at startup
> (`lazy = false`) instead. The `conflicts`, `unimported`, and `devserver`
> autocmds are registered by `setup()`, so lazy-loading on `cmd` means they
> never fire — nothing would register until you ran `:Insights` by hand.
> Keep `cmd = "Insights"` only if all three are `enable = false`.
> See [Automatic triggers](automatic-triggers.md).

### lazy.nvim

```lua
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

### packer.nvim

```lua
use {
  "StefanBartl/insights.nvim",
  requires = { "StefanBartl/lib.nvim" },
  cmd = "Insights",
  config = function()
    require("insights").setup()
  end,
}
```

### vim-plug

```vim
Plug 'StefanBartl/lib.nvim'
Plug 'StefanBartl/insights.nvim'
```

```lua
" after plug#end()
require("insights").setup()
```

vim-plug has no built-in lazy-loading by command; the `setup()` call itself
is cheap (no external process is spawned until a command runs).

## Health check

```vim
:checkhealth insights
```

Reports: Neovim version, `rg` availability, picker plugins, Tree-sitter,
configuration summary, and cache status.
