-- TESTS/lua_imports_spec.lua — insights.imports.langs.lua: which `require`
-- calls the Lua scanner reports, and which it deliberately does not.

return function(H)
  local lua = require("insights.imports.langs.lua")

  local function modules(src)
    local out = {}
    for _, hit in ipairs(lua.scan_source(src) or {}) do
      out[#out + 1] = hit.module or hit[1] or hit
    end
    return out
  end

  -- The ordinary forms ---------------------------------------------------------
  local basic = modules([[
local a = require("foo.bar")
local b = require 'baz'
require("side.effect")
]])
  H.ok(vim.tbl_contains(basic, "foo.bar"), "double-quoted require is found")
  H.ok(vim.tbl_contains(basic, "baz"), "single-quoted, parenthesis-free too")
  H.ok(vim.tbl_contains(basic, "side.effect"), "and one whose result is discarded")

  -- A dynamic require ---------------------------------------------------------
  -- `require("a." .. kind)` cannot be resolved statically. The scanner sees
  -- only the literal before the concatenation and reports *that*, so a
  -- dynamic require shows up in the report as a module name that does not
  -- exist ("a."). Pinned as it is, not as it arguably should be: this is the
  -- known false-positive class the nvim config's own :DocMap notes describe,
  -- and suppressing it needs a real decision about what a dynamic require
  -- should contribute to an import report -- nothing, or the prefix as a hint.
  local dynamic = modules('local m = require("a." .. kind)')
  H.ok(
    vim.tbl_contains(dynamic, "a."),
    "a concatenated require currently reports its pre-concatenation prefix"
  )

  -- Line numbers ---------------------------------------------------------------
  local hits = lua.scan_source('local x = 1\nlocal y = require("mod")\n')
  H.ok(#hits > 0, "the scan reports something")
  local hit = hits[1]
  if hit.lnum then
    H.eq(hit.lnum, 2, "the reported line is the one the require is on")
  end

  -- Empty input ----------------------------------------------------------------
  H.eq(#(lua.scan_source("") or {}), 0, "an empty source has no imports")
  H.eq(#(lua.scan_source("-- just a comment\n") or {}), 0, "and neither does a comment")

  -- is_external ----------------------------------------------------------------
  -- The distinction that makes the report useful: a module living in this
  -- project is not a dependency, whatever its name looks like.
  local cwd = vim.fs.normalize(vim.fn.getcwd())
  H.falsy(lua.is_external("insights.imports.langs.lua", cwd), "a module in this tree is internal")
  H.ok(lua.is_external("telescope.builtin", cwd), "one that is not, is external")
end
