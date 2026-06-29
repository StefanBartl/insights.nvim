---@module 'project_insight.imports.definition'
---@brief Locate and show the actual definition behind a require() import.
---
--- Given an import entry (module + optional accessed field), resolve the module
--- to its file, find where the field is defined inside that file, and either
--- jump there (`view = "edit"`) or show the definition in a floating preview
--- (`view = "float"`). Field location is Tree-sitter-accurate with a regex
--- fallback; resolution never executes `require(...)`.
local M = {}

local resolve = require("project_insight.imports.resolve")
local notify  = require("project_insight.util.notify").create("[project_insight.imports]")

local ts = vim.treesitter

--- Read a file's lines, or nil on failure.
---@param path string
---@return string[]|nil
local function read_lines(path)
  local ok, src = pcall(vim.fn.readfile, path)
  if ok and type(src) == "table" then return src end
  return nil
end

--- Last identifier of a name node: `foo` for `identifier`, `bar` for
--- `M.bar` / `M:bar`.
---@param node TSNode|nil
---@param src string
---@return string|nil
local function last_name(node, src)
  if not node then return nil end
  local t = node:type()
  if t == "identifier" then
    return ts.get_node_text(node, src)
  end
  if t == "dot_index_expression" or t == "method_index_expression" then
    local f = node:field("field")[1] or node:field("method")[1]
    if f then return ts.get_node_text(f, src) end
  end
  return nil
end

--- First named child of `node` with the given type, or nil.
---@param node TSNode
---@param type_name string
---@return TSNode|nil
local function child_of_type(node, type_name)
  for i = 0, node:named_child_count() - 1 do
    local ch = node:named_child(i)
    if ch:type() == type_name then return ch end
  end
  return nil
end

--- Tree-sitter search for the definition of `field` in `src`.
--- Matches `function M.field()`, `M.field = …`, `local field = …`,
--- `function field()` and `field = …` table fields.
---@param src string
---@param field string
---@return { srow: integer, erow: integer }|nil   0-based inclusive rows
local function ts_find(src, field)
  local ok_p, parser = pcall(ts.get_string_parser, src, "lua")
  if not ok_p or not parser then return nil end
  local ok_t, trees = pcall(parser.parse, parser)
  if not ok_t or not trees or #trees == 0 then return nil end

  local found
  ---@param node TSNode
  local function visit(node)
    if found then return end
    local t = node:type()

    if t == "function_declaration" then
      if last_name(node:field("name")[1], src) == field then
        found = node
      end
    elseif t == "assignment_statement" then
      local vlist = child_of_type(node, "variable_list")
      if vlist then
        for i = 0, vlist:named_child_count() - 1 do
          if last_name(vlist:named_child(i), src) == field then
            found = node
            break
          end
        end
      end
    elseif t == "field" then
      -- table constructor entry: `field = value`
      local name = node:field("name")[1]
      if name and last_name(name, src) == field then
        found = node
      end
    end

    if found then return end
    for i = 0, node:named_child_count() - 1 do
      visit(node:named_child(i))
    end
  end

  visit(trees[1]:root())
  if not found then return nil end

  local srow, _, erow, ecol = found:range()
  -- range()'s end is exclusive of the last line when ecol == 0.
  if ecol == 0 and erow > srow then erow = erow - 1 end
  return { srow = srow, erow = erow }
end

--- Regex fallback: scan lines for a definition of `field`.
---@param lines string[]
---@param field string
---@return { srow: integer, erow: integer }|nil   0-based inclusive rows
local function regex_find(lines, field)
  local fp = vim.pesc(field)
  -- Ordered so function definitions win over plain data assignments.
  local patterns = {
    "^%s*function%s+[%w_%.:]*[%.:]" .. fp .. "%s*%(",  -- function M.field(
    "^%s*local%s+function%s+" .. fp .. "%s*%(",         -- local function field(
    "^%s*function%s+" .. fp .. "%s*%(",                 -- function field(
    "^%s*[%w_%.]*%." .. fp .. "%s*=%s*function",        -- M.field = function
    "^%s*local%s+" .. fp .. "%s*=%s*function",          -- local field = function
    "^%s*[%w_%.]*%." .. fp .. "%s*=",                   -- M.field = <data>
    "^%s*local%s+" .. fp .. "%s*=",                     -- local field = <data>
    "^%s*" .. fp .. "%s*=",                             -- field = <table entry>
  }
  for _, pat in ipairs(patterns) do
    for i, line in ipairs(lines) do
      if line:match(pat) then
        local srow = i - 1
        -- Heuristic body end: a line `end` at the same indentation, else +20.
        local indent = line:match("^(%s*)") or ""
        local erow = math.min(#lines - 1, srow + 20)
        for j = i, math.min(#lines, i + 200) do
          if lines[j]:match("^" .. indent .. "end%f[%W]") then
            erow = j - 1
            break
          end
        end
        return { srow = srow, erow = erow }
      end
    end
  end
  return nil
end

--- Resolve an import entry to a concrete source location.
---@param entry { module: string, field: string|nil }
---@return { path: string, srow: integer, erow: integer }|nil, string|nil err
function M.locate(entry)
  local path = resolve.module_path(entry.module)
  if not path then
    return nil, "could not resolve module '" .. entry.module .. "' to a file"
  end

  -- No field → point at the top of the module file.
  if not entry.field or entry.field == "" then
    return { path = path, srow = 0, erow = 0 }
  end

  local lines = read_lines(path)
  if not lines then
    return nil, "could not read " .. path
  end

  local src = table.concat(lines, "\n")
  local hit = ts_find(src, entry.field) or regex_find(lines, entry.field)
  if not hit then
    -- Field not found: still open the file at the top rather than failing.
    return { path = path, srow = 0, erow = 0 }
  end
  return { path = path, srow = hit.srow, erow = hit.erow }
end

--- Jump to the definition in the current window.
---@param loc { path: string, srow: integer }
local function open_edit(loc)
  vim.cmd("edit " .. vim.fn.fnameescape(loc.path))
  pcall(vim.api.nvim_win_set_cursor, 0, { loc.srow + 1, 0 })
  vim.cmd("normal! zz")
end

--- Show the definition in a floating preview window.
---@param loc { path: string, srow: integer, erow: integer }
---@param border string
local function open_float(loc, border)
  local lines = read_lines(loc.path) or {}
  local body = {}
  for i = loc.srow + 1, math.min(#lines, loc.erow + 1) do
    body[#body + 1] = lines[i]
  end
  if #body == 0 then body = { "(empty)" } end

  local header = string.format("%s:%d", vim.fn.fnamemodify(loc.path, ":."), loc.srow + 1)
  table.insert(body, 1, "── " .. header .. " ──")

  vim.lsp.util.open_floating_preview(body, "lua", {
    border     = border or "rounded",
    focusable  = true,
    max_width  = math.min(120, math.max(40, vim.o.columns - 4)),
    max_height = math.min(30, math.max(8, vim.o.lines - 6)),
    close_events = { "CursorMoved", "BufHidden", "InsertEnter", "FocusLost" },
  })
end

--- Resolve and reveal the definition for an import entry.
---@param entry { module: string, field: string|nil }
---@param view "edit"|"float"|nil   defaults to "edit"
---@param opts { border: string|nil }|nil
function M.reveal(entry, view, opts)
  local loc, err = M.locate(entry)
  if not loc then
    notify.warn(err or "definition not found")
    return
  end
  if view == "float" then
    open_float(loc, (opts and opts.border) or "rounded")
  else
    open_edit(loc)
  end
end

return M
