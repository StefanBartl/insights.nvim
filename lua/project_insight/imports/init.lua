---@module 'project_insight.imports'
---@brief require() / import analysis for Lua projects.
---
--- Scans all Lua files in the cwd for `require(...)` calls, counts how often
--- each module is imported, and lists every occurrence with the imported
--- name / accessed field and a path:line reference.
---
---   :ProjectInsight imports                  -- all modules
---   :ProjectInsight imports lib              -- group "lib" (config.imports.groups)
---   :ProjectInsight imports project_insight  -- prefix filter
---   :ProjectInsight imports lib foo.bar      -- multiple filters (OR)
local M = {}

local notify = require("project_insight.util.notify").create("[project_insight.imports]")
local config = require("project_insight.config")
local rg     = require("project_insight.scan.rg")

---@class ImportEntry
---@field module   string   the required module path, e.g. "project_insight.config"
---@field name     string|nil   local variable the require is assigned to
---@field field    string|nil   field accessed on the result, e.g. "create" in require("x").create
---@field filename string   path relative to cwd
---@field lnum     integer  1-based line number
---@field external boolean   true if no matching .lua file exists in the project

---@class ImportData
---@field entries   ImportEntry[]
---@field counts    table<string, integer>   module -> occurrence count
---@field externals table<string, boolean>   module -> is external
---@field method    string   "treesitter" | "ripgrep" — backend used to collect

---@alias RawImport { module: string, name: string|nil, field: string|nil, filename: string, lnum: integer }

--- A valid module path: identifier chars plus dot/dash/slash separators.
--- Filters out punctuation garbage matched from comments / string-building code.
---@param mod string
---@return boolean
local function is_module_path(mod)
  return mod:match("^[%w_][%w_%.%-/]*$") ~= nil
end

--- Parse a single source line for every require occurrence.
--- Returns a list because a line may contain more than one call.
---@param line string
---@return { module: string, field: string|nil }[]
local function parse_requires(line)
  local out = {}
  -- Matches the call with or without parentheses/quotes, plus an optional
  -- trailing field access. Capture 1 = module path, capture 2 = field.
  for mod in line:gmatch("require%s*%(?%s*[\"']([^\"']+)[\"']") do
    if is_module_path(mod) then
      out[#out + 1] = { module = mod }
    end
  end
  -- Resolve a trailing field for each require independently by re-scanning with
  -- a pattern that also captures the field; align by order of appearance.
  local i = 0
  for mod, field in line:gmatch("require%s*%(?%s*[\"']([^\"']+)[\"']%)?%s*%.([%w_]+)") do
    i = i + 1
    -- find the matching entry by module value (first without field set)
    for _, e in ipairs(out) do
      if e.module == mod and not e.field then
        e.field = field
        break
      end
    end
  end
  return out
end

--- Extract the local variable name a require is assigned to, if any.
---@param line string
---@return string|nil
local function parse_lhs_name(line)
  return line:match("^%s*local%s+([%w_]+)%s*=%s*require")
    or line:match("^%s*([%w_][%w_%.]*)%s*=%s*require")
end

--- Resolve whether a module path corresponds to a .lua file inside cwd.
---@param module string
---@param cwd string
---@return boolean external
local function is_external(module, cwd)
  local rel = module:gsub("%.", "/")
  local candidates = {
    cwd .. "/lua/" .. rel .. ".lua",
    cwd .. "/lua/" .. rel .. "/init.lua",
    cwd .. "/" .. rel .. ".lua",
    cwd .. "/" .. rel .. "/init.lua",
  }
  for _, p in ipairs(candidates) do
    if vim.fn.filereadable(p) == 1 then return false end
  end
  return true
end

--- Collect raw requires via the line/regex backend (ripgrep).
--- Fast and dependency-light, but matches the word "require" in comments and
--- string literals too (mitigated by `is_module_path`).
---@param cwd string
---@return RawImport[]
local function collect_via_rg(cwd)
  local cfg = config.get()
  local cmd = rg.build_cmd("require", { "lua" }, {
    cwd              = cwd,
    exclude_patterns = (cfg.symbols and cfg.symbols.indexing
                        and cfg.symbols.indexing.exclude_patterns) or {},
  })
  local lines = rg.run(cmd, "imports")

  local raw = {}
  for _, line in ipairs(lines) do
    -- rg --vimgrep format: path:line:col:text
    local path, lnum, text = line:match("^(.-):(%d+):%d+:(.*)$")
    if path and text then
      local rel  = vim.fn.fnamemodify(path, ":."):gsub("\\", "/")
      local name = parse_lhs_name(text)
      for _, r in ipairs(parse_requires(text)) do
        raw[#raw + 1] = {
          module   = r.module,
          name     = name,
          field    = r.field,
          filename = rel,
          lnum     = tonumber(lnum),
        }
      end
    end
  end
  return raw
end

--- Collect raw requires via the Tree-sitter backend (AST-accurate).
--- Only genuine `require("…")` calls are matched; comments and strings are
--- ignored by construction.
---@param cwd string
---@return RawImport[]
local function collect_via_ts(cwd)
  local ts_req = require("project_insight.imports.ts_requires")
  local files  = vim.fn.globpath(cwd, "**/*.lua", false, true)

  local ignore = { "/%.git/", "/node_modules/", "/%.cache/", "/build/", "/dist/", "/target/" }
  local raw = {}
  for _, path in ipairs(files) do
    local skip = false
    for _, pat in ipairs(ignore) do
      if path:gsub("\\", "/"):match(pat) then skip = true; break end
    end
    if not skip then
      local ok, src = pcall(vim.fn.readfile, path)
      if ok and src then
        local rel = vim.fn.fnamemodify(path, ":."):gsub("\\", "/")
        for _, e in ipairs(ts_req.scan_source(table.concat(src, "\n"))) do
          raw[#raw + 1] = {
            module   = e.module,
            name     = e.name,
            field    = e.field,
            filename = rel,
            lnum     = e.lnum,
          }
        end
      end
    end
  end
  return raw
end

--- Pick the collection backend per config (`imports.engine`) and availability.
---@param cwd string
---@return RawImport[], string method
local function collect_raw(cwd)
  local engine = (config.get().imports and config.get().imports.engine) or "auto"
  local ts_ok  = require("project_insight.imports.ts_requires").available()

  if engine == "ripgrep" then
    return collect_via_rg(cwd), "ripgrep"
  end
  if engine == "treesitter" or (engine == "auto" and ts_ok) then
    if ts_ok then return collect_via_ts(cwd), "treesitter" end
    notify.warn("imports.engine = treesitter but the Lua parser is unavailable — falling back to ripgrep")
  end
  return collect_via_rg(cwd), "ripgrep"
end

--- Scan the cwd for all require() calls.
---@return ImportData
function M.scan_cwd()
  local cwd = vim.fn.getcwd()
  local raw, method = collect_raw(cwd)

  local entries   = {}
  local counts    = {}
  local externals = {}

  for _, e in ipairs(raw) do
    local mod = e.module
    if externals[mod] == nil then
      externals[mod] = is_external(mod, cwd)
    end
    counts[mod] = (counts[mod] or 0) + 1
    entries[#entries + 1] = {
      module   = mod,
      name     = e.name,
      field    = e.field,
      filename = e.filename,
      lnum     = e.lnum,
      external = externals[mod],
    }
  end

  return { entries = entries, counts = counts, externals = externals, method = method }
end

--- Expand filter arguments (group names + literal prefixes) into prefix list.
---@param filters string[]
---@return string[]
local function expand_filters(filters)
  local cfg    = config.get()
  local groups = (cfg.imports and cfg.imports.groups) or {}
  local out    = {}
  for _, f in ipairs(filters) do
    if groups[f] then
      for _, p in ipairs(groups[f]) do out[#out + 1] = p end
    else
      out[#out + 1] = f
    end
  end
  return out
end

--- Test whether a module matches any prefix (exact or `prefix.` boundary).
---@param module string
---@param prefixes string[]
---@return boolean
local function matches(module, prefixes)
  if #prefixes == 0 then return true end
  for _, p in ipairs(prefixes) do
    if module == p or module:sub(1, #p + 1) == p .. "." then
      return true
    end
  end
  return false
end

--- Build the report lines together with a per-line lookup table mapping each
--- count / occurrence line (1-based, as displayed in the scratch buffer) to the
--- import it represents. The lookup powers "go to definition" in the report.
---@param data ImportData
---@param filters string[]
---@return string[] lines, table<integer, { module: string, field: string|nil }> line_index
function M.build_report(data, filters)
  local prefixes = expand_filters(filters or {})
  local root     = vim.fn.fnamemodify(vim.fn.getcwd(), ":t")

  -- Filter entries
  local entries = {}
  for _, e in ipairs(data.entries) do
    if matches(e.module, prefixes) then entries[#entries + 1] = e end
  end

  -- Recompute counts for the filtered set
  local counts = {}
  for _, e in ipairs(entries) do
    counts[e.module] = (counts[e.module] or 0) + 1
  end

  local unique = vim.tbl_count(counts)
  local title  = (#prefixes > 0)
    and string.format(" [filter: %s]", table.concat(filters, ", "))
    or  ""

  local lines = {
    string.format("=== Imports — %s ===%s", root, title),
    string.format("total require() calls : %d   unique modules : %d   backend : %s",
      #entries, unique, data.method or "?"),
    "",
    "--- Count ---",
  }

  ---@type table<integer, { module: string, field: string|nil }>
  local line_index = {}

  -- Sort modules by count desc, then name asc
  local mods = {}
  for mod, c in pairs(counts) do
    mods[#mods + 1] = { module = mod, count = c }
  end
  table.sort(mods, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return a.module < b.module
  end)

  for _, m in ipairs(mods) do
    local tag = data.externals[m.module] and "  (extern)" or ""
    lines[#lines + 1] = string.format("  %3d  %s%s", m.count, m.module, tag)
    -- Count line → module file (no field).
    line_index[#lines] = { module = m.module }
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = "--- Occurrences ---"

  -- Sort occurrences by module, then file, then line
  table.sort(entries, function(a, b)
    if a.module ~= b.module then return a.module < b.module end
    if a.filename ~= b.filename then return a.filename < b.filename end
    return a.lnum < b.lnum
  end)

  for _, e in ipairs(entries) do
    local imported = e.name or "?"
    if e.field then imported = imported .. " (." .. e.field .. ")" end
    lines[#lines + 1] = string.format("%s:%d  %-32s  %s",
      e.filename, e.lnum, e.module, imported)
    -- Occurrence line → field definition (if a field was accessed).
    line_index[#lines] = { module = e.module, field = e.field }
  end

  if #entries == 0 then
    lines[#lines + 1] = "  (no matching require() calls)"
  end

  return lines, line_index
end

--- Build the report lines (compatibility wrapper around `build_report`).
---@param data ImportData
---@param filters string[]
---@return string[]
function M.format_report(data, filters)
  local lines = M.build_report(data, filters)
  return lines
end

--- Write report lines to a file (directory created as needed).
---@param lines string[]
---@param out_path string
---@return boolean, string|nil
function M.write_report(lines, out_path)
  if not out_path or out_path == "" then return false, "no output_file configured" end
  local dir = vim.fn.fnamemodify(out_path, ":h")
  if vim.fn.isdirectory(dir) == 0 then
    local ok, err = pcall(vim.fn.mkdir, dir, "p")
    if not ok then return false, tostring(err) end
  end
  local fh = io.open(out_path, "w")
  if not fh then return false, "could not open file" end
  fh:write(table.concat(lines, "\n"))
  fh:close()
  return true, nil
end

--- Run the import analysis and open the report in a scratch buffer.
---@param filters string[]|nil
function M.run(filters)
  filters = filters or {}
  local cfg = config.get()

  notify.info("scanning require() calls…")
  local data = M.scan_cwd()

  if #data.entries == 0 then
    notify.warn("no require() calls found in cwd")
    return
  end

  local report, line_index = M.build_report(data, filters)

  local out_path = cfg.imports and cfg.imports.output_file
  if out_path and out_path ~= "" then
    local ok, err = M.write_report(report, out_path)
    if ok then notify.info("report written: " .. out_path)
    else       notify.warn("could not write report: " .. tostring(err)) end
  end

  local def_cfg = (cfg.imports and cfg.imports.definition) or {}
  local maps    = def_cfg.keymaps or {}

  -- Resolve the import on the current report line and reveal its definition.
  ---@param view "edit"|"float"
  local function reveal(view)
    local entry = line_index[vim.api.nvim_win_get_cursor(0)[1]]
    if not entry then
      notify.info("no import on this line (place the cursor on a Count or Occurrence line)")
      return
    end
    require("project_insight.imports.definition").reveal(entry, view,
      { border = def_cfg.border or "rounded" })
  end

  ---@type ScratchKeymap[]
  local keymaps = {}
  if maps.jump ~= false then
    keymaps[#keymaps + 1] = { "n", maps.jump or "gd", function() reveal(def_cfg.view or "edit") end,
      desc = "project-insight: go to import definition" }
  end
  if maps.preview ~= false then
    keymaps[#keymaps + 1] = { "n", maps.preview or "gp", function() reveal("float") end,
      desc = "project-insight: preview import definition" }
  end

  require("project_insight.ui.scratch").open(report,
    "Imports — " .. vim.fn.fnamemodify(vim.fn.getcwd(), ":t"),
    { keymaps = keymaps })
end

return M
