---@module 'insights.imports.langs.python'
---@brief Regex-based Python import scanner.
---
--- Handles `import x`, `import x.y as z`, `import x, y`, `from x import a, b`,
--- `from x import a as b`, `from x import (a, b, c)` (parenthesized, possibly
--- multi-line) and relative imports (`from . import x`, `from ..pkg import y`).
local M = {}

local util = require("insights.imports.langs.util")

M.id         = "python"
M.label      = "Python"
M.extensions = { "py" }
M.rg_prefilter = "^\\s*(import|from)\\s"

--- Drop a trailing `# comment` (heuristic: no attempt to avoid `#` inside
--- string literals — import lines rarely contain one).
---@param line string
---@return string
local function strip_comment(line)
  local idx = line:find("#")
  if idx then return line:sub(1, idx - 1) end
  return line
end

--- Scan Python source text for import statements.
---@param src string
---@return { module: string, name: string|nil, field: string|nil, lnum: integer }[]
function M.scan_source(src)
  local result = {}
  local lines = vim.split(src, "\n", { plain = true })
  local i = 1

  while i <= #lines do
    local line = strip_comment(lines[i])
    local lnum = i

    local from_mod, rest = line:match("^%s*from%s+([%w_%.]+)%s+import%s+(.*)$")
    if from_mod then
      local buf = rest
      local depth = 0
      for _ in buf:gmatch("%(") do depth = depth + 1 end
      for _ in buf:gmatch("%)") do depth = depth - 1 end
      while depth > 0 and i < #lines do
        i = i + 1
        local cont = strip_comment(lines[i])
        buf = buf .. " " .. cont
        for _ in cont:gmatch("%(") do depth = depth + 1 end
        for _ in cont:gmatch("%)") do depth = depth - 1 end
      end
      buf = buf:gsub("[%(%)\\]", "")

      for _, tok in ipairs(util.split_commas(buf)) do
        if tok ~= "*" then
          local symbol, alias = tok:match("^([%w_]+)%s+as%s+([%w_]+)$")
          symbol = symbol or tok
          if symbol:match("^[%w_]+$") then
            result[#result + 1] = {
              module = from_mod,
              name   = alias or symbol,
              field  = alias and symbol or nil,
              lnum   = lnum,
            }
          end
        end
      end
    else
      local plain = line:match("^%s*import%s+(.+)$")
      if plain then
        plain = plain:gsub("\\", "")
        for _, tok in ipairs(util.split_commas(plain)) do
          local mod, alias = tok:match("^([%w_%.]+)%s+as%s+([%w_]+)$")
          mod = mod or tok
          if mod:match("^[%w_][%w_%.]*$") then
            result[#result + 1] = { module = mod, name = alias, lnum = lnum }
          end
        end
      end
    end

    i = i + 1
  end

  return result
end

--- Relative imports (`from . import x`) are always project-local; absolute
--- ones resolve against `<cwd>/<module path>.py` or `.../__init__.py`.
---@param module string
---@param cwd string
---@return boolean external
function M.is_external(module, cwd)
  if module:sub(1, 1) == "." then return false end

  local rel = (module:gsub("%.", "/"))
  local candidates = {
    cwd .. "/" .. rel .. ".py",
    cwd .. "/" .. rel .. "/__init__.py",
  }
  for _, p in ipairs(candidates) do
    if vim.fn.filereadable(p) == 1 then return false end
  end
  return true
end

return M
