---@module 'insights.hover'
---@brief Who imports the module under the cursor.
---@description
--- You are reading a module header, or a `require` in someone else's file, and
--- the question is who depends on this. `:Insights imports reverse` answers it
--- in a scratch buffer. This puts the same answer in
--- [hover.nvim](https://github.com/StefanBartl/hover.nvim)'s float, for the
--- dotted name the cursor is on.
---
--- **It answers out of the remembered scan and never starts one.** A full walk
--- of the working directory was measured on 2026-09-03 at 631 ms for
--- hover.nvim and 1.9 s for documentation.nvim; a hover that could set that
--- off from a cursor movement is the exact shape of thing hover.nvim's opt-in
--- model exists to prevent. So `imports.reverse_lookup` answers from
--- `imports.index` or answers `nil`, and a cold index means this contribution
--- says nothing at all. `:checkhealth insights` reports the cold state,
--- because "quiet" and "broken" look identical from a float that never opens.
---
--- **A module nobody imports is silence, not a zero.** Every dotted name in
--- prose looks like a module -- `a.b.c`, `read.write.execute` -- and answering
--- "0 files import this" for each of them would be the noise the position kind
--- was built to avoid. The importer count *is* the gate: something imports it,
--- or there is nothing worth interrupting a reader for.
---
--- **A stale index says so rather than looking current.** A write marks the
--- index stale and the flag comes back with the answer. An import list from
--- before your last save is usually still right, and hiding that it might not
--- be is the one thing worse than saying nothing -- the same stance
--- documentation.nvim's map preview takes for the same reason.
---
--- **On sharing the float with documentation.nvim.** Both answer for a dotted
--- name, and both are right: one says what the module is, this one says who
--- uses it. hover.nvim steps between them with `<M-n>` / `:Hover next`, so the
--- second answer is a page rather than a casualty. Before that existed the
--- first plugin to register won and the other was invisible.
---
---@see insights.imports.index

local M = {}

local api = vim.api

---@type boolean
local _registered = false

---@type integer How many importing files to name before summarising the rest.
--- Ten fills a default float without crowding it; past that the list stops
--- being readable and the count is the useful part.
local MAX_FILES = 10

---@internal
--- The dotted name under `col`, or nil.
---
--- Deliberately its own small reader rather than a shared one. The obvious
--- candidate is documentation.nvim's, which is public -- and depending on a
--- sibling plugin to answer "what is under my cursor" would make an optional
--- integration a hard dependency of an unrelated one. The rule is the whole
--- implementation: at least one dot, and the characters a module name is made
--- of.
---@param line string|nil
---@param col integer 0-based
---@return string|nil
local function dotted_at(line, col)
  if type(line) ~= "string" or line == "" then
    return nil
  end
  local i = 1
  while i <= #line do
    local s, e = line:find("[%w_][%w_%.]*", i)
    if not s then
      return nil
    end
    -- `col` is 0-based and `find` is 1-based; the cursor counts as inside the
    -- token it sits on, including its last character.
    if col + 1 >= s and col + 1 <= e then
      local token = line:sub(s, e):gsub("%.+$", "")
      if token:find("%.") then
        return token
      end
      return nil
    end
    i = e + 1
  end
  return nil
end

---@internal
--- A path shown relative to the working directory when it is inside it.
---@param path string
---@return string
local function readable(path)
  local cwd = (vim.fn.getcwd():gsub("\\", "/"):gsub("/+$", "")) .. "/"
  local p = (path:gsub("\\", "/"))
  if p:sub(1, #cwd) == cwd then
    return p:sub(#cwd + 1)
  end
  return p
end

---@internal
--- The float's lines for one lookup result.
---@param hit { files: string[], entries: table[], built_at: integer, stale: boolean }
---@return string[]
local function lines_for(hit)
  local lines = {
    ("%d file(s) import this, %d occurrence(s)"):format(#hit.files, #hit.entries),
    "",
  }
  for i, file in ipairs(hit.files) do
    if i > MAX_FILES then
      lines[#lines + 1] = ("… and %d more"):format(#hit.files - MAX_FILES)
      break
    end
    lines[#lines + 1] = "  " .. readable(file)
  end
  if hit.stale then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "! a file was written since this was scanned"
  end
  return lines
end

--- Register the position preview with hover.nvim, if it is installed.
---@return boolean registered
function M.setup()
  if _registered then
    return true
  end

  local ok, registry = pcall(require, "hover.registry")
  if not ok or type(registry) ~= "table" or type(registry.register) ~= "function" then
    return false
  end
  -- An older hover.nvim with a registry but no position kind would accept the
  -- registration and never ask for it. Declining is the honest answer.
  if type(registry.position_at) ~= "function" then
    return false
  end

  registry.register("insights.nvim", {
    positions = {
      ---@param bufnr integer
      ---@param row integer 1-based
      ---@param col integer 0-based
      ---@return table|nil
      function(bufnr, row, col)
        if not api.nvim_buf_is_valid(bufnr) then
          return nil
        end
        local module = dotted_at(api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1], col)
        if not module then
          return nil
        end

        local hit = require("insights.imports").reverse_lookup(module)
        -- Cold index, or nothing imports it. Both are silence: see this
        -- module's header for why the second one is not a zero.
        if not hit or #hit.files == 0 then
          return nil
        end

        return { lines = lines_for(hit), title = module }
      end,
    },
  })

  _registered = true
  return true
end

---@internal
--- The dotted-name test on its own, for the spec suite.
---@param line string
---@param col integer
---@return string|nil
function M.dotted_at(line, col)
  return dotted_at(line, col)
end

---@internal
--- Forget the registration. Tests only.
---@return nil
function M._reset()
  _registered = false
end

return M
