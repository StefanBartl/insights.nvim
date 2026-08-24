# Configuration

Full reference with defaults:

```lua
require("insights").setup({

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
      dir         = vim.fn.stdpath("cache") .. "/insights/symbols",
      ttl_seconds = 3600,   -- 0 = never expire
    },

    -- Progress indicator while a cwd index is built (one rg pass per language
    -- pattern). Needs lib.nvim; silently a no-op without it.
    -- "auto" | "notify" | "statusline" | "fidget" | "float" | "kit"
    progress_style = "auto",
  },

  -- Lua code metrics + documentation-file analysis
  metrics = {
    enable             = true,
    output_file        = vim.fn.stdpath("state") .. "/insights/metrics.md",
    -- Ending output_file in .pdf instead writes a PDF via pdfport.nvim
    -- (https://github.com/StefanBartl/pdfport.nvim, optional dependency,
    -- pcall-guarded — needs pandoc + a PDF engine) instead of plain text.

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
    outdir           = vim.fn.stdpath("state") .. "/insights/tree",
    outfile_fmt      = "%s-tree.txt",   -- %s = project name (cwd tail)
  },

  -- Buffer file info float
  fileinfo = {
    enable = true,
    keymap = "<leader>fi",   -- false to disable
  },

  -- Optional keymaps (false to disable)
  keymaps = {
    -- Either a plain lhs string (cwd + functions, as before) ...
    symbols_fzf       = "<leader>pS",
    -- ... or a table that also picks scope/type/rebuild. No `ui` field:
    -- the UI is which key this is.
    symbols_telescope = {
      lhs     = "<leader>ps",
      scope   = "cwd",        -- "cwd" | "buffer"
      type    = "functions",  -- "functions" | "tables" | "strings"
      rebuild = false,        -- force a cache rebuild first ("functions" only)
    },
  },

  -- Buffer-local keymaps on scratch reports and the fileinfo float
  ui = {
    close_keys = { "q", "<Esc>" },  -- {} = register no close keymap
    follow_key = "gf",              -- follow path:line in a scratch buffer; false to disable
  },

  -- Project compression (:Insights compress)
  compress = {
    enable = true,
    ---@type Insights.CompressEngine  "auto"|"tar"|"zip"|"powershell"
    engine = "auto",   -- auto → tar on Unix, powershell on Windows
    outdir = "",       -- "" = compressed/ next to the source directory
                       -- non-empty = <outdir>/<name>-compressed/
  },

  -- import/require analysis (:Insights imports) — Lua, Python, JS/TS, Go,
  -- Rust, C/C++
  imports = {
    enable      = true,
    engine      = "auto",   -- "auto" → Tree-sitter if Lua parser present, else
                            -- ripgrep; "treesitter" / "ripgrep" force a backend
                            -- (Lua-only — other languages always regex-scan)
    output_file = vim.fn.stdpath("state") .. "/insights/imports.md",
    -- Which languages to scan; false = skip. A bare language id/alias used as
    -- a filter argument (e.g. :Insights imports python) scopes one run.
    languages = {
      lua = true, python = true, javascript = true,
      go = true, rust = true, c = true,
    },
    -- Named groups expand to module prefixes when used as a filter,
    -- e.g. :Insights imports lib → matches lib, lib.nvim, lib.usrcmds
    groups = {
      lib = { "lib", "lib.nvim", "lib.usrcmds" },
    },
    classify_external = true,  -- tag modules without a local source file as (extern)

    -- "Go to definition" from the imports report (gd / gp)
    definition = {
      view   = "edit",        -- "edit" = jump in current window, "float" = preview
      border = "rounded",     -- float border
      keymaps = {
        jump    = "gd",       -- reveal definition (uses view); false to disable
        preview = "gp",       -- always reveal in a float; false to disable
      },
    },

    -- :Insights imports graph — Graphviz dependency graph, shown via images.nvim
    graph = {
      include_external = false,  -- draw external modules as nodes too (default off — noisy)
      outdir = vim.fn.stdpath("cache") .. "/insights/graph",
      layout = "dot",            -- Graphviz layout engine on PATH: dot|neato|fdp|sfdp|twopi|circo
    },
  },

  -- Quickfix-list unresolved merge conflicts
  conflicts = {
    enable      = true,             -- false = no autocmd, no :Insights conflicts
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
