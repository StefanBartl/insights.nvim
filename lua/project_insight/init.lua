---@module 'project_insight'
---@brief Project-Insight: unified project analysis (symbols, metrics, tree, fileinfo).
---
--- Combines:
---   - function_index  (ripgrep symbol indexer, multi-language)
---   - gather          (Tree-sitter Lua symbol scanner)
---   - lua_project_file_stats (Lua code metrics)
---   - project_tree    (file tree, count, clipboard)
---   - fileinfo        (buffer fs-stat float)
local M = {}

---@param opts ProjectInsightConfig|nil
function M.setup(opts)
  require("project_insight.config").setup(opts or {})

  local cfg = require("project_insight.config").get()

  if cfg.commands ~= false then
    require("project_insight.usercommands").setup()
  end

  -- Optional fileinfo keymap
  local fi = cfg.fileinfo or {}
  if fi.enable ~= false and fi.keymap and fi.keymap ~= "" and fi.keymap ~= false then
    vim.keymap.set("n", fi.keymap, function()
      require("project_insight.fileinfo").show()
    end, { desc = "project-insight: file info float" })
  end

  -- Optional symbol picker keymaps
  local km = cfg.keymaps or {}
  if km.symbols_telescope and km.symbols_telescope ~= false then
    vim.keymap.set("n", km.symbols_telescope, function()
      local symbols = require("project_insight.symbols")
      local entries, msg = symbols.get()
      if msg then vim.notify(msg, vim.log.levels.INFO) end
      require("project_insight.ui.telescope").open(entries,
        string.format("Symbols (cwd) — %d", #entries))
    end, { desc = "project-insight: symbols (telescope)" })
  end

  if km.symbols_fzf and km.symbols_fzf ~= false then
    vim.keymap.set("n", km.symbols_fzf, function()
      local symbols = require("project_insight.symbols")
      local entries, msg = symbols.get()
      if msg then vim.notify(msg, vim.log.levels.INFO) end
      require("project_insight.ui.fzf").open(entries,
        string.format("Symbols (cwd) — %d", #entries))
    end, { desc = "project-insight: symbols (fzf)" })
  end
end

-- Public façade for direct Lua use -----------------------------------------------

---@param scope "cwd"|"buffer"|nil
---@param force_rebuild boolean|nil
---@return table[], string|nil
function M.get_symbols(scope, force_rebuild)
  return require("project_insight.symbols").get(scope, force_rebuild)
end

---Run Lua file metrics for current project.
function M.run_metrics()
  require("project_insight.metrics").run()
end

---Analyze require() usage for the current project and open the report.
---@param filters string[]|nil  module prefixes / group names to filter by
function M.run_imports(filters)
  require("project_insight.imports").run(filters)
end

---Write the project file tree.
---@param callback fun(success:boolean, msg:string, path:string|nil)|nil
function M.write_tree(callback)
  require("project_insight.tree").write_tree(callback or function(ok, msg)
    vim.notify(msg, ok and vim.log.levels.INFO or vim.log.levels.ERROR)
  end)
end

---Show file info float for current buffer.
function M.show_fileinfo()
  require("project_insight.fileinfo").show()
end

return M
