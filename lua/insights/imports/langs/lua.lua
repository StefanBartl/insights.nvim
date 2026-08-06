---@module 'insights.imports.langs.lua'
---@brief Lua require() scanner — Tree-sitter-accurate by default (see
---       `insights.imports.ts_requires`), with a regex/line-scan fallback
---       when the Lua Tree-sitter parser is unavailable or `imports.engine`
---       forces `"ripgrep"`.
local M = {}

M.id = "lua"
M.label = "Lua"
M.extensions = { "lua" }
M.rg_prefilter = "require"

---@internal
--- A valid module path: identifier chars plus dot/dash/slash separators.
--- Filters out punctuation garbage matched from comments / string-building code.
---@param mod string
---@return boolean
local function is_module_path(mod)
  return mod:match("^[%w_][%w_%.%-/]*$") ~= nil
end

---@internal
--- Parse a single source line for every require occurrence.
--- Returns a list because a line may contain more than one call.
---@param line string
---@return { module: string, field: string|nil }[]
local function parse_requires(line)
  local out = {}
  for mod in line:gmatch("require%s*%(?%s*[\"']([^\"']+)[\"']") do
    if is_module_path(mod) then
      out[#out + 1] = { module = mod }
    end
  end
  -- Resolve a trailing field for each require independently by re-scanning with
  -- a pattern that also captures the field; align by order of appearance.
  for mod, field in line:gmatch("require%s*%(?%s*[\"']([^\"']+)[\"']%)?%s*%.([%w_]+)") do
    for _, e in ipairs(out) do
      if e.module == mod and not e.field then
        e.field = field
        break
      end
    end
  end
  return out
end

---@internal
--- Extract the local variable name a require is assigned to, if any.
---@param line string
---@return string|nil
local function parse_lhs_name(line)
  return line:match("^%s*local%s+([%w_]+)%s*=%s*require")
    or line:match("^%s*([%w_][%w_%.]*)%s*=%s*require")
end

--- Regex/line-scan fallback for a whole file's source text.
---@param src string
---@return { module: string, name: string|nil, field: string|nil, lnum: integer }[]
function M.scan_source(src)
  local result = {}
  for lnum, line in ipairs(vim.split(src, "\n", { plain = true })) do
    local name = parse_lhs_name(line)
    for _, r in ipairs(parse_requires(line)) do
      result[#result + 1] = { module = r.module, name = name, field = r.field, lnum = lnum }
    end
  end
  return result
end

--- Tree-sitter (AST-accurate) scan — only meaningful when `ts_available()`.
---@param src string
---@return { module: string, name: string|nil, field: string|nil, lnum: integer }[]
function M.ts_scan_source(src)
  return require("insights.imports.ts_requires").scan_source(src)
end

--- Is the Lua Tree-sitter parser available?
---@return boolean
function M.ts_available()
  return require("insights.imports.ts_requires").available()
end

--- Resolve whether a module path corresponds to a .lua file inside cwd.
---@param module string
---@param cwd string
---@return boolean external
function M.is_external(module, cwd)
  local rel = module:gsub("%.", "/")
  local candidates = {
    cwd .. "/lua/" .. rel .. ".lua",
    cwd .. "/lua/" .. rel .. "/init.lua",
    cwd .. "/" .. rel .. ".lua",
    cwd .. "/" .. rel .. "/init.lua",
  }
  for _, p in ipairs(candidates) do
    if vim.fn.filereadable(p) == 1 then
      return false
    end
  end
  return true
end

return M
