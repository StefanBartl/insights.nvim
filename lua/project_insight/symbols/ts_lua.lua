---@module 'project_insight.symbols.ts_lua'
---@brief Tree-sitter-based Lua symbol scanner (more precise than regex).
---
--- Loads each file into a scratch buffer, parses with nvim-treesitter,
--- and extracts function definitions via AST traversal.
--- Slower than rg but produces exact names for complex patterns like
--- `function M.foo:bar()` or `tbl.key = function()`.
local M = {}

local notify = require("project_insight.util.notify").create("[project_insight.symbols.ts_lua]")
local api    = vim.api
local ts     = vim.treesitter

---Scan one buffer for Lua function definitions.
---@param bufnr integer
---@return { name: string, lnum: integer, col: integer, file: string|nil }[]
function M.scan_buffer(bufnr)
  if not api.nvim_buf_is_valid(bufnr) then return {} end

  local ok_ft, ft = pcall(api.nvim_get_option_value, "filetype", { buf = bufnr })
  if not ok_ft or ft ~= "lua" then return {} end

  local ok_p, parser_obj = pcall(ts.get_parser, bufnr, "lua")
  if not ok_p or not parser_obj then return {} end

  local ok_t, trees = pcall(parser_obj.parse, parser_obj)
  if not ok_t or not trees or #trees == 0 then return {} end

  local root   = trees[1]:root()
  local seen   = {}
  local result = {}

  local function visit(node)
    local t = node:type()

    if t == "function_declaration" then
      local name_nodes = node:field("name")
      if name_nodes and #name_nodes > 0 then
        local name = ts.get_node_text(name_nodes[1], bufnr)
        if name and not seen[name] then
          seen[name] = true
          local row, col = name_nodes[1]:range()
          result[#result + 1] = { name=name, lnum=row+1, col=col, file=nil }
        end
      end
    end

    if t == "assignment_statement" then
      local var_list  = node:field("left")
      local expr_list = node:field("right")
      if var_list and expr_list and #var_list > 0 and #expr_list > 0 then
        local vn = var_list[1]
        local en = expr_list[1]
        if en:type() == "function_definition" then
          local name, row, col
          if vn:type() == "identifier" then
            name = ts.get_node_text(vn, bufnr)
            row, col = vn:range()
          elseif vn:type() == "dot_index_expression" then
            local fn = vn:field("field")
            if fn and #fn > 0 then
              name = ts.get_node_text(fn[1], bufnr)
              row, col = fn[1]:range()
            end
          end
          if name and not seen[name] then
            seen[name] = true
            result[#result + 1] = { name=name, lnum=row+1, col=col, file=nil }
          end
        end
      end
    end

    if t == "field" then
      local fn = node:field("name")
      local fv = node:field("value")
      if fn and fv and #fn > 0 and #fv > 0 then
        if fv[1]:type() == "function_definition" then
          local name = ts.get_node_text(fn[1], bufnr)
          if name and not seen[name] then
            seen[name] = true
            local row, col = fn[1]:range()
            result[#result + 1] = { name=name, lnum=row+1, col=col, file=nil }
          end
        end
      end
    end

    for child in node:iter_children() do visit(child) end
  end

  visit(root)

  table.sort(result, function(a, b) return a.name < b.name end)
  return result
end

---Scan all .lua files in cwd using Tree-sitter.
---Returns flat list of entries with `.filename` set.
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

  notify.info(string.format("scanning %d Lua files with Tree-sitter…", #filtered))

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
