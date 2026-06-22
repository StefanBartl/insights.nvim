---@module 'project_insight.config'
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
