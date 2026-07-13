---@module 'project_insight.metrics.misc'
---@brief Analysis of non-Lua project files (Markdown, TXT, JSON).
---
--- Provides file/line/word counts per file type, plus summary and detailed
--- report sections. Line arrays are returned (not printed) so the caller can
--- render them in a scratch buffer and/or write them to a file.
local M = {}

local analyzer = require("project_insight.metrics.analyzer")

local str_fmt = string.format

---@class MiscFileStats
---@field file_count  integer
---@field total_lines integer
---@field total_words integer
---@field files { rel: string, lines: integer, words: integer }[]

---@class MiscState
---@field markdown MiscFileStats
---@field txt      MiscFileStats
---@field json     MiscFileStats

---@return MiscFileStats
local function empty()
  return { file_count = 0, total_lines = 0, total_words = 0, files = {} }
end

---Count lines and words of a single non-Lua file.
---@param path string
---@return integer lines, integer words
local function analyze_file(path)
  local lines, words = 0, 0
  local ok, fh = pcall(io.open, path, "r")
  if not ok or not fh then return 0, 0 end
  for line in fh:lines() do
    lines = lines + 1
    for _ in line:gmatch("%S+") do words = words + 1 end
  end
  fh:close()
  return lines, words
end

--- Scan `root` for Markdown / TXT / JSON files.
---@param root string   normalized directory (absolute, forward slashes)
---@return MiscState
function M.scan(root)
  local state = { markdown = empty(), txt = empty(), json = empty() }
  local kinds = {
    { key = "markdown", pattern = "*.md" },
    { key = "txt",      pattern = "*.txt" },
    { key = "json",     pattern = "*.json" },
  }
  for _, ft in ipairs(kinds) do
    for _, file in ipairs(analyzer.list_files(root, ft.pattern)) do
      local lines, words = analyze_file(file)
      if lines > 0 or words > 0 then
        local st = state[ft.key]
        st.file_count  = st.file_count + 1
        st.total_lines = st.total_lines + lines
        st.total_words = st.total_words + words
        st.files[#st.files + 1] = { rel = file:sub(#root + 2), lines = lines, words = words }
      end
    end
  end
  return state
end

---True when no misc files were found at all.
---@param state MiscState
---@return boolean
function M.is_empty(state)
  return state.markdown.file_count == 0
     and state.txt.file_count == 0
     and state.json.file_count == 0
end

--- Build the summary section (one row per file type + total).
---@param state MiscState
---@return string[]
function M.build_summary(state)
  local line  = string.rep("-", 95)
  local lines = {
    "",
    "=== Documentation & Config Files ===",
    line,
    str_fmt("| %-20s | %8s | %12s | %12s | %15s |",
      "Type", "Files", "Lines", "Words", "Avg Lines/File"),
    line,
  }

  local types = {
    { key = "markdown", label = "Markdown (*.md)" },
    { key = "txt",      label = "Text/Help (*.txt)" },
    { key = "json",     label = "JSON (*.json)" },
  }

  local tf, tl, tw = 0, 0, 0
  for _, t in ipairs(types) do
    local st = state[t.key]
    if st.file_count > 0 then
      lines[#lines + 1] = str_fmt("| %-20s | %8d | %12d | %12d | %15.1f |",
        t.label, st.file_count, st.total_lines, st.total_words,
        st.total_lines / st.file_count)
      tf, tl, tw = tf + st.file_count, tl + st.total_lines, tw + st.total_words
    end
  end

  if tf > 0 then
    lines[#lines + 1] = line
    lines[#lines + 1] = str_fmt("| %-20s | %8d | %12d | %12d | %15.1f |",
      "Total", tf, tl, tw, tl / tf)
  end
  lines[#lines + 1] = line
  return lines
end

--- Build the detailed per-file listing for each file type.
---@param state MiscState
---@return string[]
function M.build_detailed(state)
  local line  = string.rep("-", 95)
  local lines = {}
  local types = {
    { key = "markdown", label = "Markdown Files" },
    { key = "txt",      label = "Text/Help Files" },
    { key = "json",     label = "JSON Files" },
  }
  for _, t in ipairs(types) do
    local st = state[t.key]
    if st.file_count > 0 then
      lines[#lines + 1] = ""
      lines[#lines + 1] = str_fmt("=== %s ===", t.label)
      lines[#lines + 1] = line
      lines[#lines + 1] = str_fmt("| %-60s | %12s | %12s |", "File", "Lines", "Words")
      lines[#lines + 1] = line
      for _, f in ipairs(st.files) do
        lines[#lines + 1] = str_fmt("| %-60s | %12d | %12d |", f.rel, f.lines, f.words)
      end
      lines[#lines + 1] = line
    end
  end
  return lines
end

return M
