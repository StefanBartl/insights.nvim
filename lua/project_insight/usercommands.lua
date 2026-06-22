---@module 'project_insight.usercommands'
---@brief Unified :ProjectInsight command with tab-completion.
---
---   :ProjectInsight symbols [cwd|buffer] [telescope|fzf|scratch]
---   :ProjectInsight symbols rebuild
---   :ProjectInsight metrics
---   :ProjectInsight tree
---   :ProjectInsight count
---   :ProjectInsight clipboard
---   :ProjectInsight fileinfo
---   :ProjectInsight cache build|info|clear
local M = {}

local SUBCOMMANDS   = { "symbols", "metrics", "tree", "count", "clipboard", "fileinfo", "cache" }
local SYMBOL_SCOPES = { "cwd", "buffer" }
local SYMBOL_UIS    = { "telescope", "fzf", "scratch", "rebuild" }
local CACHE_SUBS    = { "build", "info", "clear" }

local notify = require("project_insight.util.notify").create("[project_insight]")

---Open symbol picker in the requested UI.
---@param entries table[]
---@param ui      string  "telescope"|"fzf"|"scratch"
---@param scope   string
local function open_symbol_picker(entries, ui, scope)
  local title = string.format("Symbols (%s) — %d found", scope, #entries)
  if ui == "fzf" then
    require("project_insight.ui.fzf").open(entries, title)
  elseif ui == "scratch" then
    local lines = {}
    for _, e in ipairs(entries) do
      lines[#lines + 1] = string.format("%s:%d  [%s] %s",
        e.filename or "?", e.lnum or 0, e.func_type or "?", e.name or "?")
    end
    require("project_insight.ui.scratch").open(lines, title)
  else
    require("project_insight.ui.telescope").open(entries, title)
  end
end

---Choose best available picker.
---@return string
local function default_ui()
  if pcall(require, "telescope") then return "telescope" end
  if pcall(require, "fzf-lua")   then return "fzf" end
  return "scratch"
end

local function handle_symbols(args)
  local scope = "cwd"
  local ui    = nil
  local rebuild = false

  for _, a in ipairs(args) do
    if a == "cwd" or a == "buffer" then
      scope = a
    elseif a == "telescope" or a == "fzf" or a == "scratch" then
      ui = a
    elseif a == "rebuild" then
      rebuild = true
    end
  end

  ui = ui or default_ui()

  local symbols = require("project_insight.symbols")
  notify.info("scanning symbols…")

  local entries, msg = symbols.get(scope, rebuild)
  if msg then notify.info(msg) end

  if #entries == 0 then
    notify.warn("no symbols found")
    return
  end

  open_symbol_picker(entries, ui, scope)
end

local function handle_metrics()
  require("project_insight.metrics").run()
end

local function handle_tree()
  require("project_insight.tree").write_tree(function(ok, msg)
    vim.notify(msg, ok and vim.log.levels.INFO or vim.log.levels.ERROR)
  end)
end

local function handle_count()
  require("project_insight.tree").count_files(function(ok, msg)
    vim.notify(msg, ok and vim.log.levels.INFO or vim.log.levels.ERROR)
  end)
end

local function handle_clipboard()
  require("project_insight.tree").copy_to_clipboard(function(ok, msg)
    vim.notify(msg, ok and vim.log.levels.INFO or vim.log.levels.ERROR)
  end)
end

local function handle_fileinfo()
  require("project_insight.fileinfo").show()
end

local function handle_cache(args)
  local sub = args[1] or ""
  local cfg = require("project_insight.config").get().symbols.cache
  local cache_mod = require("project_insight.scan.cache")

  if sub == "build" then
    notify.info("rebuilding symbol cache…")
    local entries, msg = require("project_insight.symbols").rebuild()
    notify.info(msg or (string.format("%d symbols cached", #entries)))

  elseif sub == "clear" then
    local ok, err = cache_mod.clear(cfg.dir, "symbols")
    if ok then notify.info("cache cleared")
    else      notify.warn("clear failed: " .. tostring(err)) end

  elseif sub == "info" then
    local st = cache_mod.stats(cfg.dir, "symbols")
    if st then
      print("=== Project-Insight Cache ===")
      print(string.format("  Symbols  : %d", st.entry_count))
      print(string.format("  Indexed  : %s", os.date("%Y-%m-%d %H:%M:%S", st.indexed_at or 0)))
      print(string.format("  CWD      : %s", st.cwd or "?"))
      print(string.format("  Size     : %d bytes", st.size_bytes or 0))
      print(string.format("  Path     : %s", st.path or "?"))
      print("=============================")
    else
      notify.info("no cache for current CWD — run :ProjectInsight cache build")
    end

  else
    notify.warn(":ProjectInsight cache: unknown subcommand '" .. sub .. "' — use build|info|clear")
  end
end

---Register :ProjectInsight command.
function M.setup()
  vim.api.nvim_create_user_command("ProjectInsight", function(o)
    local raw  = vim.split(o.args or "", "%s+", { trimempty = true })
    local sub  = table.remove(raw, 1) or ""

    if sub == "symbols"   then handle_symbols(raw)
    elseif sub == "metrics"   then handle_metrics()
    elseif sub == "tree"      then handle_tree()
    elseif sub == "count"     then handle_count()
    elseif sub == "clipboard" then handle_clipboard()
    elseif sub == "fileinfo"  then handle_fileinfo()
    elseif sub == "cache"     then handle_cache(raw)
    else
      vim.notify(
        "[project-insight] unknown subcommand '" .. sub .. "'\n"
        .. "Use: symbols | metrics | tree | count | clipboard | fileinfo | cache",
        vim.log.levels.ERROR)
    end
  end, {
    nargs = "*",
    desc  = "Project-Insight: project analysis (symbols, metrics, tree, fileinfo, cache)",
    complete = function(arglead, cmdline, _)
      local parts = vim.split(cmdline, "%s+", { trimempty = true })
      local n     = #parts
      local editing_last = cmdline:sub(-1) ~= " "
      local pos   = editing_last and n or n + 1

      if pos == 2 then
        local out = {}
        for _, s in ipairs(SUBCOMMANDS) do
          if s:sub(1, #arglead) == arglead then out[#out + 1] = s end
        end
        return out
      end

      local sub_typed = parts[2] or ""
      if pos == 3 then
        if sub_typed == "symbols" then
          local opts = {}
          for _, v in ipairs(SYMBOL_SCOPES) do opts[#opts + 1] = v end
          for _, v in ipairs(SYMBOL_UIS)    do opts[#opts + 1] = v end
          return opts
        end
        if sub_typed == "cache" then return CACHE_SUBS end
      end

      if pos == 4 and sub_typed == "symbols" then
        return SYMBOL_UIS
      end

      return {}
    end,
  })
end

return M
