---@module 'insights'
---@brief Insights: unified project analysis (symbols, metrics, tree, fileinfo).
---
--- Combines:
---   - function_index  (ripgrep symbol indexer, multi-language)
---   - gather          (Tree-sitter Lua symbol scanner)
---   - lua_project_file_stats (Lua code metrics)
---   - project_tree    (file tree, count, clipboard)
---   - fileinfo        (buffer fs-stat float)
local M = {}

local notify = require("insights.util.notify").create("[insights]")

---@param opts InsightsConfig|nil
function M.setup(opts)
  require("insights.config").setup(opts or {})

  local cfg = require("insights.config").get()

  if cfg.commands ~= false then
    require("insights.bindings.usrcmds").setup()
  end

  require("insights.bindings.keymaps").setup(cfg)
  require("insights.bindings.autocmds").setup(cfg)
end

-- Public façade for direct Lua use -----------------------------------------------

---@param scope "cwd"|"buffer"|nil
---@param force_rebuild boolean|nil
---@return table[], string|nil
function M.get_symbols(scope, force_rebuild)
  return require("insights.symbols").get(scope, force_rebuild)
end

---Run Lua file metrics for current project.
function M.run_metrics()
  require("insights.metrics").run()
end

---Analyze import/require usage for the current project and open the report.
---@param filters string[]|nil  module prefixes / language ids / group names to filter by
---@param ui string|nil  "telescope"|"fzf"|nil (nil = scratch buffer)
function M.run_imports(filters, ui)
  require("insights.imports").run(filters, ui)
end

---List every file that imports `module` — the reverse of run_imports().
---@param module string
function M.run_imports_reverse(module)
  require("insights.imports").run_reverse(module)
end

---List bound import names never referenced again in their file (heuristic).
---@param filters string[]|nil  module prefixes / language ids / group names to filter by
function M.run_imports_unused(filters)
  require("insights.imports").run_unused(filters)
end

---Write the project file tree.
---@param callback fun(success:boolean, msg:string, path:string|nil)|nil
function M.write_tree(callback)
  require("insights.tree").write_tree(callback or function(ok, msg)
    if ok then notify.info(msg) else notify.error(msg) end
  end)
end

---Show file info float for current buffer.
function M.show_fileinfo()
  require("insights.fileinfo").show()
end

---Scan for unresolved merge conflicts and populate the quickfix list.
---@return integer count
function M.run_conflicts()
  return require("insights.conflicts").run()
end

---Component tags used in a buffer without a matching import or definition.
---@param bufnr integer|nil  defaults to the current buffer
---@return string[] missing
function M.check_unimported(bufnr)
  return require("insights.unimported").run(bufnr)
end

---Dev servers tracked in this session, keyed by terminal channel.
---@return table<integer, { pid: integer, cmd: string, kill_on_exit: boolean }>
function M.devservers()
  return require("insights.devserver").tracked()
end

return M
