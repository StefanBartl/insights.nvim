-- TESTS/imports_graph_spec.lua — the Graphviz view of the import data.
--
-- `build_dot` is a pure function on entries the scan already produced, and it
-- is where every decision that makes the picture readable lives: which nodes
-- exist, which edges survive de-duplication, and the sort that keeps two runs
-- over the same project byte-identical. `render` and `show` need `dot` on
-- PATH; only the branches that decide *not* to run it are exercised here --
-- a headless suite must not spawn a layout engine, and on a machine without
-- Graphviz there would be nothing to spawn anyway.

return function(H)
  local graph = require("insights.imports.graph")

  ---@param filename string
  ---@param module string
  ---@param external boolean
  ---@return table
  local function e(filename, module, external)
    return {
      filename = filename,
      module = module,
      external = external,
      name = "x",
      lnum = 1,
      lang = "lua",
    }
  end

  local entries = {
    e("b.lua", "proj.beta", false),
    e("a.lua", "proj.alpha", false),
    e("a.lua", "proj.alpha", false), -- the same edge, twice
    e("a.lua", "proj.beta", false),
    e("a.lua", "vendor.lib", true),
  }

  -- Default: internal modules only ------------------------------------------
  local dot = graph.build_dot(entries)

  H.contains(dot, "digraph imports {", "a digraph is emitted")
  H.contains(dot, 'rankdir="LR";', "laid out left to right")
  H.eq(dot:sub(-1), "}", "and closed")

  H.contains(dot, '"a.lua" -> "proj.alpha";', "an import is an edge from file to module")
  H.contains(dot, '"a.lua" -> "proj.beta";', "one edge per distinct pair")
  H.contains(dot, '"b.lua" -> "proj.beta";', "from every importing file")
  H.excludes(dot, "vendor.lib", "an external module is left out by default")

  -- De-duplication: two occurrences of the same import are one edge.
  local _, edge_count = dot:gsub('"a%.lua" %-> "proj%.alpha";', "")
  H.eq(edge_count, 1, "a repeated import does not repeat its edge")

  -- Deterministic order ------------------------------------------------------
  -- Two scans of an unchanged project must produce the same file, or every
  -- re-render looks like a change.
  H.eq(dot, graph.build_dot(entries), "the same entries build the same source")
  local shuffled = { entries[5], entries[3], entries[1], entries[4], entries[2] }
  H.eq(dot, graph.build_dot(shuffled), "and so do the same entries in a different order")

  -- Nodes --------------------------------------------------------------------
  H.contains(dot, '"a.lua" [style=filled', "importing files get a filled node")
  H.contains(dot, '"b.lua" [style=filled', "each of them")
  -- Internal target modules are plain nodes: only external ones are marked,
  -- and they are excluded here, so no dashed style should appear at all.
  H.excludes(dot, "dashed", "with nothing dashed while externals are excluded")

  -- include_external ---------------------------------------------------------
  local wide = graph.build_dot(entries, { include_external = true })
  H.contains(wide, '"a.lua" -> "vendor.lib";', "external imports become edges when asked for")
  H.contains(wide, '"vendor.lib" [style="filled,dashed"', "and their nodes are marked dashed")
  H.excludes(wide, '"proj.alpha" [style="filled,dashed"', "internal targets are not")

  -- `include_external` is compared to `true`, so anything else is "no".
  H.eq(graph.build_dot(entries, { include_external = false }), dot, "false is the default")
  H.eq(graph.build_dot(entries, {}), dot, "and so is an empty options table")

  -- An entry whose `external` was never classified counts as internal --------
  local unclassified = graph.build_dot({ e("c.lua", "proj.gamma", nil) })
  H.contains(unclassified, '"c.lua" -> "proj.gamma";', "a nil `external` is treated as internal")

  -- Quoting ------------------------------------------------------------------
  -- A Windows path or a module name with a quote in it must not be able to
  -- close the DOT string early; the file would stop being valid Graphviz.
  local quoted = graph.build_dot({ e([[dir\sub\file.lua]], [[weird"name]], false) })
  H.contains(quoted, [["dir\\sub\\file.lua"]], "a backslash is escaped")
  H.contains(quoted, [["weird\"name"]], "and so is a quote")

  -- Nothing in, something valid out -----------------------------------------
  local empty = graph.build_dot({})
  H.contains(empty, "digraph imports {", "an empty entry list is still a graph")
  H.excludes(empty, "->", "with no edges")

  -- available ----------------------------------------------------------------
  H.eq(type(graph.available()), "boolean", "availability is a yes/no answer")
  H.eq(graph.available("dot"), graph.available(), '"dot" is the default layout')
  H.falsy(
    graph.available("insights-no-such-layout-engine"),
    "a layout engine that is not installed is not available"
  )

  -- render, without a layout engine -----------------------------------------
  -- The failure arrives through the callback, not as a raised error: `show`
  -- is what turns it into a notification, and it cannot do that if `render`
  -- throws first.
  local out_png, err
  local called = false
  graph.render(
    "digraph {}",
    "/tmp/insights-never-written.png",
    "insights-no-such-layout",
    function(p, e_)
      called, out_png, err = true, p, e_
    end
  )
  H.ok(called, "render answers synchronously when there is no layout engine")
  H.eq(out_png, nil, "with no PNG")
  H.contains(err or "", "not found", "and an error naming the missing engine")
  H.contains(err or "", "insights-no-such-layout", "specifically")

  -- show, without a layout engine -------------------------------------------
  -- The same guard one level up: `show` returns false rather than starting a
  -- render, and says so through notify.
  local config = require("insights.config")
  config.setup({ imports = { graph = { layout = "insights-no-such-layout" } } })
  H.falsy(
    graph.show({ entries = entries, counts = {}, externals = {}, lang_totals = {}, methods = {} }),
    "show declines when Graphviz is not installed"
  )

  -- ...and when the filters match nothing, which it can tell before layout.
  if graph.available("dot") then
    config.setup({ imports = { graph = { layout = "dot" } } })
    H.falsy(
      graph.show({
        entries = entries,
        counts = {},
        externals = {},
        lang_totals = {},
        methods = {},
      }, { "matches.nothing.at.all" }),
      "show declines when the filters select no imports"
    )
  end

  config.setup({})
end
