-- Test code: a lookup asserted non-nil on the line above is still optional to
-- the type checker, and the nil guards it asks for would hide the very failure
-- this file exists to report -- H.ok is the guard.
---@diagnostic disable: need-check-nil
-- TESTS/import_index_spec.lua — the remembered scan, and the line it draws.
--
-- The property worth breaking the build over is not "does the lookup find the
-- importers": it is **that a cold index answers `nil` instead of scanning**.
-- A full scan was measured on 2026-09-03 at 631 ms for hover.nvim and 1.9 s
-- for documentation.nvim, and the whole reason this module exists is that a
-- passive consumer — a statusline, a hover, anything that speaks while the
-- reader reads — cannot start one. A `get` that quietly built the index would
-- put those 631 ms back exactly where they must not be, and nothing in the
-- returned value would show it.
--
-- The fixture is a synthetic `ImportData` rather than a real scan, for the
-- same reason: a spec that walks a directory tree measures the machine it
-- runs on. What is pinned here is the selection and the states, which is what
-- the module actually owns.

return function(H)
  local index = require("insights.imports.index")
  local imports = require("insights.imports")

  ---@param module string
  ---@param filename string
  ---@param lnum integer
  ---@return table
  local function entry(module, filename, lnum)
    return {
      module = module,
      name = "x",
      field = nil,
      filename = filename,
      lnum = lnum,
      lang = "lua",
      external = false,
    }
  end

  local data = {
    entries = {
      entry("hover.registry", "b.lua", 9),
      entry("hover.registry", "a.lua", 3),
      entry("hover.registry", "a.lua", 1),
      entry("hover.float", "c.lua", 2),
    },
    counts = {},
    externals = {},
    lang_totals = { lua = 4 },
    methods = { lua = "treesitter" },
  }

  -- cold ----------------------------------------------------------------------
  index.forget()
  H.eq(imports.reverse_lookup("hover.registry"), nil, "a cold index answers nil")
  H.eq(index.get(), nil, "and has nothing to hand back")

  -- warm ----------------------------------------------------------------------
  index.put(nil, data)
  local hit = imports.reverse_lookup("hover.registry")
  H.ok(hit ~= nil, "a warm index answers")
  H.eq(#hit.entries, 3, "with every occurrence of the module")
  H.eq(#hit.files, 2, "and the distinct files they sit in")
  H.eq(hit.files[1], "a.lua", "files come out sorted")
  H.eq(hit.entries[1].lnum, 1, "and so do the occurrences within a file")
  H.eq(hit.stale, false, "a fresh index is not stale")
  H.ok(type(hit.built_at) == "number", "and says when it was built")

  -- A module nobody imports is an empty answer, not a missing one: the caller
  -- can tell "nothing imports this" from "there is no index", and those are
  -- different sentences.
  local none = imports.reverse_lookup("hover.absent")
  H.ok(none ~= nil, "an unimported module still answers")
  H.eq(#none.entries, 0, "with nothing in it")

  -- staleness ------------------------------------------------------------------
  -- Reported, not acted on. An import list from before the last save is
  -- usually still right, and only the caller knows whether "probably still
  -- right" is good enough for the sentence it is about to write.
  vim.api.nvim_exec_autocmds("BufWritePost", {})
  local after = imports.reverse_lookup("hover.registry")
  H.eq(after.stale, true, "a write marks the index stale")
  H.eq(#after.entries, 3, "and it still answers, which is the point of a flag")

  -- guards ---------------------------------------------------------------------
  H.eq(imports.reverse_lookup(""), nil, "an empty module name is not a query")
  ---@diagnostic disable-next-line: param-type-mismatch
  H.eq(imports.reverse_lookup(nil), nil, "and neither is nothing at all")

  index.forget()
  H.eq(imports.reverse_lookup("hover.registry"), nil, "forget() puts it back to cold")
end
