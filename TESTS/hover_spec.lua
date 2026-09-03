-- Test code: a contribution asserted non-nil on the line above is still
-- optional to the type checker, and the nil guards it asks for would hide the
-- very failure this file exists to report -- H.ok is the guard.
---@diagnostic disable: need-check-nil
-- TESTS/hover_spec.lua — the hover.nvim contribution.
--
-- Two properties carry this, and neither is "does it find the importers".
--
--   1. **A cold index says nothing and starts nothing.** A full scan was
--      measured on 2026-09-03 at 631 ms for one repository and 1.9 s for
--      another. A preview that could set that off from a cursor movement is
--      the exact thing hover.nvim's opt-in model exists to prevent, and the
--      failure would be invisible: the float would simply feel slow.
--   2. **A module nobody imports is silence, not a zero.** Every dotted name
--      in prose looks like a module, so answering "0 files import this" for
--      each of them would be noise on every `a.b.c` in a comment. The
--      importer count *is* the gate.

return function(H)
  local hover = require("insights.hover")
  local index = require("insights.imports.index")

  -- dotted name ---------------------------------------------------------------
  H.eq(
    hover.dotted_at('local n = require("insights.imports")', 25),
    "insights.imports",
    "inside a require"
  )
  H.eq(hover.dotted_at("see a.b.c here", 6), "a.b.c", "bare in prose")
  H.eq(hover.dotted_at("just-a-word here", 3), nil, "no dot is not a module name")
  H.eq(hover.dotted_at("", 0), nil, "an empty line")
  H.eq(hover.dotted_at("a.b", 99), nil, "a column past the end")
  H.eq(
    hover.dotted_at("trailing.dot. here", 5),
    "trailing.dot",
    "a trailing dot is not part of the name"
  )

  -- the contribution ----------------------------------------------------------
  local captured = {}
  local real_registry = package.loaded["hover.registry"]
  package.loaded["hover.registry"] = {
    register = function(name, contribution)
      captured.name = name
      captured.contribution = contribution
    end,
    position_at = function() end,
  }

  hover._reset()
  H.ok(hover.setup(), "setup registers")
  H.eq(captured.name, "insights.nvim", "under this plugin's name")
  H.ok(type(captured.contribution.positions) == "table", "as a position preview")

  local answer = captured.contribution.positions[1]
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    'local a = require("pkg.used")',
    'local b = require("pkg.unused")',
    "local c = 1",
  })

  -- Cold: nothing, and nothing started.
  index.forget()
  H.eq(answer(buf, 1, 22), nil, "a cold index answers nothing")

  ---@param module string
  ---@param filename string
  ---@param lnum integer
  ---@return table
  local function entry(module, filename, lnum)
    return {
      module = module,
      name = "x",
      filename = filename,
      lnum = lnum,
      lang = "lua",
      external = false,
    }
  end

  index.put(nil, {
    entries = {
      entry("pkg.used", "a.lua", 1),
      entry("pkg.used", "b.lua", 4),
      entry("pkg.used", "b.lua", 9),
    },
    counts = {},
    externals = {},
    lang_totals = { lua = 3 },
    methods = { lua = "treesitter" },
  })

  local used = answer(buf, 1, 22)
  H.ok(type(used) == "table", "an imported module answers")
  H.eq(used.title, "pkg.used", "titled with the module name")
  local body = table.concat(used.lines, "\n")
  H.ok(body:find("2 file(s)", 1, true) ~= nil, "with the number of files")
  H.ok(body:find("3 occurrence(s)", 1, true) ~= nil, "and of occurrences")
  H.ok(body:find("a.lua", 1, true) ~= nil, "and names them")

  -- The gate: a dotted name nobody imports is silence rather than a zero.
  H.eq(answer(buf, 2, 24), nil, "a module nothing imports answers nothing")

  -- A line with no dotted name at all never reaches the lookup.
  H.eq(answer(buf, 3, 6), nil, "a line without a module name")

  -- Staleness is said out loud rather than smoothed over.
  vim.api.nvim_exec_autocmds("BufWritePost", {})
  local stale = answer(buf, 1, 22)
  H.ok(
    table.concat(stale.lines, "\n"):find("written since", 1, true) ~= nil,
    "a stale index says so in the float"
  )

  -- degradation ----------------------------------------------------------------
  vim.api.nvim_buf_delete(buf, { force = true })
  index.forget()

  package.loaded["hover.registry"] = nil
  local real_preload = package.preload["hover.registry"]
  package.preload["hover.registry"] = function()
    error("module 'hover.registry' not found")
  end
  hover._reset()
  H.ok(not hover.setup(), "without hover.nvim, setup declines quietly")
  package.preload["hover.registry"] = real_preload

  package.loaded["hover.registry"] = { register = function() end }
  hover._reset()
  H.ok(not hover.setup(), "an older hover.nvim without positions is declined")

  hover._reset()
  package.loaded["hover.registry"] = real_registry
end
