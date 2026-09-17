-- TESTS/metrics_report_spec.lua — the ASCII table builders, and the
-- Markdown/TXT/JSON side of the report.
--
-- Every builder returns lines rather than printing, which is the only reason
-- any of this is checkable: what is pinned is that each section is present,
-- headed, ordered the way the report promises (largest first), and that the
-- display mode and column width the user configured actually reach the cells.

return function(H)
  local report = require("insights.metrics.report")
  local misc = require("insights.metrics.misc")

  ---@param overrides table|nil
  ---@return table
  local function stats(overrides)
    local st = {
      total_lines = 100,
      lines_without_comments = 70,
      comment_lines = 20,
      lines_without_annotations = 90,
      annotation_lines = 10,
      blank_lines = 10,
      total_words = 200,
      words_without_comments = 140,
      words_without_annotations = 180,
      words_in_comments = 40,
      words_in_annotations = 20,
      words_in_blank = 0,
    }
    for k, v in pairs(overrides or {}) do
      st[k] = v
    end
    return st
  end

  local state = {
    root = "/proj",
    folder_summary = {
      ["lua/small"] = vim.tbl_extend("force", stats({ total_lines = 30 }), {
        file_count = 1,
        files = { { rel = "lua/small/a.lua", stats = stats({ total_lines = 30 }) } },
      }),
      ["lua/big"] = vim.tbl_extend("force", stats({ total_lines = 300 }), {
        file_count = 2,
        files = {
          { rel = "lua/big/small.lua", stats = stats({ total_lines = 100, total_words = 50 }) },
          { rel = "lua/big/huge.lua", stats = stats({ total_lines = 200, total_words = 400 }) },
        },
      }),
    },
    totals = vim.tbl_extend("force", stats({ total_lines = 330 }), { total_files = 3 }),
    global_averages = {
      comment_ratio = 0.2,
      annotation_ratio = 0.1,
      doc_ratio = 0.3,
      code_ratio = 0.7,
      avg_lines_per_file = 110,
      annotation_to_comment_ratio = 0.5,
    },
  }

  ---@param lines string[]
  ---@param needle string
  ---@return integer|nil
  local function index_of(lines, needle)
    for i, l in ipairs(lines) do
      if l:find(needle, 1, true) then
        return i
      end
    end
    return nil
  end

  -- ── legend ───────────────────────────────────────────────────────────────
  local legend = report.legend()
  H.eq(#legend, 4, "the legend is four lines")
  H.contains(legend[2], "L1=NoComments", "explaining the line columns")
  H.contains(legend[3], "W1=NoComments", "and the word columns")

  -- ── file_stats ───────────────────────────────────────────────────────────
  local files = report.file_stats(state, "both", 7)
  local files_text = table.concat(files, "\n")
  H.contains(files_text, "=== File Statistics ===", "the section is headed")
  H.contains(files_text, "L1", "with the column headers")
  H.contains(files_text, "W5", "all ten of them")
  H.contains(files_text, "lua/big/huge.lua", "and one row per file")
  H.contains(files_text, "lua/small/a.lua", "across every folder")

  -- Folders come out largest first, and files within a folder likewise.
  H.ok(
    index_of(files, "lua/big/") < index_of(files, "lua/small/"),
    "the folder with more lines is listed first"
  )
  H.ok(
    index_of(files, "lua/big/huge.lua") < index_of(files, "lua/big/small.lua"),
    "and the larger file within it"
  )

  -- The display mode reaches the cells.
  H.contains(table.concat(report.file_stats(state, "percent", 7), "\n"), "%", "percent mode")
  H.excludes(
    table
      .concat(report.file_stats(state, "numbers", 7), "\n")
      :gsub("=== [^\n]*", "")
      :gsub("Legend[^\n]*", ""),
    "%%",
    "numbers mode prints no percent signs in the table"
  )

  -- ── folder_summary ───────────────────────────────────────────────────────
  local folders = report.folder_summary(state, "both", 7)
  local folders_text = table.concat(folders, "\n")
  H.contains(folders_text, "=== Folder Summary ===", "the section is headed")
  H.contains(folders_text, "Folder", "with a folder column")
  H.contains(folders_text, "Files", "and a file count")
  H.contains(folders_text, "lua/big", "one row per folder")
  H.ok(index_of(folders, "lua/big") < index_of(folders, "lua/small"), "largest first here too")

  -- ── total_summary ────────────────────────────────────────────────────────
  local totals = report.total_summary(state, "both", 7)
  local totals_text = table.concat(totals, "\n")
  H.contains(totals_text, "=== Total Summary ===", "the section is headed")
  H.contains(totals_text, "Files", "with the file count column")
  H.contains(totals_text, "3", "holding the project's file count")

  -- Column width changes the row width, which is the whole point of the
  -- `col_width` option.
  local narrow = report.total_summary(state, "both", 5)
  local wide = report.total_summary(state, "both", 20)
  H.ok(#wide[#wide] > #narrow[#narrow], "a wider column makes a wider table")

  -- ── folder_ratios ────────────────────────────────────────────────────────
  local plain = report.folder_ratios(state, false)
  local plain_text = table.concat(plain, "\n")
  H.contains(plain_text, "=== Folder Ratios ===", "the section is headed")
  H.contains(plain_text, "Comm%", "with a comment-ratio column")
  H.contains(plain_text, "A/C", "and the annotation/comment column")
  H.excludes(plain_text, "Delta", "with no deviation columns when they are off")
  H.excludes(plain_text, "Global Averages", "and no averages line")

  local deviating = report.folder_ratios(state, true)
  local deviating_text = table.concat(deviating, "\n")
  H.contains(deviating_text, "Global Averages", "deviations add the averages line")
  H.contains(deviating_text, "Delta", "and a delta column per ratio")
  H.contains(deviating_text, "+", "with signed values")

  -- ── top-N lists ──────────────────────────────────────────────────────────
  local by_lines = report.top_files_by_lines(state, 2)
  local by_lines_text = table.concat(by_lines, "\n")
  H.contains(
    by_lines_text,
    "=== Top 2 Files by Lines ===",
    "the heading names the N and the metric"
  )
  H.contains(by_lines_text, "Share", "with a share-of-total column")
  H.contains(by_lines_text, "lua/big/huge.lua", "listing the biggest file")
  H.ok(
    index_of(by_lines, "lua/big/huge.lua") < index_of(by_lines, "lua/big/small.lua"),
    "in descending order"
  )
  H.excludes(by_lines_text, "lua/small/a.lua", "and stopping at N")

  local by_words = report.top_files_by_words(state, 3)
  local by_words_text = table.concat(by_words, "\n")
  H.contains(by_words_text, "=== Top 3 Files by Words ===", "the words list has its own heading")
  -- Ranked by words, so the file with fewer lines but more words wins.
  H.ok(
    index_of(by_words, "lua/big/huge.lua") < index_of(by_words, "lua/big/small.lua"),
    "ranked by words rather than lines"
  )

  -- Asking for more than there are is not an error.
  local over = report.top_files_by_lines(state, 99)
  H.contains(table.concat(over, "\n"), "lua/small/a.lua", "a larger N simply lists everything")

  local none = report.top_files_by_lines(
    { folder_summary = {}, totals = {}, global_averages = state.global_averages },
    5
  )
  H.contains(
    table.concat(none, "\n"),
    "=== Top 5 Files by Lines ===",
    "an empty project still prints the heading"
  )

  -- ── top_folders_by_annotation ────────────────────────────────────────────
  local anno = report.top_folders_by_annotation(state, 5)
  local anno_text = table.concat(anno, "\n")
  H.contains(anno_text, "=== Top 5 Folders by Annotation Ratio ===", "headed with the N")
  H.contains(anno_text, "Anno%", "with the ratio column")
  H.contains(anno_text, "lua/big", "and one row per folder")
  H.contains(anno_text, "lua/small", "all of them")

  -- ── ratio_guidelines ─────────────────────────────────────────────────────
  local guide = report.ratio_guidelines()
  H.contains(table.concat(guide, "\n"), "=== Optimal Ratio Guidelines", "the guidelines are headed")
  H.contains(table.concat(guide, "\n"), "Comment Ratio", "and name each metric")
  H.contains(table.concat(guide, "\n"), "@types", "with the note about excluded type files")

  -- ── misc: the non-Lua half ───────────────────────────────────────────────
  local dir, cleanup = H.fixture("metrics-misc")

  ---@param rel string
  ---@param lines string[]
  local function write(rel, lines)
    local path = dir .. "/" .. rel
    vim.fn.mkdir(vim.fs.dirname(path), "p")
    vim.fn.writefile(lines, path)
  end

  local empty_state = misc.scan(dir)
  H.ok(misc.is_empty(empty_state), "a tree with no documentation files is empty")
  H.eq(#misc.build_detailed(empty_state), 0, "and has no detail sections")
  local empty_summary = table.concat(misc.build_summary(empty_state), "\n")
  H.contains(
    empty_summary,
    "Documentation & Config Files",
    "though the summary still has a heading"
  )
  H.excludes(empty_summary, "Total", "with no total row when there is nothing to total")

  write("README.md", { "# Title", "", "some words here" })
  write("docs/guide.md", { "more words" })
  write("notes.txt", { "a b c" })
  write("data.json", { '{ "a": 1 }' })
  write("empty.md", {})
  write("code.lua", { "return {}" })

  local state_misc = misc.scan(dir)
  H.falsy(misc.is_empty(state_misc), "once there are files it is not empty")
  -- `docs/` is an ignored directory for the Lua analyzer, and `misc` goes
  -- through the same lister, so guide.md is not counted.
  H.eq(state_misc.markdown.file_count, 1, "only README.md is counted -- docs/ is ignored")
  H.eq(state_misc.txt.file_count, 1, "one text file")
  H.eq(state_misc.json.file_count, 1, "one JSON file")
  H.eq(state_misc.markdown.total_lines, 3, "with its line count")
  H.eq(state_misc.txt.total_words, 3, "and its word count")
  H.contains(state_misc.markdown.files[1].rel, "README.md", "paths are relative to the root")

  -- A file with no lines and no words is skipped: it would only add an empty
  -- row and pull the average down.
  for _, f in ipairs(state_misc.markdown.files) do
    H.excludes(f.rel, "empty.md", "an empty file is not listed")
  end

  local summary = table.concat(misc.build_summary(state_misc), "\n")
  H.contains(summary, "Markdown (*.md)", "one row per file type")
  H.contains(summary, "Text/Help (*.txt)", "for each type that found something")
  H.contains(summary, "JSON (*.json)", "all three")
  H.contains(summary, "Total", "plus a total row")
  H.contains(summary, "Avg Lines/File", "with an average column")

  local detailed = table.concat(misc.build_detailed(state_misc), "\n")
  H.contains(detailed, "=== Markdown Files ===", "the detail view has a section per type")
  H.contains(detailed, "README.md", "listing each file")
  H.contains(detailed, "=== JSON Files ===", "including JSON")

  -- A type with no files gets no section at all.
  local only_md =
    { markdown = state_misc.markdown, txt = misc.scan(dir).txt, json = misc.scan(dir).json }
  only_md.txt = { file_count = 0, total_lines = 0, total_words = 0, files = {} }
  only_md.json = { file_count = 0, total_lines = 0, total_words = 0, files = {} }
  local md_only = table.concat(misc.build_detailed(only_md), "\n")
  H.contains(md_only, "=== Markdown Files ===", "the type that has files gets a section")
  H.excludes(md_only, "=== JSON Files ===", "and the ones that do not, do not")

  cleanup()
end
