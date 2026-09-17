-- TESTS/symbols_ts_lua_spec.lua — the three Tree-sitter Lua scanners:
-- functions, tables and string literals.
--
-- All three are driven against real buffers parsed by the real grammar. A
-- Tree-sitter query naming a node the grammar does not have fails quietly --
-- `pcall(ts.query.parse, …)` returns false and the scanner answers "nothing
-- found", which is indistinguishable from a file with no symbols in it. Every
-- assertion that expects a non-empty result is therefore also a check that
-- the node names are still current. Verified against Neovim 0.12.2's bundled
-- tree-sitter-lua on 2026-09-17.
--
-- `scan_cwd` is not exercised: it walks every .lua file under the working
-- directory and loads each into a buffer, which on this repository alone is
-- ~50 files -- a measurement of the machine, not of the scanner. The
-- per-buffer scan it calls in a loop is covered exhaustively instead.

return function(H)
  local ts_lua = require("insights.symbols.ts_lua")
  local ts_tables = require("insights.symbols.ts_lua_tables")
  local ts_strings = require("insights.symbols.ts_lua_strings")

  if not pcall(vim.treesitter.get_string_parser, "", "lua") then
    print("      (skipped: the Lua Tree-sitter parser is unavailable here)")
    return
  end

  ---@param lines string[]
  ---@param ft string|nil
  ---@return integer
  local function buffer(lines, ft)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].filetype = ft or "lua"
    return buf
  end

  ---@param matches table[]
  ---@return table<string, table>
  local function by_name(matches)
    local out = {}
    for _, m in ipairs(matches) do
      out[m.name] = m
    end
    return out
  end

  -- ── ts_lua: function definitions ─────────────────────────────────────────
  do
    local buf = buffer({
      "local M = {}", -- 1
      "", -- 2
      "function M.declared()", -- 3
      "end", -- 4
      "", -- 5
      "local function local_fn()", -- 6
      "end", -- 7
      "", -- 8
      "function M:method()", -- 9
      "end", -- 10
      "", -- 11
      "assigned = function()", -- 12
      "end", -- 13
      "", -- 14
      "M.dotted_assigned = function()", -- 15
      "end", -- 16
      "", -- 17
      "local t = {", -- 18
      "  in_table = function() end,", -- 19
      "}", -- 20
      "", -- 21
      "return M", -- 22
    })

    local found = by_name(ts_lua.scan_buffer(buf))

    H.ok(found["M.declared"], "a `function M.x()` declaration is found under its full name")
    H.eq(found["M.declared"].lnum, 3, "on the line it is declared")
    H.ok(found.local_fn, "a `local function` is found")
    H.ok(found["M:method"], "and a method declaration, colon included")
    H.ok(found.in_table, "and a function in a table constructor")

    -- Regression: the whole `assignment_statement` branch used to be dead. It
    -- read the target and the value through `node:field("left")` and
    -- `node:field("right")`, but tree-sitter-lua exposes `variable_list` and
    -- `expression_list` as *typed children*, not as named fields -- both calls
    -- returned an empty list on every assignment, so the branch never fired.
    -- `insights.imports.ts_requires`/`insights.imports.definition` already
    -- carried a `child_of_type` helper for this reason; `ts_lua.lua` has its
    -- own copy now. With `symbols.use_treesitter_for_lua = true`, a module
    -- written as `M.foo = function() … end` used to contribute no symbols at
    -- all, while `function M.foo() … end` contributed all of them.
    H.ok(found.assigned, "`assigned = function()` is found")
    H.ok(found.dotted_assigned, "and so is `M.dotted_assigned = function()`")
    H.ok(type(found.local_fn.col) == "number", "every match carries a column")

    -- Sorted by name, so two scans of the same file list in the same order.
    local sorted = ts_lua.scan_buffer(buf)
    for i = 2, #sorted do
      H.ok(sorted[i - 1].name <= sorted[i].name, "results come out sorted by name")
    end

    -- A name is reported once, however often it is defined: the scanner is a
    -- symbol list, not an occurrence list.
    local dupes = buffer({
      "local function same() end",
      "local function same() end",
    })
    H.eq(#ts_lua.scan_buffer(dupes), 1, "a repeated name is reported once")
    vim.api.nvim_buf_delete(dupes, { force = true })

    vim.api.nvim_buf_delete(buf, { force = true })
  end

  -- ── ts_lua_tables: table definitions ─────────────────────────────────────
  do
    local buf = buffer({
      "local plain = {}", -- 1
      "state.win = {}", -- 2
      "deep.nested.path = {}", -- 3
      "local cfg = {", -- 4
      "  inner = {},", -- 5
      "}", -- 6
      "local not_a_table = 1", -- 7
      "local fn = function() end", -- 8
    })

    local found = by_name(ts_tables.scan_buffer(buf))

    H.ok(found.plain, "a plain `local x = {}` is a table")
    H.eq(found.plain.lnum, 1, "on its line")
    H.eq(found.plain.func_type, "table", "tagged as a table for the picker")
    H.ok(found["state.win"], "a dot-index assignment keeps its path")
    H.ok(found["deep.nested.path"], "however deep")
    H.ok(found.cfg, "a table with contents is still a table")
    H.eq(found.not_a_table, nil, "a number is not")
    H.eq(found.fn, nil, "and neither is a function")

    -- Regression: a nested table field used never to get its context.
    -- `scan_buffer` prefixes a `field_name` capture with the enclosing
    -- assignment's target via `par:field("variable_list")[1]` -- but in
    -- tree-sitter-lua `assignment_statement` exposes `variable_list` as a
    -- *typed child*, not a named field, so that call always returned an empty
    -- list and `ctx` was always nil. `ts_lua_tables.lua` has its own
    -- `child_of_type` helper now, the same pattern `insights.imports
    -- .ts_requires`/`insights.imports.definition` already used.
    H.eq(found.inner, nil, "a nested table field is never listed under its bare name")
    H.ok(found["cfg.inner"], "always with the enclosing table as a prefix")

    -- Sorted, and de-duplicated by name, like the function scanner.
    local sorted = ts_tables.scan_buffer(buf)
    for i = 2, #sorted do
      H.ok(sorted[i - 1].name <= sorted[i].name, "table results are sorted by name")
    end

    vim.api.nvim_buf_delete(buf, { force = true })
  end

  -- ── ts_lua_strings: string literals ──────────────────────────────────────
  do
    local buf = buffer({
      'local a = "hello"',
      "local b = 'world'",
      'local c = "hello"',
      "local d = [[long]]",
      "-- a comment is not a string",
      "local n = 42",
    })

    local strings = ts_strings.scan_buffer(buf)
    local text = {}
    for _, s in ipairs(strings) do
      text[s.name] = s
    end

    H.ok(text['"hello"'], "a double-quoted literal is collected, quotes and all")
    H.ok(text["'world'"], "and a single-quoted one")
    H.ok(text["[[long]]"], "and a long-bracket one")
    H.eq(#strings, 3, "a repeated literal is collected once")
    H.eq(text['"hello"'].func_type, "string", "tagged as a string for the picker")
    H.eq(text['"hello"'].lnum, 1, "reported at its first occurrence")
    H.eq(text["42"], nil, "a number is not a string")
    for i = 2, #strings do
      H.ok(strings[i - 1].name <= strings[i].name, "string results are sorted")
    end

    vim.api.nvim_buf_delete(buf, { force = true })
  end

  -- ── the guards all three share ───────────────────────────────────────────
  for name, scanner in pairs({
    ts_lua = ts_lua,
    ts_lua_tables = ts_tables,
    ts_lua_strings = ts_strings,
  }) do
    local where = name .. ": "

    H.eq(#scanner.scan_buffer(999999), 0, where .. "a buffer that does not exist scans to nothing")

    local deleted = buffer({ "local x = {}" })
    vim.api.nvim_buf_delete(deleted, { force = true })
    H.eq(#scanner.scan_buffer(deleted), 0, where .. "and neither does a deleted one")

    -- Filetype is the gate: these scanners parse Lua and nothing else, and a
    -- Python buffer full of braces must not be read as a Lua table.
    local other = buffer({ "x = {}" }, "python")
    H.eq(#scanner.scan_buffer(other), 0, where .. "a non-Lua buffer is not scanned")
    vim.api.nvim_buf_delete(other, { force = true })

    local empty = buffer({})
    H.eq(#scanner.scan_buffer(empty), 0, where .. "an empty buffer has no symbols")
    vim.api.nvim_buf_delete(empty, { force = true })

    -- Unparseable source still has a tree (Tree-sitter always produces one),
    -- and the scanner must walk it without raising.
    local broken = buffer({ "local = = = (((", "function" })
    H.ok(pcall(scanner.scan_buffer, broken), where .. "broken source does not raise")
    vim.api.nvim_buf_delete(broken, { force = true })
  end
end
