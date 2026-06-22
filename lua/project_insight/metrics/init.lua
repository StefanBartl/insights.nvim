---@module 'project_insight.metrics'
---@brief Lua project file statistics: per-file, per-folder, totals, ratios.
local M = {}

local notify  = require("project_insight.util.notify").create("[project_insight.metrics]")
local analyzer = require("project_insight.metrics.analyzer")
local config   = require("project_insight.config")

---@class MetricsResult
---@field total_files   integer
---@field total_lines   integer
---@field folder_summary table<string, table>
---@field totals        table
---@field output_lines  string[]

---Scan `root_dir` for Lua files and aggregate stats.
---@param root_dir      string
---@param exclude_types boolean
---@return MetricsResult
function M.scan(root_dir, exclude_types)
  local files = analyzer.get_lua_files(root_dir)

  local folder_summary = {}
  local totals         = analyzer.create_empty_stats()
  local cwd            = vim.fn.getcwd()

  for _, file in ipairs(files) do
    if not (exclude_types and analyzer.is_type_file(file)) then
      local st = analyzer.analyze_file(file)
      if st then
        local rel  = file:sub(#cwd + 2)
        local dir  = rel:match("(.+)[/\\]") or "."
        if not folder_summary[dir] then
          folder_summary[dir] = vim.tbl_extend("force",
            analyzer.create_empty_stats(), { file_count=0, files={} })
        end
        local fs = folder_summary[dir]
        for k, v in pairs(st) do
          if type(v) == "number" then fs[k] = (fs[k] or 0) + v end
        end
        fs.file_count = (fs.file_count or 0) + 1
        table.insert(fs.files or {}, { rel=rel, stats=st })

        for k, v in pairs(st) do
          if type(v) == "number" then totals[k] = (totals[k] or 0) + v end
        end
        totals.total_files = (totals.total_files or 0) + 1
      end
    end
  end

  return {
    total_files    = totals.total_files or 0,
    total_lines    = totals.total_lines or 0,
    folder_summary = folder_summary,
    totals         = totals,
    output_lines   = {},
  }
end

local function pct(part, total)
  if not total or total == 0 then return 0 end
  return (part / total) * 100
end

---Format a simple summary report as lines of text.
---@param result MetricsResult
---@return string[]
function M.format_report(result)
  local t = result.totals
  local lines = {
    "=== Project File Statistics ===",
    string.format("Lua files : %d", result.total_files),
    string.format("Total lines: %d", t.total_lines or 0),
    string.format("  Code      : %d (%.1f%%)", t.lines_without_comments or 0,
                  pct(t.lines_without_comments or 0, t.total_lines or 0)),
    string.format("  Comments  : %d (%.1f%%)", t.comment_lines or 0,
                  pct(t.comment_lines or 0, t.total_lines or 0)),
    string.format("  Annots    : %d (%.1f%%)", t.annotation_lines or 0,
                  pct(t.annotation_lines or 0, t.total_lines or 0)),
    string.format("  Blank     : %d (%.1f%%)", t.blank_lines or 0,
                  pct(t.blank_lines or 0, t.total_lines or 0)),
    "",
    "--- Folders ---",
  }

  -- Sort folders by line count descending
  local folders = {}
  for dir, fs in pairs(result.folder_summary) do
    folders[#folders + 1] = { dir=dir, fs=fs }
  end
  table.sort(folders, function(a, b)
    return (a.fs.total_lines or 0) > (b.fs.total_lines or 0)
  end)

  for _, item in ipairs(folders) do
    local r = analyzer.compute_ratios(item.fs)
    lines[#lines + 1] = string.format(
      "  %-40s  files=%d  lines=%d  code=%.0f%%  ann=%.0f%%",
      item.dir,
      item.fs.file_count or 0,
      item.fs.total_lines or 0,
      r.code_ratio * 100,
      r.annotation_ratio * 100)
  end

  return lines
end

---Write the report to the configured output file.
---@param lines string[]
---@param out_path string
---@return boolean, string|nil
function M.write_report(lines, out_path)
  local dir = vim.fn.fnamemodify(out_path, ":h")
  if vim.fn.isdirectory(dir) == 0 then
    local ok, err = pcall(vim.fn.mkdir, dir, "p")
    if not ok then return false, tostring(err) end
  end
  local ok, fh = pcall(io.open, out_path, "w")
  if not ok or not fh then return false, "could not open file" end
  fh:write(table.concat(lines, "\n"))
  fh:close()
  return true, nil
end

---Run analysis for current project and open scratch buffer with report.
function M.run()
  local cfg     = config.get()
  local root    = vim.fn.getcwd()
  local met_cfg = cfg.metrics

  notify.info("analyzing Lua files in " .. root .. " …")
  local result = M.scan(root, met_cfg.exclude_type_files ~= false)

  if result.total_files == 0 then
    notify.warn("no Lua files found in " .. root)
    return
  end

  local report = M.format_report(result)

  local ok, err = M.write_report(report, met_cfg.output_file)
  if ok then
    notify.info("report written: " .. met_cfg.output_file)
  else
    notify.warn("could not write report: " .. tostring(err))
  end

  -- Open in scratch buffer
  local scratch = require("project_insight.ui.scratch")
  scratch.open(report, "Metrics — " .. vim.fn.fnamemodify(root, ":t"))
end

return M
