-- TESTS/imports_langs_contract_spec.lua — the shared `ImportLang` contract,
-- checked once against every registered scanner instead of six near-identical
-- per-language suites.
--
-- The six language modules are the same shape by design (`insights.imports`
-- calls them through one loop and never special-cases a language beyond Lua's
-- Tree-sitter path), so what is worth pinning is the *shape*: that a scanner
-- registered in `langs.registry` can be driven by that loop at all. Where a
-- language genuinely diverges from its neighbours -- Python's multi-line
-- parenthesised form, Go's go.mod lookup, Rust's nested brace expansion, C
-- deciding `external` at scan time -- the divergence is spot-checked in
-- `imports_langs_detail_spec.lua`, which is the only thing a sixth copy of
-- this file would have added.

return function(H)
  local langs = require("insights.imports.langs")

  -- registry / order / tags agree ---------------------------------------------
  H.eq(#langs.order, 6, "six languages are registered")
  for _, id in ipairs(langs.order) do
    H.ok(langs.registry[id], id .. ": listed in order and present in the registry")
    H.ok(langs.tags[id], id .. ": has a display tag for the report")
  end
  local n = 0
  for _ in pairs(langs.registry) do
    n = n + 1
  end
  H.eq(n, #langs.order, "the registry holds nothing `order` does not name")

  -- A source every scanner can be handed -------------------------------------
  -- One import per language, written in that language's plainest form. The
  -- point is not the module name: it is that every scanner accepts a whole
  -- file's text, returns a list, and stamps a line number on each hit.
  local SAMPLES = {
    lua = { src = 'local a = require("pkg.mod")\n', module = "pkg.mod" },
    python = { src = "import pkg.mod\n", module = "pkg.mod" },
    javascript = { src = 'import a from "pkg/mod";\n', module = "pkg/mod" },
    go = { src = 'import "pkg/mod"\n', module = "pkg/mod" },
    rust = { src = "use pkg::mod_;\n", module = "pkg.mod_" },
    c = { src = "#include <pkg/mod.h>\n", module = "pkg/mod.h" },
  }

  for _, id in ipairs(langs.order) do
    local mod = langs.registry[id]
    local where = id .. ": "

    -- Declared metadata --------------------------------------------------
    H.eq(mod.id, id, where .. "id matches its registry key")
    H.ok(type(mod.label) == "string" and mod.label ~= "", where .. "has a label")
    H.ok(type(mod.extensions) == "table" and #mod.extensions > 0, where .. "names its extensions")
    for _, ext in ipairs(mod.extensions) do
      H.ok(type(ext) == "string" and not ext:find("%."), where .. "extensions carry no dot")
    end
    H.ok(
      type(mod.rg_prefilter) == "string" and mod.rg_prefilter ~= "",
      where .. "has an rg prefilter (candidate_files needs one to take the fast path)"
    )

    -- Callable surface ----------------------------------------------------
    H.eq(type(mod.scan_source), "function", where .. "scan_source is callable")
    H.eq(type(mod.is_external), "function", where .. "is_external is callable")

    -- Degenerate inputs ---------------------------------------------------
    H.eq(#mod.scan_source(""), 0, where .. "an empty source yields no imports")
    H.eq(#mod.scan_source("\n\n\n"), 0, where .. "and neither does blank text")

    -- The ordinary form ---------------------------------------------------
    local sample = SAMPLES[id]
    H.ok(sample, where .. "the contract suite knows a sample for this language")
    local hits = mod.scan_source(sample.src)
    H.eq(#hits, 1, where .. "one import in, one occurrence out")
    H.eq(hits[1].module, sample.module, where .. "with the module path the source names")
    H.eq(hits[1].lnum, 1, where .. "and the line it sits on")

    -- Line numbers are real, not always 1 ---------------------------------
    local shifted = mod.scan_source("\n\n" .. sample.src)
    H.eq(#shifted, 1, where .. "the same import two lines down is still found")
    H.eq(shifted[1].lnum, 3, where .. "and reported on line 3")

    -- is_external answers a boolean for any (module, cwd) pair ------------
    local cwd = vim.fs.normalize(vim.fn.getcwd())
    H.eq(
      type(mod.is_external(sample.module, cwd)),
      "boolean",
      where .. "is_external answers true or false, never nil"
    )
  end

  -- Only Lua claims a Tree-sitter path ---------------------------------------
  -- `build_worklist` branches on `lang_mod.id == "lua"` and calls
  -- `ts_available()`/`ts_scan_source` on that one module alone. A second
  -- language growing those functions without the loop learning about them
  -- would be a silently dead code path.
  for _, id in ipairs(langs.order) do
    local mod = langs.registry[id]
    if id == "lua" then
      H.eq(type(mod.ts_available), "function", "lua declares ts_available")
      H.eq(type(mod.ts_scan_source), "function", "lua declares ts_scan_source")
    else
      H.eq(mod.ts_available, nil, id .. ": declares no Tree-sitter entry point")
      H.eq(mod.ts_scan_source, nil, id .. ": and no Tree-sitter scanner")
    end
  end

  -- No two languages claim the same extension --------------------------------
  -- `candidate_files` builds one `--glob *.<ext>` list per language; an
  -- extension in two lists would scan the same file twice and double every
  -- count in the report.
  local owner = {}
  for _, id in ipairs(langs.order) do
    for _, ext in ipairs(langs.registry[id].extensions) do
      H.eq(owner[ext], nil, ("extension %q is claimed by exactly one language"):format(ext))
      owner[ext] = id
    end
  end
end
