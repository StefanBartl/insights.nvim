---@module 'insights.imports.langs.util'
---@brief Shared helpers for the regex/text-based multi-language import
---       scanners (python/javascript/go/rust/c). Each scanner works on a
---       whole file's source text (not single lines) so grouped/multi-line
---       import syntax (Go `import ( … )`, Python `from x import ( … )`,
---       nested Rust `use a::{ … }`) resolves correctly.
local M = {}

--- Byte offsets (1-based) where each line of `src` starts. Index 1 is
--- always 1 (start of line 1); used with `lnum_at` to turn a byte position
--- from `string.find` into a line number without re-scanning from the top.
---@param src string
---@return integer[]
function M.line_starts(src)
  local starts = { 1 }
  local pos = 1
  while true do
    local nl = src:find("\n", pos, true)
    if not nl then break end
    starts[#starts + 1] = nl + 1
    pos = nl + 1
  end
  return starts
end

--- Binary search: 1-based line number containing byte offset `pos`.
---@param starts integer[]
---@param pos integer
---@return integer
function M.lnum_at(starts, pos)
  local lo, hi = 1, #starts
  while lo < hi do
    local mid = lo + math.ceil((hi - lo) / 2)
    if starts[mid] <= pos then lo = mid else hi = mid - 1 end
  end
  return lo
end

--- Split `s` on `sep` at nesting depth 0 only (depth tracked via `{`/`}`
--- pairs), trimming whitespace and dropping empty tokens. Used for grouped
--- import lists that may themselves contain nested `{ … }` groups (Rust).
---@param s string
---@param sep string  single character
---@return string[]
function M.split_top_level(s, sep)
  local out, depth, buf = {}, 0, {}
  for i = 1, #s do
    local c = s:sub(i, i)
    if c == "{" then depth = depth + 1 end
    if c == "}" then depth = depth - 1 end
    if c == sep and depth == 0 then
      out[#out + 1] = table.concat(buf)
      buf = {}
    else
      buf[#buf + 1] = c
    end
  end
  out[#out + 1] = table.concat(buf)

  local trimmed = {}
  for _, t in ipairs(out) do
    local v = t:match("^%s*(.-)%s*$")
    if v ~= "" then trimmed[#trimmed + 1] = v end
  end
  return trimmed
end

--- Split "a, b as c, d" into trimmed, non-empty comma-separated tokens
--- (no nesting awareness — for flat named-import lists).
---@param s string
---@return string[]
function M.split_commas(s)
  return M.split_top_level(s, ",")
end

return M
