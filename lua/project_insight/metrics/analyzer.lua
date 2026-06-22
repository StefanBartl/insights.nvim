---@module 'project_insight.metrics.analyzer'
---@brief Per-file Lua code metrics: lines, comments, annotations, words.
local M = {}

local IGNORE_DIRS = { ".git", "node_modules", ".cache", "debuglog", "docs" }

---Return true if path contains an ignored directory segment.
---@param path string
---@return boolean
local function should_ignore(path)
  local lp = path:lower()
  for _, d in ipairs(IGNORE_DIRS) do
    if lp:find(d:lower(), 1, true) then return true end
  end
  return false
end

---Check whether path is a @types file (excluded from ratio analysis).
---@param path string
---@return boolean
function M.is_type_file(path)
  return path:match("[/\\]@types[/\\]") ~= nil
      or path:match("[/\\]@types%.lua$") ~= nil
end

---Find all .lua files under `dir` (respects IGNORE_DIRS).
---@param dir string
---@return string[]
function M.get_lua_files(dir)
  local files = {}
  local pattern = dir .. "/**/*.lua"
  local found = vim.fn.glob(pattern, false, true)
  for _, f in ipairs(found) do
    if not should_ignore(f) then
      files[#files + 1] = f
    end
  end
  return files
end

---@param s string|nil
---@return integer
local function word_count(s)
  if not s or type(s) ~= "string" then return 0 end
  local n = 0
  for _ in s:gmatch("%S+") do n = n + 1 end
  return n
end

---Analyze a single Lua file and return line/word statistics.
---@param filepath string
---@return table|nil   stats object (see create_empty_stats)
function M.analyze_file(filepath)
  if type(filepath) ~= "string" then return nil end

  local st = {
    total_lines              = 0,
    lines_without_comments   = 0,
    comment_lines            = 0,
    lines_without_annotations= 0,
    annotation_lines         = 0,
    blank_lines              = 0,
    total_words              = 0,
    words_in_comments        = 0,
    words_in_annotations     = 0,
    words_without_comments   = 0,
    words_without_annotations= 0,
    words_in_blank           = 0,
  }

  local ok, fh = pcall(io.open, filepath, "r")
  if not ok or not fh then return st end

  local in_block = false

  for line in fh:lines() do
    st.total_lines = st.total_lines + 1
    local trimmed = line:match("^%s*(.-)%s*$") or ""

    if trimmed == "" then
      st.blank_lines = st.blank_lines + 1
    else
      local code_part, comment_part = trimmed, ""

      if in_block then
        comment_part = code_part
        code_part = ""
        if trimmed:find("%]%]") then in_block = false end
      elseif trimmed:match("^%-%-%[%[") then
        in_block = true
        comment_part = code_part
        code_part = ""
      else
        local ip = code_part:find("%-%-")
        if ip then
          comment_part = code_part:sub(ip)
          code_part    = code_part:sub(1, ip - 1)
        elseif trimmed:match("^%-%-") then
          comment_part = code_part
          code_part    = ""
        end
      end

      local is_annotation = comment_part:match("^%-%-%-%@") ~= nil

      if is_annotation then
        st.annotation_lines         = st.annotation_lines + 1
        st.words_in_annotations     = st.words_in_annotations + word_count(comment_part)
      end

      if #comment_part > 0 then
        st.comment_lines            = st.comment_lines + 1
        st.words_in_comments        = st.words_in_comments + word_count(comment_part)
      end

      if #code_part > 0 then
        st.lines_without_comments   = st.lines_without_comments + 1
        st.words_without_comments   = st.words_without_comments + word_count(code_part)
      end

      if not is_annotation then
        st.lines_without_annotations= st.lines_without_annotations + 1
        st.words_without_annotations= st.words_without_annotations + word_count(code_part)
      end

      st.total_words = st.total_words + word_count(code_part) + word_count(comment_part)
    end
  end

  fh:close()
  return st
end

---@return table
function M.create_empty_stats()
  return {
    total_lines=0, lines_without_comments=0, comment_lines=0,
    lines_without_annotations=0, annotation_lines=0, blank_lines=0,
    total_words=0, words_in_comments=0, words_in_annotations=0,
    words_without_comments=0, words_without_annotations=0, words_in_blank=0,
    total_files=0,
  }
end

---Compute ratio metrics from a stats object.
---@param st table
---@return { comment_ratio:number, annotation_ratio:number, code_ratio:number, avg_lines_per_file:number }
function M.compute_ratios(st)
  local total = st.total_lines or 0
  local files = st.total_files or st.file_count or 1
  return {
    comment_ratio    = total > 0 and (st.comment_lines or 0) / total or 0,
    annotation_ratio = total > 0 and (st.annotation_lines or 0) / total or 0,
    code_ratio       = total > 0 and (st.lines_without_comments or 0) / total or 0,
    avg_lines_per_file = files > 0 and total / files or 0,
  }
end

return M
