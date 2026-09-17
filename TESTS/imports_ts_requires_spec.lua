-- TESTS/imports_ts_requires_spec.lua — the AST-accurate Lua require scanner.
--
-- This is the backend `imports.engine = "auto"` picks whenever the Lua parser
-- is there, so it is what most users' reports are actually built from. The
-- regex fallback has its own suite (`lua_imports_spec.lua`); what is pinned
-- here is the difference between the two -- a `require` written in a comment
-- or inside a string is not a require -- plus the two things the AST is used
-- for beyond finding the call: the bound name and the trailing field.
--
-- The query's node names are the part worth guarding. A Tree-sitter query
-- that names a node the grammar no longer has does not fail loudly: it fails
-- to parse, `scan_tree` returns `{}`, and the report simply says there are no
-- imports. Every assertion below that expects a non-empty result is therefore
-- also a check that `function_call`/`identifier`/`arguments`/`string` are
-- still the right names. Verified against Neovim 0.12.2's bundled
-- tree-sitter-lua on 2026-09-17.

return function(H)
  local ts_requires = require("insights.imports.ts_requires")

  -- Without the Lua parser there is nothing to test and nothing to report;
  -- `imports/init.lua` falls back to ripgrep in exactly this case.
  if not ts_requires.available() then
    print("      (skipped: the Lua Tree-sitter parser is unavailable here)")
    return
  end

  ---@param src string
  ---@return table<string, table>
  local function by_module(src)
    local out = {}
    for _, hit in ipairs(ts_requires.scan_source(src)) do
      out[hit.module] = out[hit.module] or hit
    end
    return out
  end

  -- The forms ----------------------------------------------------------------
  local seen = by_module(table.concat({
    'local bound = require("pkg.bound")',
    'require("pkg.bare")',
    'local field = require("pkg.field").create',
    'local chained = require("pkg.chained").make()',
    "local a, b = 1, require('pkg.second')",
    'M.assigned = require("pkg.assigned")',
    "local long = require([[pkg.long]])",
  }, "\n"))

  H.eq(seen["pkg.bound"].name, "bound", "a local binding is reported as the bound name")
  H.eq(seen["pkg.bound"].field, nil, "with no field when nothing is accessed")
  H.eq(seen["pkg.bare"].name, nil, "a bare require binds nothing")
  H.eq(seen["pkg.field"].name, "field", "a trailing field does not hide the binding")
  H.eq(seen["pkg.field"].field, "create", "and the field itself is recorded")
  H.eq(seen["pkg.chained"].field, "make", "a called field is still a field")
  H.eq(seen["pkg.second"].name, "b", "multiple assignment aligns names by index")
  H.eq(seen["pkg.assigned"].name, "M.assigned", "a dotted assignment target is the name")
  H.eq(seen["pkg.long"].module, "pkg.long", "a long-bracket string literal is unquoted")

  -- Line numbers -------------------------------------------------------------
  local lines = ts_requires.scan_source('local x = 1\n\nlocal y = require("pkg.third")\n')
  H.eq(#lines, 1, "one require, one hit")
  H.eq(lines[1].lnum, 3, "reported on the line the call is written on")

  -- The whole point of the AST backend --------------------------------------
  -- The regex scanner reports both of these; this one reports neither,
  -- because neither is a call.
  local quiet = ts_requires.scan_source(table.concat({
    '-- see require("not.a.call") in the docs',
    'local s = "require(\\"also.not.a.call\\")"',
    "local t = [[require('nor.this')]]",
  }, "\n"))
  H.eq(#quiet, 0, "a require named in a comment or a string is not an import")

  -- Guards -------------------------------------------------------------------
  H.eq(#ts_requires.scan_source(""), 0, "an empty source has no requires")
  H.eq(
    #ts_requires.scan_source("local = = = broken"),
    0,
    "unparseable source yields nothing rather than raising"
  )
  -- `require()` with no argument, and with a non-literal one: neither gives a
  -- module name, and inventing one would put a module that does not exist in
  -- the report.
  H.eq(#ts_requires.scan_source("require()\n"), 0, "a require with no argument is skipped")
  H.eq(#ts_requires.scan_source("require(name)\n"), 0, "and one with a variable argument")
  -- A same-named local function is not the global `require`; the callee text
  -- is compared to "require" exactly.
  H.eq(#ts_requires.scan_source('other("pkg.x")\n'), 0, "a different callee is not a require")

  -- scan_buffer --------------------------------------------------------------
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    'local cfg = require("pkg.from.buffer")',
    'require("pkg.side").init()',
  })
  vim.bo[buf].filetype = "lua"
  local from_buf = ts_requires.scan_buffer(buf)
  H.eq(#from_buf, 2, "a buffer scan finds both calls")
  H.eq(from_buf[1].module, "pkg.from.buffer", "with the same module names")
  H.eq(from_buf[1].name, "cfg", "and the same bindings")
  H.eq(from_buf[2].field, "init", "and the same fields")

  vim.api.nvim_buf_delete(buf, { force = true })
  H.eq(#ts_requires.scan_buffer(buf), 0, "a deleted buffer scans to nothing")
  H.eq(#ts_requires.scan_buffer(999999), 0, "and so does a buffer that never existed")

  -- The registry's Lua entry delegates here ---------------------------------
  local lua_mod = require("insights.imports.langs.lua")
  H.eq(lua_mod.ts_available(), true, "langs.lua reports the parser as available")
  H.eq(
    lua_mod.ts_scan_source('local d = require("pkg.delegated")')[1].module,
    "pkg.delegated",
    "and ts_scan_source goes through this module"
  )
end
