---@module 'project_insight.symbols.ts_lua_strings'
---@brief Tree-sitter-based Lua string literal scanner.
---
--- Collects all unique string literals from a buffer or cwd.
--- Useful for auditing magic strings, require paths, and event names.
local M = {}

local notify = require("project_insight.util.notify").create("[project_insight.symbols.ts_lua_strings]")
local api    = vim.api
local ts     = vim.treesitter

---Scan one buffer for Lua string literals.
---@param bufnr integer
---@return { name: string, lnum: integer, col: integer, filename: string|nil, func_type: string }[]
function M.scan_buffer(bufnr)
  if not api.nvim_buf_is_valid(bufnr) then return {} end

  local ok_ft, ft = pcall(api.nvim_get_option_value, "filetype", { buf = bufnr })
  if not ok_ft or ft ~= "lua" then return {} end

  local ok_p, parser_obj = pcall(ts.get_parser, bufnr, "lua")
  if not ok_p or not parser_obj then return {} end

  local ok_t, trees = pcall(parser_obj.parse, parser_obj)
  if not ok_t or not trees or #trees == 0 then return {} end

  local root = trees[1]:root()

  local ok_q, query = pcall(ts.query.parse, "lua", [[ (string) @str ]])
  if not ok_q or not query then return {} end

  local seen   = {}
  local result = {}

  for _, node in query:iter_captures(root, bufnr) do
    local text = ts.get_node_text(node, bufnr)
    if text and not seen[text] then
      seen[text] = true
      local row, col = node:range()
      result[#result + 1] = {
        name      = text,
        lnum      = row + 1,
        col       = col,
        filename  = nil,
        func_type = "string",
      }
    end
  end

  table.sort(result, function(a, b) return a.name < b.name end)
  return result
end

---Scan all .lua files in cwd.
---@return table[]
function M.scan_cwd()
  local cwd   = vim.fn.getcwd()
  local files = vim.fn.globpath(cwd, "**/*.lua", false, true)

  local ignore = { "/%.git/", "/node_modules/", "/%.cache/", "/build/", "/dist/", "/target/" }
  local filtered = {}
  for _, f in ipairs(files) do
    local ok = true
    for _, pat in ipairs(ignore) do
      if f:match(pat) then ok = false; break end
    end
    if ok then filtered[#filtered + 1] = f end
  end

  if #filtered == 0 then
    notify.warn("no Lua files found in cwd")
    return {}
  end

  notify.info(string.format("scanning %d Lua files for strings…", #filtered))

  local all = {}
  for _, path in ipairs(filtered) do
    local bufnr = vim.fn.bufadd(path)
    vim.fn.bufload(bufnr)
    local matches = M.scan_buffer(bufnr)
    for _, m in ipairs(matches) do
      m.filename = path
      all[#all + 1] = m
    end
  end

  return all
end

return M
