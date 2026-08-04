---@module 'insights.bindings.usrcmds'
---@brief Unified :Insights command, built via lib.nvim.usercmd.composer.
---
---   :Insights symbols [cwd|buffer] [telescope|fzf|scratch] [functions|tables|strings] [rebuild]
---   :Insights metrics [flags...] [dir]
---   :Insights tree
---   :Insights count
---   :Insights clipboard
---   :Insights fileinfo
---   :Insights cache build|info|clear
---   :Insights compress [path] [outdir]
---   :Insights imports [filter/lang...] [telescope|fzf]
---   :Insights imports reverse <module>
---   :Insights imports unused [filter/lang...]
---   :Insights conflicts
---   :Insights unimported
---   :Insights devserver [list|kill]
---
--- Every composer route only supplies typed-arg schema for tab-completion;
--- dispatch is always delegated to the handle_* functions below (unchanged),
--- so behavior — including symbols/metrics/imports' order-independent token
--- parsing — is unaffected by the migration. See composer.lua's Route.args
--- docs: a route with N declared optional slots of the same custom type
--- reproduces "same completion candidates at every position", which is what
--- these three subcommands need (unlike a fixed positional grammar).
local composer   = require("lib.nvim.usercmd.composer")
local expand_path = require("lib.nvim.cross.fs.expand_path")

local M = {}

local SYMBOL_SCOPES = { "cwd", "buffer" }
local SYMBOL_UIS    = { "telescope", "fzf", "scratch", "rebuild" }
local SYMBOL_TYPES  = { "functions", "tables", "strings" }

local notify = require("insights.util.notify").create("[insights]")

---@internal
---Open symbol picker in the requested UI.
---@param entries table[]
---@param ui      string  "telescope"|"fzf"|"scratch"
---@param scope   string
local function open_symbol_picker(entries, ui, scope)
  local title = string.format("Symbols (%s) — %d found", scope, #entries)
  if ui == "fzf" then
    require("insights.ui.fzf").open(entries, title)
  elseif ui == "scratch" then
    local lines = {}
    for _, e in ipairs(entries) do
      lines[#lines + 1] = string.format("%s:%d  [%s] %s",
        e.filename or "?", e.lnum or 0, e.func_type or "?", e.name or "?")
    end
    require("insights.ui.scratch").open(lines, title)
  else
    require("insights.ui.telescope").open(entries, title)
  end
end

local METRICS_BOOL_FLAGS = {
  "reverse", "no-reverse", "percent-only", "numbers-only",
  "ratios", "no-ratios", "deviations", "no-deviations",
  "lua-only", "misc-only", "no-misc", "misc-detailed",
  "no-top", "top-files-lines-only", "top-files-words-only", "current",
}
local METRICS_VALUE_FLAGS = { "topn", "colwidth", "file" }

---@internal
---FlagSpec list for the `metrics` route — declared purely so composer's own
---`--<Tab>` completion fires (composer intercepts any "--"-prefixed arg_lead
---unconditionally, ahead of a route's own `args` completers — a plain
---repeated-positional-arg route, like symbols/imports below, would silently
---never get a chance to complete these). Dispatch still goes through the
---unchanged parse_metrics_args below: reconstruct_metrics_tokens() re-derives
---the original "--flag"/"--flag=value" string tokens from ctx.flags/ctx.pos
---so that parser's semantics (e.g. --lua-only setting *two* opts fields)
---never has to be re-expressed here.
---@return table[]
local function metrics_flag_specs()
  local specs = {}
  for _, name in ipairs(METRICS_BOOL_FLAGS) do
    specs[#specs + 1] = { name = name, bool = true }
  end
  for _, name in ipairs(METRICS_VALUE_FLAGS) do
    specs[#specs + 1] = { name = name, type = "STRING" }
  end
  return specs
end

---@internal
---Re-derive the original flat token list from a metrics route's ctx, so
---parse_metrics_args (below, unchanged) can parse it exactly as before.
---@param ctx table
---@return string[]
local function reconstruct_metrics_tokens(ctx)
  local out = {}
  for _, name in ipairs(METRICS_BOOL_FLAGS) do
    if ctx.flags[name] then out[#out + 1] = "--" .. name end
  end
  for _, name in ipairs(METRICS_VALUE_FLAGS) do
    if ctx.flags[name] ~= nil then out[#out + 1] = ("--%s=%s"):format(name, ctx.flags[name]) end
  end
  for _, v in ipairs(ctx.pos) do out[#out + 1] = v end
  for _, v in ipairs(ctx.rest) do out[#out + 1] = v end
  return out
end

local IMPORT_LANG_IDS = { "lua", "python", "javascript", "go", "rust", "c" }
local IMPORT_UIS      = { "telescope", "fzf", "scratch" }

---@internal
---Completion candidates for `:Insights imports` (group names, language ids,
---and the picker-UI tokens — all order-independent, like SYMBOL_TOKENS).
---@param arglead string
---@return string[]
local function import_tokens(arglead)
  local cfg = require("insights.config").get()
  local out = {}
  for name, _ in pairs((cfg.imports and cfg.imports.groups) or {}) do
    out[#out + 1] = name
  end
  vim.list_extend(out, IMPORT_LANG_IDS)
  vim.list_extend(out, IMPORT_UIS)
  out = vim.tbl_filter(function(c) return c:sub(1, #arglead) == arglead end, out)
  table.sort(out)
  return out
end

---@internal
---Choose best available picker.
---@return string
local function default_ui()
  if pcall(require, "telescope") then return "telescope" end
  if pcall(require, "fzf-lua")   then return "fzf" end
  return "scratch"
end

---@internal
---Dispatch `:Insights symbols` — parses order-independent scope/ui/rebuild/type
---tokens, runs the matching symbol scan, and opens the resulting picker.
---@param args string[]
local function handle_symbols(args)
  local scope    = "cwd"
  local ui       = nil
  local rebuild  = false
  local sym_type = "functions"

  for _, a in ipairs(args) do
    if a == "cwd" or a == "buffer" then
      scope = a
    elseif a == "telescope" or a == "fzf" or a == "scratch" then
      ui = a
    elseif a == "rebuild" then
      rebuild = true
    elseif a == "tables" or a == "strings" or a == "functions" then
      sym_type = a
    end
  end

  ui = ui or default_ui()

  local symbols = require("insights.symbols")
  local entries, msg

  if sym_type == "tables" then
    notify.info("scanning Lua tables…")
    entries, msg = symbols.get_tables(scope)
  elseif sym_type == "strings" then
    notify.info("scanning Lua strings…")
    entries, msg = symbols.get_strings(scope)
  else
    notify.info("scanning symbols…")
    entries, msg = symbols.get(scope, rebuild)
  end

  if msg then notify.info(msg) end

  if not entries or #entries == 0 then
    notify.warn("nothing found")
    return
  end

  open_symbol_picker(entries, ui, scope .. " " .. sym_type)
end

---@internal
---Parse :Insights metrics flags + optional directory into an options table.
---@param args string[]
---@return table
local function parse_metrics_args(args)
  local opts = {}
  for _, a in ipairs(args) do
    if     a == "--reverse"               then opts.reverse_order = true
    elseif a == "--no-reverse"            then opts.reverse_order = false
    elseif a == "--percent-only"          then opts.percent_mode = "percent"
    elseif a == "--numbers-only"          then opts.percent_mode = "numbers"
    elseif a == "--ratios"                then opts.show_ratios = true
    elseif a == "--no-ratios"             then opts.show_ratios = false
    elseif a == "--deviations"            then opts.show_deviations = true
    elseif a == "--no-deviations"         then opts.show_deviations = false
    elseif a == "--lua-only"              then opts.analyze_lua = true;  opts.analyze_misc = false
    elseif a == "--misc-only"             then opts.analyze_lua = false; opts.analyze_misc = true
    elseif a == "--no-misc"               then opts.analyze_misc = false
    elseif a == "--misc-detailed"         then opts.show_misc_detailed = true
    elseif a == "--no-top"                then opts.show_top_lists = false
    elseif a == "--top-files-lines-only"  then opts.only_top_lines = true
    elseif a == "--top-files-words-only"  then opts.only_top_words = true
    elseif a == "--current"               then opts.single_file = vim.fn.expand("%:p")
    elseif a:match("^--topn=")            then opts.top_n = tonumber(a:sub(8))
    elseif a:match("^--colwidth=")        then opts.col_width = tonumber(a:sub(12))
    elseif a:match("^--file=")            then opts.single_file = expand_path(a:sub(8))
    elseif not a:match("^%-")             then opts.root = a
    end
  end
  return opts
end

---@internal
---@param args string[]  flags + optional directory (default: cwd)
local function handle_metrics(args)
  require("insights.metrics").run(parse_metrics_args(args))
end

---@internal
local function handle_tree()
  require("insights.tree").write_tree(function(ok, msg)
    if ok then notify.info(msg) else notify.error(msg) end
  end)
end

---@internal
local function handle_count()
  require("insights.tree").count_files(function(ok, msg)
    if ok then notify.info(msg) else notify.error(msg) end
  end)
end

---@internal
local function handle_clipboard()
  require("insights.tree").copy_to_clipboard(function(ok, msg)
    if ok then notify.info(msg) else notify.error(msg) end
  end)
end

---@internal
local function handle_fileinfo()
  require("insights.fileinfo").show()
end

---@internal
---@param args string[]  optional [path, outdir]
local function handle_compress(args)
  local cfg = require("insights.config").get()
  if not (cfg.compress and cfg.compress.enable) then
    notify.warn("compress feature is disabled (set compress.enable = true in setup)")
    return
  end

  -- arg 1: optional path (default = cwd); arg 2: optional outdir override
  local path = args[1]
    and vim.fn.fnamemodify(vim.fn.expand(args[1]), ":p")
    or  vim.fn.getcwd()

  local compress_cfg = args[2]
    and vim.tbl_extend("force", cfg.compress, { outdir = args[2] })
    or  cfg.compress

  notify.info(string.format("compressing %s …", vim.fn.fnamemodify(path, ":t")))
  require("insights.compress").compress(path, compress_cfg, function(ok, msg)
    if ok then notify.info(msg)
    else      notify.error(msg) end
  end)
end

---@internal
---Split repeated imports tokens into filters + an optional picker-UI choice.
---@param args string[]
---@return string[] filters, string|nil ui
local function split_import_args(args)
  local filters, ui = {}, nil
  for _, a in ipairs(args) do
    if a == "telescope" or a == "fzf" or a == "scratch" then
      ui = (a ~= "scratch") and a or nil
    else
      filters[#filters + 1] = a
    end
  end
  return filters, ui
end

---@internal
---@param args string[]  filters + optional picker UI
local function handle_imports(args)
  local cfg = require("insights.config").get()
  if not (cfg.imports and cfg.imports.enable) then
    notify.warn("imports feature is disabled (set imports.enable = true in setup)")
    return
  end
  local filters, ui = split_import_args(args)
  require("insights.imports").run(filters, ui)
end

---@internal
---@param args string[]  args[1] is the target module name
local function handle_imports_reverse(args)
  local cfg = require("insights.config").get()
  if not (cfg.imports and cfg.imports.enable) then
    notify.warn("imports feature is disabled (set imports.enable = true in setup)")
    return
  end
  require("insights.imports").run_reverse(args[1])
end

---@internal
---@param args string[]  filters, same shape as handle_imports
local function handle_imports_unused(args)
  local cfg = require("insights.config").get()
  if not (cfg.imports and cfg.imports.enable) then
    notify.warn("imports feature is disabled (set imports.enable = true in setup)")
    return
  end
  require("insights.imports").run_unused(args)
end

---@internal
local function handle_conflicts()
  local cfg = require("insights.config").get()
  if not (cfg.conflicts and cfg.conflicts.enable) then
    notify.warn("conflicts feature is disabled (set conflicts.enable = true in setup)")
    return
  end
  require("insights.conflicts").run()
end

---@internal
local function handle_unimported()
  local cfg = require("insights.config").get()
  if not (cfg.unimported and cfg.unimported.enable) then
    notify.warn("unimported feature is disabled (set unimported.enable = true in setup)")
    return
  end
  require("insights.unimported").run()
end

---@internal
---@param args string[]  args[1] is the subcommand, "list"|"kill" (default "list")
local function handle_devserver(args)
  local cfg = require("insights.config").get()
  if not (cfg.devserver and cfg.devserver.enable) then
    notify.warn("devserver feature is disabled (set devserver.enable = true in setup)")
    return
  end

  local devserver = require("insights.devserver")
  local sub = args[1] or "list"

  if sub == "list" then
    local lines = {}
    for _, info in pairs(devserver.tracked()) do
      lines[#lines + 1] = string.format("  pid %-8d %s  (kill on exit: %s)",
        info.pid, info.cmd, tostring(info.kill_on_exit))
    end
    if #lines == 0 then
      notify.info("no dev servers tracked in this session")
    else
      notify.info("tracked dev servers:\n" .. table.concat(lines, "\n"))
    end

  elseif sub == "kill" then
    local killed = devserver.kill_all(true)
    notify.info(string.format("killed %d dev server%s", killed, killed == 1 and "" or "s"))

  else
    notify.warn(":Insights devserver: unknown subcommand '" .. sub .. "' — use list|kill")
  end
end

---@internal
---@param args string[]  args[1] is the subcommand, "build"|"info"|"clear"
local function handle_cache(args)
  local sub = args[1] or ""
  local cfg = require("insights.config").get().symbols.cache
  local cache_mod = require("insights.scan.cache")

  if sub == "build" then
    notify.info("rebuilding symbol cache…")
    local entries, msg = require("insights.symbols").rebuild()
    notify.info(msg or (string.format("%d symbols cached", #entries)))

  elseif sub == "clear" then
    local ok, err = cache_mod.clear(cfg.dir, "symbols")
    if ok then notify.info("cache cleared")
    else      notify.warn("clear failed: " .. tostring(err)) end

  elseif sub == "info" then
    local st = cache_mod.stats(cfg.dir, "symbols")
    if st then
      notify.info(table.concat({
        "=== Insights Cache ===",
        string.format("  Symbols  : %d", st.entry_count),
        string.format("  Indexed  : %s", os.date("%Y-%m-%d %H:%M:%S", st.indexed_at or 0)),
        string.format("  CWD      : %s", st.cwd or "?"),
        string.format("  Size     : %d bytes", st.size_bytes or 0),
        string.format("  Path     : %s", st.path or "?"),
        "=============================",
      }, "\n"))
    else
      notify.info("no cache for current CWD — run :Insights cache build")
    end

  else
    notify.warn(":Insights cache: unknown subcommand '" .. sub .. "' — use build|info|clear")
  end
end

-- ── composer wiring ──────────────────────────────────────────────────────────

---@internal
---Prefix-filter, matching composer's own convention (its built-in types all
---filter this way — the old hand-rolled completers above did NOT filter
---symbols/cache/devserver candidates by arglead at all, an inconsistency
---fixed here, not carried forward).
---@param cands string[]
---@param lead string
---@return string[]
local function prefix(cands, lead)
  if lead == "" then return cands end
  local out = {}
  for _, c in ipairs(cands) do
    if c:sub(1, #lead) == lead then out[#out + 1] = c end
  end
  return out
end

-- symbols' 4 tokens (scope/type/ui/"rebuild") are order-independent — see the
-- loop in handle_symbols — so every position offers the same union set.
local SYMBOL_TOKENS = {}
vim.list_extend(SYMBOL_TOKENS, SYMBOL_SCOPES)
vim.list_extend(SYMBOL_TOKENS, SYMBOL_TYPES)
vim.list_extend(SYMBOL_TOKENS, SYMBOL_UIS)

composer.register_type("INSIGHTS_SYMBOLS_TOKEN", {
  validate = function(raw) return true, raw, nil end,
  complete = function(arg_lead) return prefix(SYMBOL_TOKENS, arg_lead) end,
})

composer.register_type("INSIGHTS_IMPORT_GROUP", {
  validate = function(raw) return true, raw, nil end,
  complete = function(arg_lead) return import_tokens(arg_lead) end,
})

-- compress's path/outdir are directories that need NOT already exist (outdir
-- especially — it's created on demand), so this stays soft like the original
-- (built-in DIR would hard-reject a not-yet-created outdir).
composer.register_type("INSIGHTS_DIR_SOFT", {
  validate = function(raw) return true, raw, nil end,
  complete = function(arg_lead) return vim.fn.getcompletion(arg_lead, "dir") end,
})

---@internal
---N optional positional slots of the same type — reproduces "same completion
---candidates at every position" for an order-independent/variadic grammar.
---@param type_name string
---@param count integer
---@return table[]
local function repeated_args(type_name, count)
  local out = {}
  for i = 1, count do
    out[i] = { name = "a" .. i, type = type_name, optional = true }
  end
  return out
end

---@internal
---Every bound positional plus whatever overflowed the declared slots, in order.
---@param ctx table
---@return string[]
local function merged_tokens(ctx)
  local out = {}
  for _, v in ipairs(ctx.pos) do out[#out + 1] = v end
  for _, v in ipairs(ctx.rest) do out[#out + 1] = v end
  return out
end

---@internal
---Build a composer route for a subcommand that takes no arguments.
---@param path string[]
---@param desc string
---@param fn fun()
---@return table
local function no_arg_route(path, desc, fn)
  return { path = path, desc = desc, run = function(_) fn() end }
end

---Register :Insights command.
function M.setup()
  local routes = {
    {
      path = { "symbols" },
      args = repeated_args("INSIGHTS_SYMBOLS_TOKEN", 4),
      desc = "Symbol index (scope/type/ui in any order)",
      run  = function(ctx) handle_symbols(merged_tokens(ctx)) end,
    },
    {
      path = { "metrics" },
      args = { { name = "root", type = "INSIGHTS_DIR_SOFT", optional = true } },
      flags = metrics_flag_specs(),
      desc = "Lua code metrics (flags + optional directory)",
      run  = function(ctx) handle_metrics(reconstruct_metrics_tokens(ctx)) end,
    },
    no_arg_route({ "tree" }, "Write project file tree", handle_tree),
    no_arg_route({ "count" }, "Count project files", handle_count),
    no_arg_route({ "clipboard" }, "Copy tree to clipboard", handle_clipboard),
    no_arg_route({ "fileinfo" }, "Toggle fs.stat float for current buffer", handle_fileinfo),
    no_arg_route({ "cache", "build" }, "Rebuild symbol cache", function() handle_cache({ "build" }) end),
    no_arg_route({ "cache", "info" }, "Show symbol cache stats", function() handle_cache({ "info" }) end),
    no_arg_route({ "cache", "clear" }, "Clear symbol cache", function() handle_cache({ "clear" }) end),
    {
      path = { "compress" },
      args = {
        { name = "path", type = "INSIGHTS_DIR_SOFT", optional = true },
        { name = "outdir", type = "INSIGHTS_DIR_SOFT", optional = true },
      },
      desc = "Archive a directory (default: cwd)",
      run  = function(ctx) handle_compress(ctx.pos) end,
    },
    {
      path = { "imports" },
      args = repeated_args("INSIGHTS_IMPORT_GROUP", 6),
      desc = "import/require usage report (filters + optional picker UI)",
      run  = function(ctx) handle_imports(merged_tokens(ctx)) end,
    },
    {
      path = { "imports", "reverse" },
      args = { { name = "module", type = "STRING" } },
      desc = "List every file that imports <module>",
      run  = function(ctx) handle_imports_reverse(merged_tokens(ctx)) end,
    },
    {
      path = { "imports", "unused" },
      args = repeated_args("INSIGHTS_IMPORT_GROUP", 6),
      desc = "Bound import names never referenced again in their file",
      run  = function(ctx) handle_imports_unused(merged_tokens(ctx)) end,
    },
    no_arg_route({ "conflicts" }, "Quickfix unresolved git conflicts", handle_conflicts),
    no_arg_route({ "unimported" }, "Check used-but-unimported components", handle_unimported),
    no_arg_route({ "devserver" }, "List tracked dev servers", function() handle_devserver({}) end),
    no_arg_route({ "devserver", "list" }, "List tracked dev servers", function() handle_devserver({ "list" }) end),
    no_arg_route({ "devserver", "kill" }, "Kill tracked dev servers", function() handle_devserver({ "kill" }) end),
  }

  composer.verb("Insights", {
    desc = "Insights: project analysis (symbols, metrics, tree, fileinfo, cache)",
    routes = routes,
  })
end

return M
