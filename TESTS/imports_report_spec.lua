-- TESTS/imports_report_spec.lua — `insights.imports` itself: the cwd scan,
-- the filter language, and the four reports built on top of them.
--
-- **No ripgrep runs here.** `candidate_files` takes the `rg
-- --files-with-matches` prefilter whenever ripgrep is on PATH, which would
-- make this suite spawn a process per language and depend on what is
-- installed. `vim.fn.executable` is replaced for the duration so the glob
-- path is taken instead -- the same file list, found without a subprocess,
-- and the branch CI takes on a machine without ripgrep anyway.
--
-- The scan reads the working directory, so the suite changes into a fixture
-- tree and changes back. Everything it asserts about counts and file names is
-- therefore about the fixture, not about whichever repository the suite
-- happens to be run from.

return function(H)
  local imports = require("insights.imports")
  local index = require("insights.imports.index")
  local config = require("insights.config")

  local dir, cleanup = H.fixture("imports-report")
  local original_cwd = vim.fn.getcwd()
  local real_executable = vim.fn.executable
  local real_scratch = package.loaded["insights.ui.scratch"]
  local real_fzf = package.loaded["insights.ui.fzf"]
  local real_telescope = package.loaded["insights.ui.telescope"]

  ---@param rel string
  ---@param lines string[]
  local function write(rel, lines)
    local path = dir .. "/" .. rel
    vim.fn.mkdir(vim.fs.dirname(path), "p")
    vim.fn.writefile(lines, path)
  end

  -- Two Lua files and a Python one. `alpha.lua` imports the project's own
  -- `proj.beta` (internal) and an external module; `beta.lua` imports the
  -- same external one, so it has a count of two.
  write("lua/proj/alpha.lua", {
    'local beta = require("proj.beta")',
    'local ext = require("vendor.thing")',
    "return beta.go(ext)",
  })
  write("lua/proj/beta.lua", {
    'local ext = require("vendor.thing")',
    'local dead = require("vendor.unused")',
    "return { ext = ext }",
  })
  write("script.py", { "import os", "from vendor import thing" })

  -- The captured UI: `present` hands the finished report to one of these.
  local shown = {}
  package.loaded["insights.ui.scratch"] = {
    open = function(lines, title, opts)
      shown = { lines = lines, title = title, opts = opts }
      return 1
    end,
  }
  package.loaded["insights.ui.fzf"] = {
    open = function(entries, title)
      shown = { picker = "fzf", entries = entries, title = title }
    end,
  }
  package.loaded["insights.ui.telescope"] = {
    open = function(entries, title)
      shown = { picker = "telescope", entries = entries, title = title }
    end,
  }

  vim.fn.executable = function(_)
    return 0
  end
  vim.fn.chdir(dir)

  local ok_body, err_body = pcall(function()
    config.setup({
      imports = {
        output_file = "",
        groups = { vendor = { "vendor" }, both = { "proj", "vendor" } },
      },
    })

    -- ── the scan ───────────────────────────────────────────────────────────
    index.forget()
    local data = imports.scan_cwd()

    H.eq(type(data.entries), "table", "a scan answers entries")
    H.eq(#data.entries, 6, "one per import in the fixture (4 Lua, 2 Python)")
    H.eq(data.lang_totals.lua, 4, "counted per language")
    H.eq(data.lang_totals.python, 2, "for each language that found something")
    H.eq(data.lang_totals.go, nil, "and not for the ones that found nothing")
    H.ok(
      data.methods.lua == "treesitter" or data.methods.lua == "ripgrep",
      "the Lua backend is named"
    )
    H.eq(data.methods.python, "regex", "and every other language reports regex")

    -- Composite keys keep same-named modules in different languages apart.
    H.eq(data.counts["lua\1vendor.thing"], 2, "the shared external is imported twice")
    H.eq(data.externals["lua\1proj.beta"], false, "a module with a file in the tree is internal")
    H.eq(data.externals["lua\1vendor.thing"], true, "one without is external")

    -- The scan leaves its result behind for the passive consumers.
    local remembered = index.get()
    H.ok(remembered, "a scan populates the remembered index")
    H.eq(#remembered.data.entries, #data.entries, "with the data it just built")
    H.eq(remembered.stale, false, "fresh")

    -- Ignored directories -------------------------------------------------
    write("node_modules/pkg/ignored.lua", { 'require("should.not.appear")' })
    write(".git/hooks/ignored.lua", { 'require("nor.this")' })
    local after_noise = imports.scan_cwd()
    H.eq(#after_noise.entries, 6, "node_modules and .git are not scanned")

    -- ── scan_cwd_async ─────────────────────────────────────────────────────
    local async_data
    imports.scan_cwd_async(function(d)
      async_data = d
    end)
    H.ok(
      vim.wait(5000, function()
        return async_data ~= nil
      end),
      "the async scan completes"
    )
    H.eq(#async_data.entries, #data.entries, "and finds the same imports as the sync one")

    -- ── filtered_entries ───────────────────────────────────────────────────
    ---@param filters string[]
    ---@return string[]
    local function modules_for(filters)
      local out = {}
      for _, entry in ipairs(imports.filtered_entries(data, filters)) do
        out[#out + 1] = entry.lang .. ":" .. entry.module
      end
      return out
    end

    H.eq(#imports.filtered_entries(data, {}), 6, "no filter selects everything")
    H.eq(#imports.filtered_entries(data, nil), 6, "and so does no filter at all")

    -- Sorted by language, then module, then file, then line -- the order the
    -- report and the picker both present.
    local all = imports.filtered_entries(data, {})
    H.eq(all[1].lang, "lua", "lua sorts before python")
    H.eq(all[1].module, "proj.beta", "and the modules within a language sort by name")
    H.eq(all[#all].lang, "python", "python comes last")

    -- A language id, and its aliases.
    H.eq(#imports.filtered_entries(data, { "python" }), 2, "a language id scopes the report")
    H.eq(#imports.filtered_entries(data, { "py" }), 2, "and so does its alias")
    H.eq(#imports.filtered_entries(data, { "lua" }), 4, "each language on its own")

    -- A configured group expands to its prefixes.
    H.eq(#imports.filtered_entries(data, { "vendor" }), 4, "a group name expands to its prefixes")
    H.eq(#imports.filtered_entries(data, { "both" }), 5, "a group may hold several")

    -- A literal prefix that is not a group, and the boundary rule: `proj`
    -- matches `proj.beta` but a longer word starting with the same letters
    -- does not.
    H.eq(#imports.filtered_entries(data, { "proj" }), 1, "a bare prefix matches on a dot boundary")
    H.eq(#imports.filtered_entries(data, { "pro" }), 0, "a partial segment is not a prefix match")
    H.eq(#imports.filtered_entries(data, { "proj.beta" }), 1, "an exact module name matches itself")

    -- Language and prefix filters combine (AND), not replace each other.
    H.eq(
      #imports.filtered_entries(data, { "lua", "vendor" }),
      3,
      "a language and a prefix filter apply together"
    )
    H.eq(
      #imports.filtered_entries(data, { "python", "vendor" }),
      1,
      "the python side of the same pair"
    )

    local combined = modules_for({ "lua", "vendor" })
    H.eq(combined[1], "lua:vendor.thing", "with only the selected language's entries")

    -- ── build_report ───────────────────────────────────────────────────────
    local lines, line_index = imports.build_report(data, {})
    local text = table.concat(lines, "\n")

    H.contains(lines[1], "=== Imports", "the report is headed")
    H.contains(lines[1], vim.fn.fnamemodify(dir, ":t"), "with the project name")
    H.contains(lines[2], "total import/require calls : 6", "and the totals")
    H.contains(lines[2], "unique modules : 5", "including the distinct module count")
    H.contains(text, "--- Count ---", "there is a count section")
    H.contains(text, "--- Occurrences ---", "and an occurrence section")
    H.contains(text, "(extern)", "external modules are tagged")
    H.contains(text, "Lua", "each language that found something gets a line")
    H.contains(text, "Python", "including python")

    -- The line index is what "go to definition" reads: every count and
    -- occurrence line must be reachable, and nothing else.
    local indexed = 0
    for lnum, entry in pairs(line_index) do
      indexed = indexed + 1
      H.ok(type(entry.module) == "string", "line " .. lnum .. " names a module")
      H.ok(type(entry.lang) == "string", "and a language")
      H.contains(lines[lnum], entry.module, "and the line really shows that module")
    end
    H.eq(indexed, 11, "5 count lines plus 6 occurrence lines are indexed")
    H.eq(line_index[1], nil, "the header is not an import")
    H.eq(line_index[2], nil, "nor the totals line")
    for lnum, line in ipairs(lines) do
      if line == "--- Count ---" or line == "--- Occurrences ---" or line == "" then
        H.eq(line_index[lnum], nil, "a section heading or blank line is not an import")
      end
    end

    -- A filter is named in the title, so a saved report says what it is.
    local filtered_lines = imports.build_report(data, { "vendor" })
    H.contains(filtered_lines[1], "[filter: vendor]", "a filtered report says so in its header")

    -- Nothing matching is a sentence, not an empty file.
    local nothing = imports.build_report(data, { "matches.nothing" })
    H.contains(
      table.concat(nothing, "\n"),
      "(no matching import/require calls)",
      "an empty selection says so"
    )

    -- format_report is the compatibility wrapper: same lines, no index.
    H.eq(
      table.concat(imports.format_report(data, {}), "\n"),
      text,
      "format_report returns the lines"
    )

    -- ── build_reverse_report ───────────────────────────────────────────────
    local reverse = imports.build_reverse_report(data, "vendor.thing")
    H.contains(reverse[1], "Reverse: vendor.thing", "the reverse report names its query")
    H.contains(reverse[2], "2 occurrence(s) across 2 file(s)", "and counts files and occurrences")
    H.contains(table.concat(reverse, "\n"), "alpha.lua", "listing each importing file")
    H.contains(table.concat(reverse, "\n"), "beta.lua", "all of them")

    local reverse_none = imports.build_reverse_report(data, "nobody.imports.this")
    H.contains(
      table.concat(reverse_none, "\n"),
      "(no file imports 'nobody.imports.this')",
      "and says so when nothing does"
    )

    -- ── build_unused_report ────────────────────────────────────────────────
    -- `vendor.unused` is bound to `dead` in beta.lua and never mentioned
    -- again; every other binding is used.
    local unused = imports.build_unused_report(data, {})
    local unused_text = table.concat(unused, "\n")
    -- `dead` in beta.lua, and python's `thing`, which `script.py` binds and
    -- never mentions again.
    H.contains(unused[2], "possibly-unused imports : 2", "two bindings are never referenced again")
    H.contains(unused_text, "vendor.unused", "the dead Lua binding is named")
    H.contains(unused_text, "script.py", "and the dead Python one")
    H.excludes(unused_text, "vendor.thing", "a used binding is not flagged")
    H.excludes(unused_text, "proj.beta", "nor another one")
    -- A binding named `_` or `*` is never flagged: it says outright that the
    -- value is not meant to be used again.
    H.contains(
      table.concat(
        imports.build_unused_report({
          entries = {
            {
              module = "x",
              name = "_",
              filename = "script.py",
              lnum = 1,
              lang = "lua",
              external = true,
            },
          },
          counts = {},
          externals = {},
          lang_totals = {},
          methods = {},
        }, {}),
        "\n"
      ),
      "(none found)",
      "a binding named _ is never reported as unused"
    )

    -- The synchronous form also calls the callback when one is given.
    local cb_lines
    imports.build_unused_report(data, {}, function(l)
      cb_lines = l
    end)
    H.ok(cb_lines, "a callback is honoured even on the small, synchronous path")
    H.eq(table.concat(cb_lines, "\n"), unused_text, "with the same report")

    local unused_filtered = imports.build_unused_report(data, { "proj" })
    H.contains(
      table.concat(unused_filtered, "\n"),
      "(none found)",
      "a filter that excludes the dead import finds nothing"
    )
    H.contains(unused_filtered[1], "[filter: proj]", "and the filter is in the header")

    -- ── write_report ───────────────────────────────────────────────────────
    local ok_w, err_w = imports.write_report({ "one", "two" }, dir .. "/out/report.txt")
    H.ok(ok_w, "write_report creates the parent directory and writes")
    H.eq(err_w, nil, "with no error")
    H.eq(H.read(dir .. "/out/report.txt"), "one\ntwo", "and the lines it was given")

    local ok_n, err_n = imports.write_report({ "x" }, "")
    H.falsy(ok_n, "an empty path is not an output file")
    H.contains(err_n or "", "no output_file configured", "and says so")

    -- A path whose parent is an existing *file* cannot be a directory.
    local ok_b, err_b = imports.write_report({ "x" }, dir .. "/script.py/nested/report.txt")
    H.falsy(ok_b, "an impossible parent directory is reported, not raised")
    H.ok(type(err_b) == "string", "as an error string")

    -- ── run / run_reverse / run_unused ─────────────────────────────────────
    shown = {}
    imports.run({})
    H.ok(
      vim.wait(5000, function()
        return shown.lines ~= nil
      end),
      "run() opens the report when the scan finishes"
    )
    H.contains(shown.title or "", "Imports", "in a scratch buffer titled for the feature")
    H.contains(shown.lines[1], "=== Imports", "with the report lines")
    H.ok(#(shown.opts.keymaps or {}) == 2, "and the jump/preview keymaps attached")
    H.eq(shown.opts.keymaps[1][2], "gd", "gd reveals the definition")
    H.eq(shown.opts.keymaps[2][2], "gp", "gp previews it")

    -- `definition.keymaps.jump = false` removes just that one.
    config.setup({
      imports = {
        output_file = "",
        definition = { keymaps = { jump = false } },
      },
    })
    shown = {}
    imports.run({})
    H.ok(
      vim.wait(5000, function()
        return shown.lines ~= nil
      end),
      "run() still opens with a mapping disabled"
    )
    H.eq(#shown.opts.keymaps, 1, "one keymap instead of two")
    H.eq(shown.opts.keymaps[1][2], "gp", "the preview one")
    config.setup({ imports = { output_file = "" } })

    -- The picker views hand the occurrence list to the UI adapter instead.
    shown = {}
    imports.run({ "lua" }, "fzf")
    H.ok(
      vim.wait(5000, function()
        return shown.picker ~= nil
      end),
      "run(filters, 'fzf') opens the fzf adapter"
    )
    H.eq(shown.picker, "fzf", "the fzf one")
    H.eq(#shown.entries, 4, "with the filtered occurrences")
    H.eq(shown.entries[1].func_type, "lua", "mapped onto the picker entry shape")
    H.ok(shown.entries[1].filename and shown.entries[1].lnum, "with a file and a line to jump to")

    shown = {}
    imports.run({}, "telescope")
    H.ok(
      vim.wait(5000, function()
        return shown.picker ~= nil
      end),
      "and 'telescope' opens the telescope adapter"
    )
    H.eq(shown.picker, "telescope", "that one")

    -- An `output_file` is written as a side effect of presenting.
    config.setup({ imports = { output_file = dir .. "/out/imports.md" } })
    shown = {}
    imports.run({})
    H.ok(
      vim.wait(5000, function()
        return shown.lines ~= nil
      end),
      "run() completes with an output file configured"
    )
    H.contains(H.read(dir .. "/out/imports.md"), "=== Imports", "and the report is on disk")
    config.setup({ imports = { output_file = "" } })

    -- output_file is a scalar leaf, so config.setup() never validates it --
    -- a wrong-type value (e.g. `output_file = true`, surviving setup())
    -- must degrade to "no file written" rather than crash write_report()'s
    -- io.open() call, which -- unlike metrics.lua's sibling present() -- is
    -- not pcall-wrapped here (ERR-22).
    ---@diagnostic disable-next-line: assign-type-mismatch
    config.setup({ imports = { output_file = true } })
    shown = {}
    local ok_bad_type = pcall(imports.run, {})
    H.ok(ok_bad_type, "a wrong-type output_file does not crash run()")
    H.ok(
      vim.wait(5000, function()
        return shown.lines ~= nil
      end),
      "and the report still opens"
    )
    config.setup({ imports = { output_file = "" } })

    -- run_reverse: a warm index answers without scanning again.
    imports.scan_cwd()
    shown = {}
    imports.run_reverse("vendor.thing")
    H.ok(shown.lines, "a warm index answers the reverse report synchronously")
    H.contains(shown.title or "", "vendor.thing", "titled with the module")

    -- A cold index makes it scan; the answer arrives through the callback.
    index.forget()
    shown = {}
    imports.run_reverse("vendor.thing")
    H.ok(
      vim.wait(5000, function()
        return shown.lines ~= nil
      end),
      "a cold index scans first, then answers"
    )
    H.contains(table.concat(shown.lines, "\n"), "2 occurrence(s)", "with the same numbers")

    shown = {}
    imports.run_reverse("")
    H.eq(shown.lines, nil, "an empty query opens nothing")

    shown = {}
    imports.run_unused({})
    H.ok(
      vim.wait(5000, function()
        return shown.lines ~= nil
      end),
      "run_unused opens the unused report"
    )
    H.eq(shown.title, "Imports Unused", "under its own title")
    H.contains(table.concat(shown.lines, "\n"), "vendor.unused", "naming the dead binding")

    -- ── reverse_lookup's tie to the index ──────────────────────────────────
    imports.scan_cwd()
    local hit = imports.reverse_lookup("vendor.thing")
    H.ok(hit, "reverse_lookup answers from the index a scan left")
    H.eq(#hit.files, 2, "with the importing files")
    H.eq(hit.stale, false, "and the freshness flag")

    -- A language that found nothing is not in the report at all -------------
    config.setup({ imports = { output_file = "", languages = { python = false } } })
    local lua_only = imports.scan_cwd()
    H.eq(lua_only.lang_totals.python, nil, "a disabled language is never scanned")
    H.eq(lua_only.lang_totals.lua, 4, "while the others still are")
  end)

  vim.fn.executable = real_executable
  vim.fn.chdir(original_cwd)
  package.loaded["insights.ui.scratch"] = real_scratch
  package.loaded["insights.ui.fzf"] = real_fzf
  package.loaded["insights.ui.telescope"] = real_telescope
  config.setup({})
  index.forget()
  cleanup()

  if not ok_body then
    error(err_body, 0)
  end
end
