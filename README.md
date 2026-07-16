# project-insight.nvim

```
  ___         _        _     ___          _      _   _
 | _ \_ _ ___(_)___ __| |_  |_ _|_ _  __(_)__ _| |_| |_
 |  _/ '_/ _ \ / -_) _|  _|  | || ' \(_-< / _` | ' \  _|
 |_| |_| \___/_\___\__|\__| |___|_||_/__/_\__, |_||_\__|
                                           |___/
```

> Pairs well with [buffer-ctx.nvim](https://github.com/StefanBartl/buffer-ctx.nvim) —
> insert or copy the current buffer's path, module name, or other context that
> complements the module-path resolution used by `:ProjectInsight imports`.

![version](https://img.shields.io/badge/version-0.1.0-blue.svg)
![status](https://img.shields.io/badge/status-beta-orange.svg)
![Neovim](https://img.shields.io/badge/Neovim-0.9%2B-success.svg)
![Lua](https://img.shields.io/badge/language-Lua-yellow.svg)
![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20Windows-lightgrey.svg)

A project-analysis plugin for Neovim. Combines ripgrep-based symbol indexing,
Tree-sitter Lua scanning, code metrics, file tree utilities, and buffer info
into a single unified command.

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
| **conflicts** | Populate the quickfix list with files holding unresolved merge conflicts |
| **unimported** | Warn on component tags (`<Foo />`) used but never imported — astro / jsx / tsx / vue / svelte |
| **devserver** | Notice dev servers started in a Neovim terminal and offer to kill them on exit |

Unlike the others, these last three can also run **automatically** — see
[Automatic triggers](#automatic-triggers).

---

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

---

## Installation

project-insight.nvim is lazy by design: `plugin/project_insight.lua` only sets
a load guard, and every command runs through the single `:ProjectInsight`
entry point. Load it on `cmd = "ProjectInsight"` — there is no benefit to
loading it eagerly.

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
:ProjectInsight metrics                        " full report for cwd
:ProjectInsight metrics /path/to/dir           " analyze a specific directory
:ProjectInsight metrics --ratios --deviations  " emphasize the ratio analysis
:ProjectInsight metrics --lua-only --no-top     " Lua only, skip top-N lists
:ProjectInsight metrics --misc-only --misc-detailed  " only docs (md/txt/json)
:ProjectInsight metrics --numbers-only /path   " raw counts, no percentages
:ProjectInsight metrics --current              " analyze the current buffer only
```

Without an argument the current working directory is analyzed. Pass a directory
to analyze it instead (tab-completion suggests directories and flags) — useful
when the editor's cwd differs from the project you want to measure. The report
is also written to `metrics.output_file` (default:
`{state}/project-insight/metrics.md`).

The report contains:

| Section | Content |
|---------|---------|
| **Total / Folder / File tables** | Lines (`L1` code, `L2` comments, `L3` no-annotations, `L4` annotations, `L5` blank) and words (`W1`–`W5`), each as count and/or percentage |
| **Folder ratios** | Comment %, annotation %, doc %, code %, avg lines/file, annotation-to-comment ratio — with deviations from the project's global averages |
| **Top-N lists** | Largest files by lines and by words; folders ranked by annotation ratio |
| **Ratio guidelines** | Heuristic healthy ranges for each ratio |
| **Documentation & config files** | Markdown / TXT / JSON file, line, and word counts (summary + optional per-file detail) |

Behavior is configurable both per-invocation (flags) and globally (`metrics.*`
in `setup()`): analysis scope (`analyze_lua`, `analyze_misc`), which sections
appear (`show_file_tables`, `show_folder_tables`, `show_total_summary`,
`show_ratios`, `show_deviations`, `show_top_lists`, `show_misc_detailed`),
display (`percent_mode` = `both`/`percent`/`numbers`, `reverse_order`, `top_n`,
`col_width`), and `exclude_type_files`.

Flags: `--ratios`/`--no-ratios`, `--deviations`, `--lua-only`, `--misc-only`,
`--no-misc`, `--misc-detailed`, `--no-top`, `--top-files-lines-only`,
`--top-files-words-only`, `--percent-only`, `--numbers-only`, `--reverse`,
`--topn=N`, `--colwidth=N`, `--file=PATH`, `--current`.

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

**Go to definition.** Inside the report, two extra keymaps resolve a required
module to the file that defines it — *without* executing `require(...)` — and
reveal the definition of the accessed field:

| Key  | Action |
|------|--------|
| `gd` | reveal the definition (jump in the current window, or a float — see `definition.view`) |
| `gp` | always reveal the definition in a floating preview |

On an **Occurrence** line (`module  name (.field)`) the jump lands on the
definition of that field — e.g. on `… project_insight.util.notify  notify (.create)`,
`gd` opens `notify.lua` at `function M.create(…)`. On a **Count** line it opens
the module file itself. Field location is Tree-sitter-accurate (it understands
`function M.f()`, `M.f = function`, `local f = …`, and table fields), with a
regex fallback when the Lua parser is unavailable. Module resolution searches
project-local `lua/` paths first, then the Neovim loader cache, `package.path`,
and the runtimepath. Configure the view, float border, and keys under
`imports.definition` (set a keymap to `false` to disable it).

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

The scan runs asynchronously so it never blocks the editor: the ripgrep backend
runs `rg` as a subprocess (`vim.system`), and the Tree-sitter backend parses
files in scheduled chunks. The report opens when the scan completes.

> Currently Lua-only. Support for other languages' imports is tracked in
> [docs/ROADMAP.md](docs/ROADMAP.md).

#### Conflicts

```vim
:ProjectInsight conflicts
```

Asks git for files in the unmerged state (`git diff --diff-filter=U`) and puts
them in the quickfix list, then `:copen`. Runs automatically on `VimEnter` —
see [Automatic triggers](#automatic-triggers).

#### Unimported

```vim
:ProjectInsight unimported
```

Reports component tags used in the current buffer with no matching import or
local definition. A tag starting with an uppercase letter (`<Card />`) is a
component reference; lowercase tags are HTML elements and ignored. A name
counts as bound if it is imported (`import Card …`, `import { Card } …`) or
declared locally (`const` / `let` / `var` / `function` / `class`).

This is a fast textual check, not a type-checker: it never reads other files,
so it cannot know whether the import actually resolves. Names you deliberately
leave unimported (globals, framework injections) go in `unimported.ignore`.

#### Devserver

```vim
:ProjectInsight devserver list   " tracked servers in this session
:ProjectInsight devserver kill   " kill them all now
```

See [Automatic triggers](#automatic-triggers) — this is mostly automatic.

---

## Automatic triggers

Most of the plugin only acts when you ask it to. These three also run on their
own, and each is switched off with its `enable` key:

| Feature | Fires on | Does |
|---------|----------|------|
| `conflicts` | `VimEnter` | Quickfix-lists unresolved merge conflicts. Silent when the repo is clean or not a git repo. |
| `unimported` | `BufWritePost` | Warns about used-but-unimported components, for `unimported.filetypes` only. Silent when nothing is missing. |
| `devserver` | `TermOpen`, `TermRequest`, `VimLeavePre` | Detects dev servers and kills the ones you approved on exit. |

### How the dev-server tracking works

When a terminal command matches one of `devserver.patterns` (`npm run dev`,
`astro dev`, `vite`, …), a prompt asks once whether that server should be
killed when Neovim exits. Answer yes and its process tree is killed on
`VimLeavePre`; answer no (or press `<Esc>`) and it is left alone. You are asked
once per terminal — the answer sticks for that terminal's lifetime.

**Only terminals this Neovim instance started are tracked.** The kill targets
that terminal's recorded PID — its process tree via `taskkill /T` on Windows,
its process group via `kill -TERM -<pid>` elsewhere. A server you started in
another shell or a tmux pane is never touched, because this plugin only kills
processes it can account for. That is the deliberate trade-off against a
`pkill -f "astro dev"`-style sweep, which would also kill servers that have
nothing to do with this editor session.

A command typed into an already-open shell is only detected if the program sets
the terminal title (most dev servers do, via OSC 0/2). Starting the server as
the terminal's command — `:terminal npm run dev` — always works.

To skip the prompt and always kill matching servers:

```lua
devserver = { prompt = false, kill_on_exit = true }
```

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

  -- Lua code metrics + documentation-file analysis
  metrics = {
    enable             = true,
    output_file        = vim.fn.stdpath("state") .. "/project-insight/metrics.md",

    analyze_lua        = true,   -- analyze Lua source files
    analyze_misc       = true,   -- analyze Markdown / TXT / JSON files

    show_file_tables   = true,   -- detailed per-file table (L1-L5 / W1-W5)
    show_folder_tables = true,   -- per-folder aggregate table
    show_total_summary = true,   -- grand-total row
    show_ratios        = true,   -- folder ratio analysis
    show_deviations    = true,   -- deviations from the global averages
    show_top_lists     = true,   -- top-N files by lines/words
    show_misc_detailed = true,   -- per-file listing for misc files

    percent_mode       = "both", -- "both" | "percent" | "numbers"
    reverse_order      = true,   -- summary first (vs. files first)
    top_n              = 50,     -- items in top-N lists
    col_width          = 7,      -- data column width in tables
    exclude_type_files = true,   -- exclude @types files from ratio analysis
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

  -- Buffer-local keymaps on scratch reports and the fileinfo float
  ui = {
    close_keys = { "q", "<Esc>" },  -- {} = register no close keymap
    follow_key = "gf",              -- follow path:line in a scratch buffer; false to disable
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

    -- "Go to definition" from the imports report (gd / gp)
    definition = {
      view   = "edit",        -- "edit" = jump in current window, "float" = preview
      border = "rounded",     -- float border
      keymaps = {
        jump    = "gd",       -- reveal definition (uses view); false to disable
        preview = "gp",       -- always reveal in a float; false to disable
      },
    },
  },

  -- Quickfix-list unresolved merge conflicts
  conflicts = {
    enable      = true,             -- false = no autocmd, no :ProjectInsight conflicts
    events      = { "VimEnter" },   -- {} = never automatic, command only
    git_cmd     = "git",
    diff_filter = "U",              -- git --diff-filter value; U = unmerged
    open_qf     = true,             -- :copen after populating the list
    notify      = true,             -- notify with the conflicting file names
  },

  -- Warn about component tags used but never imported
  unimported = {
    enable    = true,
    events    = { "BufWritePost" },
    filetypes = { "astro", "javascriptreact", "typescriptreact", "vue", "svelte" },
    ignore    = {},                 -- component names to never report
  },

  -- Kill dev servers started in a Neovim terminal on exit
  devserver = {
    enable       = true,            -- false = never watch terminals
    prompt       = true,            -- ask via lib.nvim ui.kit before killing
    kill_on_exit = true,            -- the answer used when prompt = false
    patterns     = {                -- plain substrings, case-insensitive
      "astro dev", "npm run dev", "pnpm dev", "yarn dev", "bun dev",
      "vite", "next dev", "nuxt dev", "ng serve", "rails server",
    },
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
  config/
    init.lua            merges user opts over DEFAULTS
    DEFAULTS.lua         plugin-side default configuration
  bindings/
    usrcmds.lua         :ProjectInsight dispatcher + tab-completion
    keymaps.lua         optional global keymaps (which-key discoverable)
    autocmds.lua        no-op — project-insight registers no autocmds
  util/
    notify.lua          re-exports lib.nvim's notify factory
    platform.lua        is_windows() (via lib.nvim), run_shell(), copy_to_clipboard()
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
    analyzer.lua        per-file line/word stats, ratios, percentages, formatting
    report.lua          ASCII tables (file/folder/total/ratios/top-N/guidelines)
    misc.lua            Markdown/TXT/JSON documentation-file analysis
    init.lua            scan, option resolution, report assembly, file output
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
    resolve.lua         module path → file resolution (no require side-effects)
    definition.lua      locate + jump/preview the definition behind an import
  health.lua            :checkhealth project_insight
plugin/project_insight.lua   guard + lazy-load trigger
```

---

## Health check

```vim
:checkhealth project_insight
```

Reports: Neovim version, `rg` availability, picker plugins, Tree-sitter,
configuration summary, and cache status.

---

