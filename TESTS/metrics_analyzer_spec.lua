-- TESTS/metrics_analyzer_spec.lua — the per-file counter every metrics number
-- is derived from, and the arithmetic on top of it.
--
-- `analyze_file` classifies each line into code / comment / annotation /
-- blank, and the four buckets are not exclusive: an annotation line is also a
-- comment line, and a line with a trailing `--` is both code and comment.
-- That overlap is the part worth pinning, because every percentage in the
-- report is a ratio against a total that includes it.

return function(H)
  local analyzer = require("insights.metrics.analyzer")

  local dir, cleanup = H.fixture("metrics-analyzer")

  ---@param rel string
  ---@param lines string[]
  ---@return string
  local function write(rel, lines)
    local path = dir .. "/" .. rel
    vim.fn.mkdir(vim.fs.dirname(path), "p")
    vim.fn.writefile(lines, path)
    return path
  end

  -- ── is_type_file ─────────────────────────────────────────────────────────
  H.ok(analyzer.is_type_file("lua/proj/@types/init.lua"), "a file under @types/")
  H.ok(analyzer.is_type_file([[lua\proj\@types\init.lua]]), "with backslashes too")
  H.ok(analyzer.is_type_file("lua/proj/@types.lua"), "and a file named @types.lua")
  H.falsy(analyzer.is_type_file("lua/proj/types.lua"), "a plain types.lua is not one")
  H.falsy(analyzer.is_type_file("lua/proj/init.lua"), "and neither is an ordinary module")

  -- ── list_files ───────────────────────────────────────────────────────────
  write("keep.lua", { "return {}" })
  write("nested/deeper/keep2.lua", { "return {}" })
  write("notes.md", { "# hi" })
  write(".git/hooks/hook.lua", { "return {}" })
  write("node_modules/pkg/index.lua", { "return {}" })
  write("docs/manual.lua", { "return {}" })
  write("debuglog/trace.lua", { "return {}" })
  write("docs.lua", { "return {}" })

  local lua_files = analyzer.get_lua_files(dir)
  local names = {}
  for _, f in ipairs(lua_files) do
    names[vim.fn.fnamemodify(f, ":t")] = true
  end

  H.ok(names["keep.lua"], "a top-level Lua file is listed")
  H.ok(names["keep2.lua"], "and one nested any number of levels down")
  H.ok(names["docs.lua"], "a *file* named docs.lua is kept -- only directories are ignored")
  H.eq(names["hook.lua"], nil, ".git is ignored")
  H.eq(names["index.lua"], nil, "node_modules is ignored")
  H.eq(names["manual.lua"], nil, "docs/ is ignored")
  H.eq(names["trace.lua"], nil, "debuglog/ is ignored")
  H.eq(names["notes.md"], nil, "and a non-Lua file is not a Lua file")

  local md = analyzer.list_files(dir, "*.md")
  H.eq(#md, 1, "another pattern finds its own files")
  H.contains(md[1], "notes.md", "the Markdown one")

  for _, f in ipairs(lua_files) do
    H.excludes(f, "\\", "paths come back with forward slashes")
  end

  -- ── analyze_file ─────────────────────────────────────────────────────────
  local path = write("sample.lua", {
    "local M = {}", -- 1: code
    "", -- 2: blank
    "-- a plain comment", -- 3: comment
    "---@param x integer", -- 4: annotation (and a comment)
    "function M.f(x)", -- 5: code
    "  return x -- trailing", -- 6: code AND comment
    "end", -- 7: code
    "--[[", -- 8: block comment opens
    "still inside the block", -- 9: inside
    "]]", -- 10: block closes
    "return M", -- 11: code
  })

  local st = analyzer.analyze_file(path)
  H.eq(st.total_lines, 11, "every line is counted")
  H.eq(st.blank_lines, 1, "the empty one is blank")
  H.eq(st.annotation_lines, 1, "the ---@ line is an annotation")

  -- Comments: the plain one, the annotation, the trailing one, and the three
  -- lines of the block.
  H.eq(st.comment_lines, 6, "comment lines include annotations and block lines")

  -- Code: everything with something left after the comment is stripped.
  H.eq(st.lines_without_comments, 5, "code lines are the ones with code on them")
  -- Every non-blank line that is not an annotation. Blank lines are counted
  -- in `blank_lines` only and never reach this bucket -- pinned so the
  -- asymmetry with `lines_without_comments` is a decision, not drift.
  H.eq(st.lines_without_annotations, 9, "every non-blank line but the annotation")
  H.eq(
    st.lines_without_comments + st.comment_lines + st.blank_lines,
    12,
    "the buckets overlap by one -- line 6 is both code and comment"
  )

  H.ok(st.total_words > 0, "words are counted")
  H.ok(st.words_in_comments > 0, "in comments")
  H.ok(st.words_in_annotations > 0, "and in annotations")
  H.eq(st.words_in_blank, 0, "a blank line contributes no words, ever")

  -- An unreadable file answers zeroes rather than nil, so a folder total is
  -- never poisoned by one missing file.
  local absent = analyzer.analyze_file(dir .. "/does-not-exist.lua")
  H.ok(absent, "a missing file still answers a stats table")
  H.eq(absent.total_lines, 0, "with nothing counted")

  ---@diagnostic disable-next-line: param-type-mismatch
  H.eq(analyzer.analyze_file(42), nil, "a non-string path is refused outright")

  local empty_path = write("empty.lua", {})
  local empty_st = analyzer.analyze_file(empty_path)
  H.eq(empty_st.total_lines, 0, "an empty file has no lines")

  -- ── create_empty_stats / create_empty_folder_stats ───────────────────────
  local blank = analyzer.create_empty_stats()
  H.eq(blank.total_lines, 0, "an empty stats object starts at zero")
  H.eq(blank.total_files, 0, "including its file count")

  local folder = analyzer.create_empty_folder_stats()
  H.eq(folder.total_files, nil, "a folder's stats count files differently")
  H.eq(folder.file_count, 0, "under file_count")
  H.eq(#folder.files, 0, "and carry a per-file list")

  -- ── percent ──────────────────────────────────────────────────────────────
  H.eq(analyzer.percent(1, 4), 25, "a quarter")
  H.eq(analyzer.percent(0, 10), 0, "nothing of something")
  H.eq(analyzer.percent(5, 0), 0, "and something of nothing is zero, not a division by zero")
  ---@diagnostic disable-next-line: param-type-mismatch
  H.eq(analyzer.percent(5, nil), 0, "a missing total is the same")

  -- ── compute_percentages ──────────────────────────────────────────────────
  local l1, l2, l3, l4, l5, w1, w2, w3, w4, w5 = analyzer.compute_percentages({
    total_lines = 10,
    total_words = 20,
    lines_without_comments = 5,
    comment_lines = 3,
    lines_without_annotations = 9,
    annotation_lines = 1,
    blank_lines = 2,
    words_without_comments = 10,
    words_without_annotations = 18,
    words_in_comments = 6,
    words_in_annotations = 2,
    words_in_blank = 0,
  })
  H.eq(l1, 50, "L1 is code lines over total lines")
  H.eq(l2, 30, "L2 comments")
  H.eq(l3, 90, "L3 non-annotation lines")
  H.eq(l4, 10, "L4 annotations")
  H.eq(l5, 20, "L5 blank")
  H.eq(w1, 50, "W1 is code words over total words")
  H.eq(w2, 90, "W2 non-annotation words")
  H.eq(w3, 30, "W3 comment words")
  H.eq(w4, 10, "W4 annotation words")
  H.eq(w5, 0, "W5 blank words")

  -- Every field is optional; a sparse stats object must not raise.
  local sparse = { analyzer.compute_percentages({}) }
  H.eq(#sparse, 10, "an empty stats object still yields ten percentages")
  for _, v in ipairs(sparse) do
    H.eq(v, 0, "all of them zero")
  end

  -- ── format_value ─────────────────────────────────────────────────────────
  H.eq(analyzer.format_value(42, 12.345, "both"), "42 (12.3%)", "the default shows both")
  H.eq(analyzer.format_value(42, 12.345, "percent"), "12.3%", "percent-only")
  H.eq(analyzer.format_value(42, 12.345, "numbers"), "42", "numbers-only")
  H.eq(analyzer.format_value(42, 12.345, "anything else"), "42 (12.3%)", "an unknown mode is both")
  ---@diagnostic disable-next-line: param-type-mismatch
  H.eq(analyzer.format_value(nil, nil, "both"), "0 (0.0%)", "missing values read as zero")

  -- ── format_deviation ─────────────────────────────────────────────────────
  H.eq(analyzer.format_deviation(0.25, 0.20), "+5.0%", "above the average carries a sign")
  H.eq(analyzer.format_deviation(0.15, 0.20), "-5.0%", "and below carries its own")
  H.eq(analyzer.format_deviation(0.20, 0.20), "+0.0%", "exactly on it reads as +0.0%")

  -- ── compute_ratios ───────────────────────────────────────────────────────
  local ratios = analyzer.compute_ratios({
    total_lines = 100,
    comment_lines = 20,
    annotation_lines = 10,
    lines_without_comments = 70,
    total_files = 4,
  })
  H.eq(ratios.comment_ratio, 0.2, "comment ratio")
  H.eq(ratios.annotation_ratio, 0.1, "annotation ratio")
  H.ok(math.abs(ratios.doc_ratio - 0.3) < 1e-9, "documentation is comments plus annotations")
  H.eq(ratios.code_ratio, 0.7, "code ratio")
  H.eq(ratios.avg_lines_per_file, 25, "average lines per file")
  H.eq(ratios.annotation_to_comment_ratio, 0.5, "and annotations per comment")

  -- A folder's stats count files under `file_count`, not `total_files`.
  H.eq(
    analyzer.compute_ratios({ total_lines = 50, file_count = 5 }).avg_lines_per_file,
    10,
    "file_count is used when total_files is absent"
  )

  local zeroes = analyzer.compute_ratios({})
  for key, value in pairs(zeroes) do
    H.eq(value, 0, key .. " is zero for an empty stats object, not a division by zero")
  end

  cleanup()
end
