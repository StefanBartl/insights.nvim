---@module 'project_insight.config'

---@alias ProjectInsight.CompressEngine
---| '"auto"'        # tar on Unix, Compress-Archive on Windows (default)
---| '"tar"'         # find + tar → .tar.gz  (Unix/macOS)
---| '"zip"'         # find + zip → .zip     (Unix/macOS, requires zip)
---| '"powershell"'  # PowerShell Compress-Archive → .zip  (Windows)

local M = {}

---@type ProjectInsightConfig
local defaults = {
  symbols = {
    enable          = true,
    default_scope   = "cwd",
    languages = {
      lua        = true,
      python     = true,
      javascript = true,
      typescript = true,
      go         = true,
      rust       = true,
      c          = true,
      cpp        = true,
      java       = true,
      ruby       = true,
      php        = true,
    },
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
      ttl_seconds = 3600,
    },
  },

  metrics = {
    enable              = true,
    output_file         = vim.fn.stdpath("state") .. "/project-insight/metrics.md",
    show_ratios         = true,
    show_deviations     = true,
    top_n               = 50,
    exclude_type_files  = true,
  },

  tree = {
    enable           = true,
    exclude_patterns = { "*/.git/*", "*/node_modules/*", "*/.cache/*" },
    outdir           = vim.fn.stdpath("state") .. "/project-insight/tree",
    outfile_fmt      = "%s-tree.txt",
  },

  fileinfo = {
    enable = true,
    keymap = "<leader>fi",
  },

  keymaps = {
    symbols_telescope = "<leader>ps",
    symbols_fzf       = "<leader>pS",
  },

  compress = {
    enable = true,
    ---@type ProjectInsight.CompressEngine
    engine = "auto",
    outdir = "",  -- "" = place compressed/ next to the source directory
  },

  imports = {
    enable      = true,
    -- "auto"       use Tree-sitter when the Lua parser is available, else rg
    -- "treesitter" force AST scan (falls back to rg if parser missing)
    -- "ripgrep"    force the line/regex scan
    engine      = "auto",
    output_file = vim.fn.stdpath("state") .. "/project-insight/imports.md",
    -- Named groups expand to a list of module prefixes when used as a filter,
    -- e.g. :ProjectInsight imports lib  →  matches lib, lib.nvim, lib.usrcmds.
    groups = {
      lib = { "lib", "lib.nvim", "lib.usrcmds" },
    },
    classify_external = true,  -- tag modules without a local .lua file as (extern)

    -- "Go to definition" from the imports report: resolve a required module to
    -- its file and jump to / preview the definition of the accessed field.
    definition = {
      view   = "edit",       -- "edit" = jump in current window, "float" = preview window
      border = "rounded",    -- float border (when view/preview opens a float)
      keymaps = {
        jump    = "gd",      -- reveal definition (uses `view`); false to disable
        preview = "gp",      -- always reveal in a floating preview; false to disable
      },
    },
  },

  commands = true,
}

---@type ProjectInsightConfig
local current = vim.deepcopy(defaults)

---@param opts ProjectInsightConfig|nil
function M.setup(opts)
  current = vim.tbl_deep_extend("force", defaults, opts or {})
end

---@return ProjectInsightConfig
function M.get()
  return current
end

return M
