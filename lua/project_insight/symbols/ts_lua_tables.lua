---@module 'project_insight.symbols.ts_lua_tables'
---@brief Tree-sitter-based Lua table scanner.
---
--- Finds table constructors assigned to variables, dot-index paths, and table fields.
--- Returns entries in the same format as the rest of project_insight symbols.
local M = {}

local notify = require("project_insight.util.notify").create("[project_insight.symbols.ts_lua_tables]")
local api    = vim.api
local ts     = vim.treesitter

---Build full dot-path for nested table assignments like `state.win = {}`.
---@param node TSNode
---@param bufnr integer
---@return string|nil
local function build_table_path(node, bufnr)
  local parts   = {}
  local current = node

  while current do
    local t = current:type()
    if t == "dot_index_expression" then
      local field_node = current:field("field")[1]
      if field_node then
        table.insert(parts, 1, ts.get_node_text(field_node, bufnr))
      end
      local tbl_node = current:field("table")[1]
      if tbl_node and tbl_node:type() == "identifier" then
        table.insert(parts, 1, ts.get_node_text(tbl_node, bufnr))
        break
      end
      current = tbl_node
    elseif t == "identifier" then
      table.insert(parts, 1, ts.get_node_text(current, bufnr))
      break
    else
      current = current:parent()
    end
  end

  return #parts > 0 and table.concat(parts, ".") or nil
end

---Scan one buffer for Lua table definitions.
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

  local ok_q, query = pcall(ts.query.parse, "lua", [[
    ; local t = {}  /  t = {}
    (assignment_statement
      (variable_list
        (identifier) @name)
      (expression_list
        (table_constructor)))

    ; state.win = {}
    (assignment_statement
      (variable_list
        (dot_index_expression) @path)
      (expression_list
        (table_constructor)))

    ; { field = {} }
    (field
      name: (identifier) @field_name
      value: (table_constructor))
  ]])
  if not ok_q or not query then return {} end

  local seen   = {}
  local result = {}

  for id, node in query:iter_captures(root, bufnr) do
    local capture = query.captures[id]
    local row, col = node:range()
    local name

    if capture == "name" then
      name = ts.get_node_text(node, bufnr)

    elseif capture == "path" then
      name = build_table_path(node, bufnr)

    elseif capture == "field_name" then
      local raw  = ts.get_node_text(node, bufnr)
      -- Try to prefix with parent assignment variable for context
      local par  = node:parent()
      while par and par:type() ~= "assignment_statement" do
        par = par:parent()
      end
      local ctx = nil
      if par then
        local vl = par:field("variable_list")[1]
        if vl then ctx = ts.get_node_text(vl, bufnr) end
      end
      name = ctx and (ctx .. "." .. raw) or raw
    end

    if name and not seen[name] then
      seen[name] = true
      result[#result + 1] = {
        name      = name,
        lnum      = row + 1,
        col       = col,
        filename  = nil,
        func_type = "table",
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

  notify.info(string.format("scanning %d Lua files for tables…", #filtered))

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
