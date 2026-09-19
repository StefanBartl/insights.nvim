-- TESTS/metrics_init_spec.lua — the metrics entry point: the scan that
-- aggregates per-file stats into folders and totals, the option resolution
-- that turns flags into sections, and the writers.
--
-- The scratch buffer is replaced so the report can be inspected as lines
-- rather than rendered; the PDF writer is driven with and without a stand-in
-- for pdfport.nvim, which is an optional dependency and not installed here.

return function(H)
  local metrics = require("insights.metrics")
  local config = require("insights.config")

  local dir, cleanup = H.fixture("metrics-init")
  local real_scratch = package.loaded["insights.ui.scratch"]
  local real_pdfport = package.loaded["pdfport"]

  ---@param rel string
  ---@param lines string[]
  local function write(rel, lines)
    local path = dir .. "/" .. rel
    vim.fn.mkdir(vim.fs.dirname(path), "p")
    vim.fn.writefile(lines, path)
  end

  write("lua/alpha/one.lua", { "local M = {}", "-- a comment", "return M" })
  write("lua/alpha/two.lua", { "return 1" })
  write("lua/beta/three.lua", { "---@type integer", "local x = 1", "return x" })
  write("lua/beta/@types/init.lua", { "---@meta", "---@class Thing" })
  write("README.md", { "# Readme", "text" })

  local shown
  package.loaded["insights.ui.scratch"] = {
    open = function(lines, title)
      shown = { lines = lines, title = title }
      return 1
    end,
  }

  local ok_body, err_body = pcall(function()
    -- ── normalize_dir ──────────────────────────────────────────────────────
    local normalized = metrics.normalize_dir(dir .. "/")
    H.excludes(normalized, "\\", "the normalised root uses forward slashes")
    H.eq(normalized:sub(-1), "t", "and has no trailing slash")
    H.eq(metrics.normalize_dir(dir), normalized, "with or without one, the answer is the same")

    -- ── scan ───────────────────────────────────────────────────────────────
    local state = metrics.scan(dir, false)
    H.eq(state.root, normalized, "the state records the root it scanned")
    H.eq(state.totals.total_files, 4, "every Lua file is counted, @types included")
    H.ok(state.folder_summary["lua/alpha"], "grouped by folder")
    H.ok(state.folder_summary["lua/beta"], "one entry per folder")
    H.ok(state.folder_summary["lua/beta/@types"], "including the @types folder")
    H.eq(state.folder_summary["lua/alpha"].file_count, 2, "with the files it holds")
    H.eq(#state.folder_summary["lua/alpha"].files, 2, "listed individually")
    H.contains(state.folder_summary["lua/alpha"].files[1].rel, "lua/alpha/", "under relative paths")

    -- Folder aggregates are the sum of their files.
    local alpha = state.folder_summary["lua/alpha"]
    H.eq(
      alpha.total_lines,
      alpha.files[1].stats.total_lines + alpha.files[2].stats.total_lines,
      "a folder's line count is its files' line counts"
    )

    -- `exclude_types` drops @types from the ratio analysis, which is the
    -- whole reason the flag exists: those files are nearly all annotation.
    local excluded = metrics.scan(dir, true)
    H.eq(excluded.totals.total_files, 3, "@types files are excluded when asked")
    H.eq(excluded.folder_summary["lua/beta/@types"], nil, "and their folder disappears with them")

    -- Global averages are the mean of the per-folder ratios.
    H.ok(type(state.global_averages.comment_ratio) == "number", "global averages are computed")
    H.ok(state.global_averages.avg_lines_per_file > 0, "over the folders that were scanned")

    local empty_dir, empty_cleanup = H.fixture("metrics-init-empty")
    local empty = metrics.scan(empty_dir, false)
    H.eq(empty.totals.total_files, 0, "a tree with no Lua files scans to nothing")
    H.eq(
      empty.global_averages.comment_ratio,
      0,
      "and its averages are zero, not a division by zero"
    )
    empty_cleanup()

    -- ── analyze_single ─────────────────────────────────────────────────────
    local single = metrics.analyze_single(dir .. "/lua/alpha/one.lua")
    H.contains(single[1], "=== Single File Statistics ===", "the single-file report is headed")
    H.contains(single[2], "one.lua", "naming the file")
    H.contains(single[3], "Lines: 3", "with its line breakdown")
    H.contains(single[4], "Words:", "and its word breakdown")

    local missing = metrics.analyze_single(dir .. "/nope.lua")
    H.contains(missing[3], "Lines: 0", "an unreadable file reports zeroes rather than failing")

    -- ── write_report ───────────────────────────────────────────────────────
    local ok_w, err_w = metrics.write_report({ "one", "two" }, dir .. "/out/metrics.md")
    H.ok(ok_w, "write_report creates the parent directory and writes")
    H.eq(err_w, nil, "with no error")
    H.eq(H.read(dir .. "/out/metrics.md"), "one\ntwo", "and the lines it was given")

    local ok_n, err_n = metrics.write_report({ "x" }, "")
    H.falsy(ok_n, "an empty path is not an output file")
    H.contains(err_n or "", "no output_file configured", "and says so")

    local ok_b = metrics.write_report({ "x" }, dir .. "/README.md/nested/out.txt")
    H.falsy(ok_b, "an impossible parent directory is reported, not raised")

    -- ── write_report_pdf ───────────────────────────────────────────────────
    package.loaded["pdfport"] = nil
    local pdf_ok, pdf_err
    metrics.write_report_pdf({ "x" }, dir .. "/out.pdf", function(o, e)
      pdf_ok, pdf_err = o, e
    end)
    H.falsy(pdf_ok, "without pdfport.nvim the PDF export declines")
    H.contains(pdf_err or "", "pdfport.nvim not installed", "saying which optional dependency")

    -- Installed, but with no producer available (no pandoc / PDF engine).
    package.loaded["pdfport"] = {
      create = function() end,
      can_create = function()
        return false
      end,
    }
    metrics.write_report_pdf({ "x" }, dir .. "/out.pdf", function(o, e)
      pdf_ok, pdf_err = o, e
    end)
    H.falsy(pdf_ok, "an installed pdfport with no producer also declines")
    H.contains(pdf_err or "", "no available text producer", "with the other reason")

    -- Installed and able: the lines go over as text, byte-for-byte what
    -- write_report would have written.
    local handed
    package.loaded["pdfport"] = {
      can_create = function(kind)
        return kind == "text"
      end,
      create = function(opts)
        handed = opts
        opts.__callback({ status = "ok" })
      end,
    }
    metrics.write_report_pdf({ "one", "two" }, dir .. "/out.pdf", function(o, e)
      pdf_ok, pdf_err = o, e
    end)
    H.ok(pdf_ok, "a working pdfport reports success")
    H.eq(pdf_err, nil, "with no error")
    H.eq(handed.text, "one\ntwo", "handing over the same lines")
    H.eq(handed.from, "text", "as text")
    H.eq(handed.on_conflict, "overwrite", "overwriting an existing file")

    package.loaded["pdfport"].create = function(opts)
      opts.__callback({ status = "error", error = "pandoc blew up" })
    end
    metrics.write_report_pdf({ "x" }, dir .. "/out.pdf", function(o, e)
      pdf_ok, pdf_err = o, e
    end)
    H.falsy(pdf_ok, "a failing export is reported")
    H.eq(pdf_err, "pandoc blew up", "with pdfport's own message")
    package.loaded["pdfport"] = nil

    -- ── run ────────────────────────────────────────────────────────────────
    config.setup({ metrics = { output_file = "" } })

    shown = nil
    metrics.run(dir)
    H.ok(shown, "run(<dir>) opens a report")
    H.contains(shown.title, "Metrics", "titled for the feature")
    H.contains(shown.lines[1], "=== Project File Statistics Report ===", "with the report header")
    H.contains(shown.lines[2], "Root: ", "naming the root")
    local text = table.concat(shown.lines, "\n")
    H.contains(text, "Lua files analyzed:", "the Lua section is present")
    H.contains(text, "=== Folder Ratios ===", "with ratios")
    H.contains(text, "=== Folder Summary ===", "folder tables")
    H.contains(text, "=== File Statistics ===", "file tables")
    H.contains(text, "=== Total Summary ===", "a total row")
    H.contains(text, "=== Top 50 Files by Lines ===", "the top-N lists")
    H.contains(text, "Documentation & Config Files", "and the misc section")

    -- A string argument is the root; nil is the working directory.
    shown = nil
    metrics.run({ root = dir, show_ratios = false, show_top_lists = false, analyze_misc = false })
    local trimmed = table.concat(shown.lines, "\n")
    H.excludes(trimmed, "=== Folder Ratios ===", "show_ratios = false drops the ratio section")
    H.excludes(trimmed, "Top 50 Files", "show_top_lists = false drops the top-N lists")
    H.excludes(trimmed, "Documentation & Config", "analyze_misc = false drops the misc section")
    H.contains(trimmed, "=== Folder Summary ===", "while the rest survives")

    -- `reverse_order` decides whether the summary or the per-file table comes
    -- first; both orders must contain the same sections.
    shown = nil
    metrics.run({ root = dir, reverse_order = false, analyze_misc = false })
    local forward = shown.lines
    local function line_of(lines, needle)
      for i, l in ipairs(lines) do
        if l:find(needle, 1, true) then
          return i
        end
      end
    end
    H.ok(
      line_of(forward, "=== File Statistics ===") < line_of(forward, "=== Total Summary ==="),
      "with reverse_order off, the file table comes before the summary"
    )
    shown = nil
    metrics.run({ root = dir, reverse_order = true, analyze_misc = false })
    H.ok(
      line_of(shown.lines, "=== Total Summary ===")
        < line_of(shown.lines, "=== File Statistics ==="),
      "and with it on, the summary comes first"
    )

    -- Top-only mode emits just the requested list.
    shown = nil
    metrics.run({ root = dir, only_top_lines = true })
    local top_only = table.concat(shown.lines, "\n")
    H.contains(top_only, "Top 50 Files by Lines", "only_top_lines emits that list")
    H.excludes(top_only, "Top 50 Files by Words", "and not the other one")
    H.excludes(top_only, "=== Folder Summary ===", "nor any of the tables")

    shown = nil
    metrics.run({ root = dir, only_top_words = true })
    H.contains(table.concat(shown.lines, "\n"), "Top 50 Files by Words", "only_top_words the other")

    -- `--misc-only`: no Lua analysis at all.
    shown = nil
    metrics.run({ root = dir, analyze_lua = false, analyze_misc = true })
    local misc_only = table.concat(shown.lines, "\n")
    H.contains(misc_only, "Documentation & Config Files", "misc-only keeps the misc section")
    H.excludes(misc_only, "Lua files analyzed:", "and drops the Lua one")

    -- A mistyped col_width/top_n (a scalar leaf, so config.setup() lets it
    -- through with no warning) must degrade to its default rather than crash
    -- report.lua's string.format/string.rep arithmetic (ERR-22).
    config.setup({ metrics = { col_width = "wide", top_n = "many" } })
    shown = nil
    metrics.run({ root = dir })
    H.ok(shown, "a wrong-type col_width/top_n does not crash the report")
    H.contains(
      table.concat(shown.lines, "\n"),
      "Top 50 Files by Lines",
      "and top_n falls back to its default of 50"
    )
    config.setup({})

    -- `single_file` short-circuits everything else.
    shown = nil
    metrics.run({ single_file = dir .. "/lua/alpha/one.lua" })
    H.contains(shown.lines[1], "=== Single File Statistics ===", "single_file reports one file")
    H.contains(shown.title, "one.lua", "and is titled with it")

    -- A root that is not a directory is refused before anything is scanned.
    shown = nil
    metrics.run({ root = dir .. "/README.md" })
    H.eq(shown, nil, "a non-directory root opens nothing")

    -- A directory with neither Lua nor documentation files is refused too.
    local bare, bare_cleanup = H.fixture("metrics-init-bare")
    shown = nil
    metrics.run({ root = bare })
    H.eq(shown, nil, "an empty directory opens nothing")
    bare_cleanup()

    -- A tree with only documentation still reports, with a warning line where
    -- the Lua section would have been.
    local docs_only, docs_cleanup = H.fixture("metrics-init-docs")
    vim.fn.writefile({ "# only prose" }, docs_only .. "/NOTES.md")
    shown = nil
    metrics.run({ root = docs_only })
    H.ok(shown, "a documentation-only tree still reports")
    H.contains(
      table.concat(shown.lines, "\n"),
      "Warning: no Lua files found.",
      "saying that there was no Lua to analyse"
    )
    docs_cleanup()

    -- An `output_file` is written as a side effect of presenting.
    config.setup({ metrics = { output_file = dir .. "/out/report.md" } })
    shown = nil
    metrics.run({ root = dir })
    H.ok(shown, "the report still opens with an output file configured")
    H.contains(H.read(dir .. "/out/report.md"), "Project File Statistics", "and is written to disk")

    -- A `.pdf` output goes through the PDF writer instead, which declines
    -- without pdfport -- and the report still opens either way.
    config.setup({ metrics = { output_file = dir .. "/out/report.pdf" } })
    shown = nil
    metrics.run({ root = dir })
    H.ok(shown, "a .pdf output file does not stop the report from opening")
    H.eq(vim.fn.filereadable(dir .. "/out/report.pdf"), 0, "and no PDF is produced without pdfport")
  end)

  package.loaded["insights.ui.scratch"] = real_scratch
  package.loaded["pdfport"] = real_pdfport
  config.setup({})
  cleanup()

  if not ok_body then
    error(err_body, 0)
  end
end
