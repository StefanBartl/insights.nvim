-- TESTS/imports_definition_spec.lua — "go to definition" from the imports
-- report: resolve the module, then find where the accessed field is defined
-- inside it.
--
-- `locate` resolves against the editor's own working directory (that is what
-- the report's entries are relative to), so the suite changes into the
-- fixture for the duration and changes back. A module name with a dot in one
-- of its path segments -- which `H.fixture`'s `.fixture-<name>` directory
-- would produce -- is not a module name at all: `resolve` turns every dot
-- into a separator, so the fixture is addressed as a plain `target.mod` from
-- inside it instead.

return function(H)
  local definition = require("insights.imports.definition")

  local dir, cleanup = H.fixture("imports-definition")
  local original_cwd = vim.fn.getcwd()

  ---@param rel string
  ---@param lines string[]
  local function write(rel, lines)
    local path = dir .. "/" .. rel
    vim.fn.mkdir(vim.fs.dirname(path), "p")
    vim.fn.writefile(lines, path)
  end

  write("lua/target/mod.lua", {
    "local M = {}", -- 1
    "", -- 2
    "local helper = 1", -- 3
    "", -- 4
    "function M.declared()", -- 5
    "  return helper", -- 6
    "end", -- 7
    "", -- 8
    "M.assigned = function()", -- 9
    "  return 2", -- 10
    "end", -- 11
    "", -- 12
    "M.table_entry = {", -- 13
    "  inner = 3,", -- 14
    "}", -- 15
    "", -- 16
    "return M", -- 17
  })

  vim.fn.chdir(dir)
  local ok_body, err_body = pcall(function()
    local module = "target.mod"

    -- No field: the top of the module ---------------------------------------
    local top, top_err = definition.locate({ module = module })
    H.eq(top_err, nil, "a resolvable module locates without an error")
    H.ok(top, "and answers a location")
    H.eq(top.srow, 0, "with no field, the answer is the top of the file")
    H.eq(top.erow, 0, "a single line, not the whole module")
    H.contains(vim.fs.normalize(top.path), "target/mod.lua", "pointing at the module's own file")

    local empty_field = definition.locate({ module = module, field = "" })
    H.eq(empty_field.srow, 0, "an empty field is treated as no field")

    -- The definition shapes the finders recognise --------------------------
    local declared = definition.locate({ module = module, field = "declared" })
    H.eq(declared.srow, 4, "`function M.declared()` is found (0-based row)")
    H.eq(declared.erow, 6, "and the range covers the body up to its `end`")

    local assigned = definition.locate({ module = module, field = "assigned" })
    H.eq(assigned.srow, 8, "`M.assigned = function()` is found")

    local entry = definition.locate({ module = module, field = "table_entry" })
    H.eq(entry.srow, 12, "a table field is found")
    H.eq(entry.erow, 14, "with the constructor's closing brace as its end")

    local helper = definition.locate({ module = module, field = "helper" })
    H.eq(helper.srow, 2, "a plain local is found too")

    -- A field the module does not define: the file still opens, at the top.
    -- Failing here would turn a slightly-wrong report line into a dead end.
    local missing = definition.locate({ module = module, field = "no_such_field" })
    H.ok(missing, "an unknown field still locates the module")
    H.eq(missing.srow, 0, "at the top of the file rather than nowhere")

    -- Unresolvable module ---------------------------------------------------
    local none, err = definition.locate({ module = "nothing.resolves.to.this.name" })
    H.eq(none, nil, "an unresolvable module has no location")
    H.contains(err or "", "could not resolve module", "and says why")

    -- reveal: edit ----------------------------------------------------------
    definition.reveal({ module = module, field = "declared" }, "edit")
    H.contains(
      vim.fs.normalize(vim.api.nvim_buf_get_name(0)),
      "target/mod.lua",
      "reveal('edit') opens the file"
    )
    H.eq(vim.api.nvim_win_get_cursor(0)[1], 5, "with the cursor on the definition (1-based)")

    -- reveal: float ---------------------------------------------------------
    local before_wins = #vim.api.nvim_list_wins()
    definition.reveal({ module = module, field = "declared" }, "float", { border = "single" })
    local float_win
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local wcfg = vim.api.nvim_win_get_config(win)
      if wcfg.relative and wcfg.relative ~= "" then
        float_win = win
      end
    end
    H.ok(float_win, "reveal('float') opens a floating preview")
    H.ok(#vim.api.nvim_list_wins() > before_wins, "in addition to the window it came from")
    local body = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(float_win), 0, -1, false)
    H.contains(body[1], "mod.lua", "headed with the file it is previewing")
    H.contains(body[1], ":5", "and the line the definition starts on")
    H.contains(table.concat(body, "\n"), "function M.declared()", "and showing the definition")
    pcall(vim.api.nvim_win_close, float_win, true)

    -- reveal on something unresolvable must not raise: it notifies and returns.
    H.ok(
      pcall(definition.reveal, { module = "nothing.resolves.here" }, "edit"),
      "reveal declines quietly when the module cannot be resolved"
    )
  end)

  vim.fn.chdir(original_cwd)
  vim.cmd("silent! %bwipeout!")
  cleanup()

  if not ok_body then
    error(err_body, 0)
  end
end
