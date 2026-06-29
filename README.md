# project-insight.nvim

```
  ___         _        _     ___          _      _   _
 | _ \_ _ ___(_)___ __| |_  |_ _|_ _  __(_)__ _| |_| |_
 |  _/ '_/ _ \ / -_) _|  _|  | || ' \(_-< / _` | ' \  _|
 |_| |_| \___/_\___\__|\__| |___|_||_/__/_\__, |_||_\__|
                                           |___/
```

![version](https://img.shields.io/badge/version-0.1.0-blue.svg)
![status](https://img.shields.io/badge/status-beta-orange.svg)
![Neovim](https://img.shields.io/badge/Neovim-0.9%2B-success.svg)
![Lua](https://img.shields.io/badge/language-Lua-yellow.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)
![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20Windows-lightgrey.svg)

A project-analysis plugin for Neovim. Combines ripgrep-based symbol indexing,
Tree-sitter Lua scanning, code metrics, file tree utilities, and buffer info
into a single unified command with zero external dependencies beyond Neovim itself.

---

## Features

| Module | What it does |
|--------|-------------|
| **symbols** | Ripgrep symbol index (11 languages) + Tree-sitter Lua scanner for functions, tables, and string literals; telescope / fzf-lua / scratch picker |
| **metrics** | Lua file statistics: lines, comments, annotations, word counts, ratios per file and folder |
| **tree** | Async project file tree (write to file / count / copy to clipboard) |
| **fileinfo** | Floating window with `fs.stat` metadata for the current buffer |
| **cache** | CWD-keyed JSON cache for the symbol index (TTL-based, mtime-aware) |
| **compress** | Compress a project directory — configurable engine: `tar` (.tar.gz), `zip`, or PowerShell (.zip) |
| **imports** | Count and list `require()` calls across Lua files — Tree-sitter-accurate (ignores `require` in comments/strings), per-module counts, every occurrence with imported name/field and `path:line`, with prefix/group filters |

---

## Requirements

| Tool | Required | Purpose |
|------|----------|---------|
| Neovim | **≥ 0.9** | core |
| `rg` (ripgrep) | **yes** | symbol indexing |
| `telescope.nvim` | optional | telescope picker |
| `fzf-lua` | optional | fzf picker |
| `nvim-treesitter` | optional | TS-based Lua scanner + accurate import analysis |

---

## Installation

### lazy.nvim

```lua
{
  "StefanBartl/project-insight.nvim",
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

### Local development

```lua
{
  dir = "E:/repos/project-insight.nvim",
  cmd = "ProjectInsight",
  config = function()
    require("project_insight").setup()
  end,
}
```

---

## Commands

### Unified command

```
:ProjectInsight <subcommand> [args]
```

Tab-completion works at every level.

#### Symbol index

```vim
:ProjectInsight symbols                       " cwd scope, best available picker
:ProjectInsight symbols cwd                   " explicit cwd scope
:ProjectInsight symbols buffer                " current buffer only
:ProjectInsight symbols telescope             " force telescope
:ProjectInsight symbols fzf                   " force fzf-lua
:ProjectInsight symbols scratch               " scratch buffer (no picker needed)
:ProjectInsight symbols cwd telescope         " scope + picker
:ProjectInsight symbols rebuild               " force cache rebuild, then open picker

" Lua-specific Tree-sitter scanners (tables and string literals)
:ProjectInsight symbols buffer tables         " Lua table definitions in current buffer
:ProjectInsight symbols cwd tables            " Lua table definitions across cwd
:ProjectInsight symbols buffer strings        " Lua string literals in current buffer
:ProjectInsight symbols cwd strings           " Lua string literals across cwd
:ProjectInsight symbols buffer functions      " Lua functions (explicit; same as default for Lua)
```

The `[type]` argument selects the symbol kind:

| Type | Scanner | What is found |
|------|---------|---------------|
| `functions` | rg + optional TS | function declarations and assignments (default) |
| `tables` | Tree-sitter | table constructor assignments, dot-index paths, table fields |
| `strings` | Tree-sitter | unique string literals (useful for auditing magic strings, require paths, event names) |

`tables` and `strings` require `nvim-treesitter` with the `lua` parser installed.
Arguments can appear in any order.

In the picker:

| Key | Action |
|-----|--------|
| `<Enter>` | Jump to definition |
| `<C-p>` | Toggle preview (telescope) |
| `q` / `<Esc>` | Close (scratch buffer) |
| `gf` | Follow path:line in scratch buffer |

#### Code metrics

```vim
:ProjectInsight metrics      " analyze Lua files in cwd, open scratch report
```

The report is also written to `metrics.output_file` (default:
`{state}/project-insight/metrics.md`).

#### File tree

```vim
:ProjectInsight tree         " write project tree to configured output file
:ProjectInsight count        " count project files
:ProjectInsight clipboard    " copy tree file content to system clipboard
```

#### Buffer file info

```vim
:ProjectInsight fileinfo     " toggle fs.stat float for current buffer
```

#### Symbol cache

```vim
:ProjectInsight cache build  " rebuild symbol cache for current cwd
:ProjectInsight cache info   " show cache statistics
:ProjectInsight cache clear  " delete cache for current cwd
```

#### Compress

```vim
:ProjectInsight compress                " compress cwd with configured engine
:ProjectInsight compress /path/to/dir   " compress a specific directory
:ProjectInsight compress . ~/backups    " compress cwd, write to ~/backups/
```

Creates a `compressed/` sub-directory inside the target path (default) or
inside `compress.outdir` if set, and places the archive + `file-list.txt`
there. `.git/` is excluded automatically.

| Engine | Produces | Platform |
|---|---|---|
| `tar` | `.tar.gz` | Unix/macOS |
| `zip` | `.zip` | Unix/macOS |
| `powershell` | `.zip` | Windows |
| `auto` (default) | tar on Unix, powershell on Windows | any |

#### Imports

```vim
:ProjectInsight imports                  " all require() calls in cwd
:ProjectInsight imports lib              " only group "lib" (config.imports.groups)
:ProjectInsight imports project_insight  " only modules under prefix project_insight
:ProjectInsight imports lib foo.bar      " multiple filters (OR-combined)
```

Scans every Lua file in the cwd for `require(...)` calls and opens a scratch
report (also written to `imports.output_file`). The report has two sections:

```
=== Imports — project-insight.nvim ===
total require() calls : 74   unique modules : 29   backend : treesitter

--- Count ---
   13  project_insight.util.notify
   10  project_insight.config
    1  telescope.actions               (extern)
   ...

--- Occurrences ---
lua/project_insight/metrics/init.lua:5   project_insight.util.notify   notify (.create)
lua/project_insight/metrics/init.lua:7   project_insight.config        config
...
```

- **Count**: each module with its occurrence count, sorted descending. Modules
  with no matching `.lua` file in the project are tagged `(extern)`
  (e.g. `vim`, `telescope.*`).
- **Occurrences**: every call as `path:line  module  imported-name (.field)`.
  `gf` in the scratch buffer jumps to the `path:line`.

Filters match by module prefix: `lib` matches `lib`, `lib.nvim`,
`lib.usrcmds` — but not `mylib`. Named groups in `imports.groups` expand to a
list of prefixes. Tab-completion suggests configured group names.

**Detection backend.** By default (`imports.engine = "auto"`) the scan uses
Tree-sitter: only genuine `require("…")` calls in the AST are counted, so the
word `require` inside comments or string literals is ignored. If the Lua
Tree-sitter parser is unavailable it falls back to a ripgrep line scan (which
matches the word `require` anywhere and is therefore less precise). The active
backend is shown in the report header. Set `engine = "treesitter"` or
`"ripgrep"` to force one.

> Currently Lua-only. Support for other languages' imports is tracked in
> [roadmap.md](roadmap.md).

---

## Configuration

Full reference with defaults:

```lua
require("project_insight").setup({

  -- Symbol index (ripgrep + optional Tree-sitter)
  symbols = {
    enable        = true,
    default_scope = "cwd",          -- "cwd" | "buffer"

    -- Languages to index with ripgrep
    languages = {
      lua = true, python = true, javascript = true, typescript = true,
      go = true, rust = true, c = true, cpp = true,
      java = true, ruby = true, php = true,
    },

    -- When true: use Tree-sitter for Lua (more precise names),
    -- ripgrep for all other languages.
    use_treesitter_for_lua = false,

    indexing = {
      exclude_patterns = {
        ".git/", "node_modules/", ".cache/",
        "build/", "dist/", "target/",
      },
      max_file_size_kb = 1024,
      follow_symlinks  = false,
    },

    cache = {
      enabled     = true,
      dir         = vim.fn.stdpath("cache") .. "/project-insight/symbols",
      ttl_seconds = 3600,   -- 0 = never expire
    },
  },

  -- Lua code metrics
  metrics = {
    enable             = true,
    output_file        = vim.fn.stdpath("state") .. "/project-insight/metrics.md",
    show_ratios        = true,
    show_deviations    = true,
    top_n              = 50,
    exclude_type_files = true,  -- exclude @types/ files from ratio analysis
  },

  -- File tree
  tree = {
    enable           = true,
    exclude_patterns = { "*/.git/*", "*/node_modules/*", "*/.cache/*" },
    outdir           = vim.fn.stdpath("state") .. "/project-insight/tree",
    outfile_fmt      = "%s-tree.txt",   -- %s = project name (cwd tail)
  },

  -- Buffer file info float
  fileinfo = {
    enable = true,
    keymap = "<leader>fi",   -- false to disable
  },

  -- Optional keymaps (false to disable)
  keymaps = {
    symbols_telescope = "<leader>ps",
    symbols_fzf       = "<leader>pS",
  },

  -- Project compression (:ProjectInsight compress)
  compress = {
    enable = true,
    ---@type ProjectInsight.CompressEngine  "auto"|"tar"|"zip"|"powershell"
    engine = "auto",   -- auto → tar on Unix, powershell on Windows
    outdir = "",       -- "" = compressed/ next to the source directory
                       -- non-empty = <outdir>/<name>-compressed/
  },

  -- require()/import analysis (:ProjectInsight imports)
  imports = {
    enable      = true,
    engine      = "auto",   -- "auto" → Tree-sitter if Lua parser present, else
                            -- ripgrep; "treesitter" / "ripgrep" force a backend
    output_file = vim.fn.stdpath("state") .. "/project-insight/imports.md",
    -- Named groups expand to module prefixes when used as a filter,
    -- e.g. :ProjectInsight imports lib → matches lib, lib.nvim, lib.usrcmds
    groups = {
      lib = { "lib", "lib.nvim", "lib.usrcmds" },
    },
    classify_external = true,  -- tag modules without a local .lua file as (extern)
  },

  -- false = register no user commands at all
  commands = true,
})
```

---

## Symbol types

The symbol index uses the following type labels:

| Label | Meaning |
|-------|---------|
| `local` | `local function foo()` |
| `global` | `function foo()` / top-level `def foo():` |
| `module` | `function M.foo()` / `M.foo = function()` |
| `method` | receiver method (Go, Python class method, …) |
| `anonymous` | `const foo = () =>` / `foo = function()` |
| `exported` | `export function foo()` |
| `unknown` | pattern matched but type not inferred |
| `table` | Lua table constructor (`:ProjectInsight symbols … tables`) |
| `string` | Lua string literal (`:ProjectInsight symbols … strings`) |

---

## Architecture

```
lua/project_insight/
  init.lua              setup() + public Lua façade
  config.lua            merged defaults
  util/
    notify.lua          vim.notify wrapper (no lib.* dependency)
    platform.lua        is_windows(), run_shell(), copy_to_clipboard()
  scan/
    rg.lua              ripgrep command builder + sync executor
    cache.lua           CWD-keyed JSON cache (mtime-aware TTL)
  symbols/
    patterns.lua        PCRE2 patterns + extension maps (11 languages)
    parser.lua          rg --vimgrep output → SymbolEntry
    rg_index.lua        rg-based indexer with cache integration
    ts_lua.lua          Tree-sitter Lua function scanner (AST traversal)
    ts_lua_tables.lua   Tree-sitter Lua table constructor scanner
    ts_lua_strings.lua  Tree-sitter Lua string literal scanner
    init.lua            unified entry: rg + optional TS merge; get_tables/get_strings
  metrics/
    analyzer.lua        per-file line/word/comment statistics
    init.lua            project scan, ASCII report, file output
  tree/init.lua         async file tree, count, clipboard
  fileinfo/init.lua     fs.stat floating window
  ui/
    telescope.lua       telescope entry_maker + picker
    fzf.lua             fzf-lua picker
    scratch.lua         read-only scratch buffer display
  compress/init.lua     async compression — engine dispatch (tar / zip / powershell)
  imports/
    init.lua            require() analysis — backend dispatch, counts, report
    ts_requires.lua     Tree-sitter require() scanner (AST-accurate)
  health.lua            :checkhealth project-insight
  usercommands.lua      :ProjectInsight dispatcher + tab-completion
plugin/project_insight.lua   guard + lazy-load trigger
```

---

## Health check

```vim
:checkhealth project-insight
```

Reports: Neovim version, `rg` availability, picker plugins, Tree-sitter,
configuration summary, and cache status.

---

## License

MIT
