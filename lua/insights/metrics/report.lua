---@module 'insights.metrics.report'
---@brief ASCII report builders for Lua metrics. Every builder returns a list
---of lines so the caller can render them in a scratch buffer and/or write them
---to a file (no direct printing).
local M = {}

local analyzer = require("insights.metrics.analyzer")

local str_fmt, rep = string.format, string.rep
local sort = table.sort

local HEADER_COLS = { "L1", "L2", "L3", "L4", "L5", "W1", "W2", "W3", "W4", "W5" }

---@internal
---@param value any
---@param width integer
---@return string
local function cell(value, width)
  return str_fmt("%-" .. tostring(width) .. "s", tostring(value))
end

---@internal
---Row with a wide left "File" column followed by the data cells.
---@param left string
---@param cells string[]
---@param col_width integer
---@return string
local function row_with_file_col(left, cells, col_width)
  local parts = { "| " .. cell(left, 60) .. " |" }
  for _, c in ipairs(cells) do
    parts[#parts + 1] = " " .. cell(c, col_width) .. " |"
  end
  return table.concat(parts, "")
end

---@internal
---The ten formatted data cells for a stats object.
---@param s table
---@param mode string
---@return string[]
local function data_cells(s, mode)
  local l1, l2, l3, l4, l5, w1, w2, w3, w4, w5 = analyzer.compute_percentages(s)
  return {
    analyzer.format_value(s.lines_without_comments, l1, mode),
    analyzer.format_value(s.comment_lines, l2, mode),
    analyzer.format_value(s.lines_without_annotations, l3, mode),
    analyzer.format_value(s.annotation_lines, l4, mode),
    analyzer.format_value(s.blank_lines, l5, mode),
    analyzer.format_value(s.words_without_comments, w1, mode),
    analyzer.format_value(s.words_without_annotations, w2, mode),
    analyzer.format_value(s.words_in_comments, w3, mode),
    analyzer.format_value(s.words_in_annotations, w4, mode),
    analyzer.format_value(s.words_in_blank, w5, mode),
  }
end

---Legend explaining the L*/W* columns.
---@return string[]
function M.legend()
  return {
    "Legend (percentages relative to total lines or total words):",
    "Lines: L1=NoComments, L2=Comments, L3=NoAnnotations, L4=Annotations, L5=Whitespace",
    "Words: W1=NoComments, W2=NoAnnotations, W3=Comments, W4=Annotations, W5=Whitespace",
    "",
  }
end

---@internal
---Sorted (folder, stats) pairs, largest by total lines first.
---@param state table
---@return { folder: string, stats: table }[]
local function sorted_folders(state)
  local list = {}
  for folder, stats in pairs(state.folder_summary) do
    list[#list + 1] = { folder = folder, stats = stats }
  end
  sort(list, function(a, b)
    return (a.stats.total_lines or 0) > (b.stats.total_lines or 0)
  end)
  return list
end

---Detailed per-file table.
---@param state table
---@param mode string
---@param col_width integer
---@return string[]
function M.file_stats(state, mode, col_width)
  local line = rep("-", 60 + 10 * (col_width + 3))
  local out = { "", "=== File Statistics ===" }
  vim.list_extend(out, M.legend())
  out[#out + 1] = line
  out[#out + 1] = row_with_file_col("File", HEADER_COLS, col_width)
  out[#out + 1] = line

  for _, item in ipairs(sorted_folders(state)) do
    local files = {}
    for _, f in ipairs(item.stats.files) do
      files[#files + 1] = f
    end
    sort(files, function(a, b)
      return (a.stats.total_lines or 0) > (b.stats.total_lines or 0)
    end)
    for _, f in ipairs(files) do
      out[#out + 1] = row_with_file_col(f.rel, data_cells(f.stats, mode), col_width)
    end
  end

  out[#out + 1] = line
  return out
end

---Per-folder aggregate table.
---@param state table
---@param mode string
---@param col_width integer
---@return string[]
function M.folder_summary(state, mode, col_width)
  local line = rep("-", 42 + 10 * (col_width + 3))
  local out = { "", "=== Folder Summary ===" }
  vim.list_extend(out, M.legend())
  out[#out + 1] = line

  local header = { "| " .. cell("Folder", 40) .. " | " .. cell("Files", 5) .. " |" }
  for _, h in ipairs(HEADER_COLS) do
    header[#header + 1] = " " .. cell(h, col_width) .. " |"
  end
  out[#out + 1] = table.concat(header, "")
  out[#out + 1] = line

  for _, item in ipairs(sorted_folders(state)) do
    local parts =
      { "| " .. cell(item.folder, 40) .. " | " .. cell(item.stats.file_count or 0, 5) .. " |" }
    for _, c in ipairs(data_cells(item.stats, mode)) do
      parts[#parts + 1] = " " .. cell(c, col_width) .. " |"
    end
    out[#out + 1] = table.concat(parts, "")
  end

  out[#out + 1] = line
  return out
end

---Grand-total summary row.
---@param state table
---@param mode string
---@param col_width integer
---@return string[]
function M.total_summary(state, mode, col_width)
  local line = rep("-", 42 + 10 * (col_width + 3))
  local out = { "", "=== Total Summary ===" }
  vim.list_extend(out, M.legend())
  out[#out + 1] = line

  local header = { "| " .. cell("Files", 8) .. " |" }
  for _, h in ipairs(HEADER_COLS) do
    header[#header + 1] = " " .. cell(h, col_width) .. " |"
  end
  out[#out + 1] = table.concat(header, "")
  out[#out + 1] = line

  local parts = { "| " .. cell(state.totals.total_files or 0, 8) .. " |" }
  for _, c in ipairs(data_cells(state.totals, mode)) do
    parts[#parts + 1] = " " .. cell(c, col_width) .. " |"
  end
  out[#out + 1] = table.concat(parts, "")
  out[#out + 1] = line
  return out
end

---Folder ratio table, optionally with deviations from the global average.
---@param state table
---@param show_deviations boolean
---@return string[]
function M.folder_ratios(state, show_deviations)
  local line = rep("-", 130)
  local ga = state.global_averages
  local out = {
    "",
    "=== Folder Ratios ===",
    "(Type definition files excluded from ratio analysis)",
  }

  if show_deviations then
    out[#out + 1] = str_fmt(
      "Global Averages: Comm=%.1f%%, Anno=%.1f%%, Doc=%.1f%%, Code=%.1f%%, L/File=%.1f, A/C=%.2f",
      ga.comment_ratio * 100,
      ga.annotation_ratio * 100,
      ga.doc_ratio * 100,
      ga.code_ratio * 100,
      ga.avg_lines_per_file,
      ga.annotation_to_comment_ratio
    )
  end

  out[#out + 1] = line
  if show_deviations then
    out[#out + 1] = str_fmt(
      "| %-40s | %6s | %8s | %6s | %8s | %6s | %8s | %6s | %8s | %8s | %6s |",
      "Folder",
      "Comm%",
      "Delta",
      "Anno%",
      "Delta",
      "Doc%",
      "Delta",
      "Code%",
      "Delta",
      "L/File",
      "A/C"
    )
  else
    out[#out + 1] = str_fmt(
      "| %-40s | %6s | %6s | %6s | %6s | %8s | %6s |",
      "Folder",
      "Comm%",
      "Anno%",
      "Doc%",
      "Code%",
      "L/File",
      "A/C"
    )
  end
  out[#out + 1] = line

  for _, item in ipairs(sorted_folders(state)) do
    local r = analyzer.compute_ratios(item.stats)
    if show_deviations then
      out[#out + 1] = str_fmt(
        "| %-40s | %6.1f | %8s | %6.1f | %8s | %6.1f | %8s | %6.1f | %8s | %8.1f | %6.2f |",
        item.folder,
        r.comment_ratio * 100,
        analyzer.format_deviation(r.comment_ratio, ga.comment_ratio),
        r.annotation_ratio * 100,
        analyzer.format_deviation(r.annotation_ratio, ga.annotation_ratio),
        r.doc_ratio * 100,
        analyzer.format_deviation(r.doc_ratio, ga.doc_ratio),
        r.code_ratio * 100,
        analyzer.format_deviation(r.code_ratio, ga.code_ratio),
        r.avg_lines_per_file,
        r.annotation_to_comment_ratio
      )
    else
      out[#out + 1] = str_fmt(
        "| %-40s | %6.1f | %6.1f | %6.1f | %6.1f | %8.1f | %6.2f |",
        item.folder,
        r.comment_ratio * 100,
        r.annotation_ratio * 100,
        r.doc_ratio * 100,
        r.code_ratio * 100,
        r.avg_lines_per_file,
        r.annotation_to_comment_ratio
      )
    end
  end

  out[#out + 1] = line
  return out
end

---@internal
---Flatten all files across folders.
---@param state table
---@return { rel: string, stats: table }[]
local function all_files(state)
  local files = {}
  for _, folder in pairs(state.folder_summary) do
    for _, f in ipairs(folder.files) do
      files[#files + 1] = f
    end
  end
  return files
end

---@internal
---Top-N files by a numeric stat field.
---@param state table
---@param n integer
---@param field "total_lines"|"total_words"
---@param label string
---@return string[]
local function top_files(state, n, field, label)
  local files = all_files(state)
  sort(files, function(a, b)
    return (a.stats[field] or 0) > (b.stats[field] or 0)
  end)

  local line = rep("-", 95)
  local total = state.totals[field] or 0
  local out = {
    "",
    str_fmt("=== Top %d Files by %s ===", n, label),
    line,
    str_fmt("| %3s | %-60s | %9s | %9s |", "No", "File", label, "Share"),
    line,
  }
  for i = 1, math.min(n, #files) do
    local v = files[i].stats[field] or 0
    out[#out + 1] =
      str_fmt("| %3d | %-60s | %9d | %8.2f%% |", i, files[i].rel, v, analyzer.percent(v, total))
  end
  out[#out + 1] = line
  return out
end

---@param state table
---@param n integer
---@return string[]
function M.top_files_by_lines(state, n)
  return top_files(state, n, "total_lines", "Lines")
end

---@param state table
---@param n integer
---@return string[]
function M.top_files_by_words(state, n)
  return top_files(state, n, "total_words", "Words")
end

---Top-N folders ranked by annotation ratio.
---@param state table
---@param n integer
---@return string[]
function M.top_folders_by_annotation(state, n)
  local list = {}
  for folder, stats in pairs(state.folder_summary) do
    list[#list + 1] = {
      folder = folder,
      ratio = analyzer.compute_ratios(stats).annotation_ratio,
      lines = stats.total_lines or 0,
    }
  end
  sort(list, function(a, b)
    return a.ratio > b.ratio
  end)

  local line = rep("-", 80)
  local out = {
    "",
    str_fmt("=== Top %d Folders by Annotation Ratio ===", n),
    "(Type definition files excluded from this ranking)",
    line,
    str_fmt("| %3s | %-40s | %8s | %8s |", "No", "Folder", "Anno%", "Lines"),
    line,
  }
  for i = 1, math.min(n, #list) do
    local e = list[i]
    out[#out + 1] = str_fmt("| %3d | %-40s | %7.2f | %8d |", i, e.folder, e.ratio * 100, e.lines)
  end
  out[#out + 1] = line
  return out
end

---Heuristic ratio guidelines.
---@return string[]
function M.ratio_guidelines()
  return {
    "",
    "=== Optimal Ratio Guidelines (Heuristic) ===",
    "",
    "Metric                     Typical Range    Interpretation",
    "-------------------------- ---------------- ------------------------------------------------------------",
    "Comment Ratio              15% - 30%        Healthy explanation density. Below 10% often under-documented.",
    "Annotation Ratio           5% - 12%         Strong LuaLS/EmmyLua usage. Above 15% = API-heavy modules.",
    "Documentation Ratio        20% - 40%        Combined comments + annotations for maintainability.",
    "Code Ratio                 55% - 75%        Effective executable logic density.",
    "Avg Lines per File         80 - 200         Modular structure indicator.",
    "Annotation/Comment Ratio   0.20 - 0.50      Balance between semantic and technical documentation.",
    "",
    "Note: Type definition files (@types) are excluded from ratio calculations as they",
    "      naturally have very high annotation ratios and would skew the results.",
  }
end

return M
