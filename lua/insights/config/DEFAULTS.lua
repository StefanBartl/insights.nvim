---@module 'insights.config.DEFAULTS'
--- Plugin-side default configuration for insights.nvim.
--- Overridden by user options passed to require("insights").setup().
--- See config/@types for the full InsightsConfig type.

require("insights.config.@types")

---@type InsightsConfig
local defaults = {
  symbols = {
    enable = true,
    default_scope = "cwd",
    languages = {
      lua = true,
      python = true,
      javascript = true,
      typescript = true,
      go = true,
      rust = true,
      c = true,
      cpp = true,
      java = true,
      ruby = true,
      php = true,
    },
    use_treesitter_for_lua = false,
    indexing = {
      exclude_patterns = {
        ".git/",
        "node_modules/",
        ".cache/",
        "build/",
        "dist/",
        "target/",
      },
      max_file_size_kb = 1024,
      follow_symlinks = false,
      -- How long one rg invocation may run before it is given up on. Only a
      -- guard against a wedged process -- raise it on a very large tree,
      -- lower it if you would rather hear about a stuck scan quickly.
      timeout_ms = 120000,
    },
    cache = {
      enabled = true,
      dir = vim.fn.stdpath("cache") .. "/insights/symbols",
      ttl_seconds = 3600,
    },
    -- Indicator while a cwd index is built (one rg pass per language pattern).
    -- Needs lib.nvim; silently a no-op without it.
    progress_style = "auto",
  },

  metrics = {
    enable = true,
    output_file = vim.fn.stdpath("state") .. "/insights/metrics.md",

    -- Analysis scope
    analyze_lua = true, -- analyze Lua source files
    analyze_misc = true, -- analyze Markdown / TXT / JSON files

    -- Lua output sections
    show_file_tables = true, -- detailed per-file table (L1-L5 / W1-W5)
    show_folder_tables = true, -- per-folder aggregate table
    show_total_summary = true, -- grand-total row
    show_ratios = true, -- folder ratio analysis
    show_deviations = true, -- deviations from the global averages
    show_top_lists = true, -- top-N files by lines/words
    show_misc_detailed = true, -- per-file listing for misc files (vs. summary only)

    -- Display
    percent_mode = "both", -- "both" | "percent" | "numbers"
    reverse_order = true, -- summary first (vs. files first)
    top_n = 50, -- items in top-N lists
    col_width = 7, -- data column width in tables
    exclude_type_files = true, -- exclude @types files from ratio analysis
  },

  tree = {
    enable = true,
    exclude_patterns = { "*/.git/*", "*/node_modules/*", "*/.cache/*" },
    outdir = vim.fn.stdpath("state") .. "/insights/tree",
    outfile_fmt = "%s-tree.txt",
  },

  fileinfo = {
    enable = true,
    keymap = "<leader>fi",
  },

  keymaps = {
    symbols_telescope = "<leader>ps",
    symbols_fzf = "<leader>pS",
  },

  -- Buffer-local keymaps on scratch reports and the fileinfo float.
  -- Set a list to {} to register no close/follow keymap at all.
  ui = {
    close_keys = { "q", "<Esc>" }, -- close scratch buffer / fileinfo float
    follow_key = "gf", -- follow path:line in a scratch buffer
  },

  compress = {
    enable = true,
    ---@type Insights.CompressEngine
    engine = "auto",
    outdir = "", -- "" = place compressed/ next to the source directory
  },

  imports = {
    enable = true,
    -- "auto"       use Tree-sitter when the Lua parser is available, else rg
    -- "treesitter" force AST scan (falls back to rg if parser missing)
    -- "ripgrep"    force the line/regex scan
    -- NOTE: engine only selects the Lua backend — the other languages below
    -- always use a regex/text scan (no Tree-sitter query implemented for them).
    engine = "auto",
    output_file = vim.fn.stdpath("state") .. "/insights/imports.md",
    -- Which languages :Insights imports scans; false = skip. A bare language
    -- id/alias (e.g. "python", "py", "js") used as a filter argument scopes
    -- the report to just that language for that run.
    languages = {
      lua = true,
      python = true,
      javascript = true,
      go = true,
      rust = true,
      c = true,
    },
    -- Named groups expand to a list of module prefixes when used as a filter,
    -- e.g. :Insights imports lib  →  matches lib, lib.nvim, lib.usrcmds.
    groups = {
      lib = { "lib", "lib.nvim", "lib.usrcmds" },
    },
    classify_external = true, -- tag modules without a local .lua file as (extern)

    -- "Go to definition" from the imports report: resolve a required module to
    -- its file and jump to / preview the definition of the accessed field.
    definition = {
      view = "edit", -- "edit" = jump in current window, "float" = preview window
      border = "rounded", -- float border (when view/preview opens a float)
      keymaps = {
        jump = "gd", -- reveal definition (uses `view`); false to disable
        preview = "gp", -- always reveal in a floating preview; false to disable
      },
    },

    -- :Insights imports graph — same scan/filters as the report, rendered as
    -- a Graphviz dependency graph (needs `dot` on PATH) and shown inline via
    -- images.nvim (soft dep; falls back to just reporting the PNG path).
    graph = {
      include_external = false, -- external modules add nodes/noise without adding structure
      outdir = vim.fn.stdpath("cache") .. "/insights/graph",
      layout = "dot",
    },
  },

  -- Populate the quickfix list with files holding unresolved merge conflicts.
  conflicts = {
    enable = true,
    events = { "VimEnter" }, -- when to scan; {} = only :Insights conflicts
    git_cmd = "git",
    diff_filter = "U", -- git --diff-filter; U = unmerged
    open_qf = true, -- :copen after populating the list
    notify = true, -- notify with the conflicting file names
  },

  -- Warn about component tags (<Foo …>) that are used but never imported.
  unimported = {
    enable = true,
    events = { "BufWritePost" },
    filetypes = { "astro", "javascriptreact", "typescriptreact", "vue", "svelte" },
    ignore = {}, -- component names to never report (e.g. globals)
  },

  -- Notice dev servers started in a Neovim terminal and offer to kill them on
  -- exit. Only terminals this Neovim owns are tracked — never every process on
  -- the machine matching a name.
  devserver = {
    enable = true,
    prompt = true, -- ask via lib.nvim ui.kit; false = apply kill_on_exit silently
    kill_on_exit = true, -- the answer used when prompt = false
    patterns = { -- plain substrings, matched case-insensitively
      "astro dev",
      "npm run dev",
      "pnpm dev",
      "yarn dev",
      "bun dev",
      "vite",
      "next dev",
      "nuxt dev",
      "ng serve",
      "rails server",
    },
  },

  commands = true,

  -- One-time "which CLI tools does this plugin want, and why" popup on
  -- first setup() after install (via lib.nvim.deps). false disables it for
  -- this plugin specifically, right here in the spec passed to setup() —
  -- no vim.g needed. See README.
  deps_popup = true,
}

return defaults
