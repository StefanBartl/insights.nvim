---@module 'project_insight.tree'
---@brief Async file tree writer, file counter, and clipboard copy.
local M = {}

local notify   = require("project_insight.util.notify").create("[project_insight.tree]")
local platform = require("project_insight.util.platform")
local config   = require("project_insight.config")

local fn = vim.fn

local function current_project()
  local cwd  = fn.getcwd()
  if type(cwd) ~= "string" or cwd == "" then return nil, nil, "invalid cwd" end
  local proj = fn.fnamemodify(cwd, ":t")
  if not proj or proj == "" then return nil, nil, "failed to derive project name" end
  return cwd, proj, nil
end

local function ensure_dir(dir)
  if fn.isdirectory(dir) == 1 then return true, nil end
  local ok, err = pcall(fn.mkdir, dir, "p")
  if not ok then return false, tostring(err) end
  if fn.isdirectory(dir) ~= 1 then return false, "mkdir returned non-directory" end
  return true, nil
end

local function output_path(proj)
  local cfg = config.get().tree
  return cfg.outdir .. "/" .. (cfg.outfile_fmt:gsub("%%s", proj))
end

---Build a shell command that lists relative file paths in the project.
---@param cwd     string
---@param exclude string[]
---@return string
local function build_tree_cmd(cwd, exclude)
  if not platform.is_windows() then
    local parts = { "find", fn.shellescape(cwd), "-type f" }
    for _, p in ipairs(exclude) do
      parts[#parts + 1] = "-not -path " .. fn.shellescape(p)
    end
    parts[#parts + 1] = "-print"
    local escaped_cwd = cwd:gsub("([^%w_%./%-])", "%%%1")
    return table.concat(parts, " ")
        .. " | sed -e " .. fn.shellescape("s#^" .. escaped_cwd .. "/##")
        .. " | sort"
  end

  -- PowerShell
  local function q(s) return "'" .. tostring(s):gsub("'", "''") .. "'" end
  local regexes = {}
  for _, g in ipairs(exclude) do
    local r = g:gsub("([%^%$%(%)%%%.%[%]%+%-%?])", "%%%1")
                :gsub("%*", ".*"):gsub("/", "[\\\\/]")
    regexes[#regexes + 1] = r
  end

  local ps = {
    "$ErrorActionPreference='Stop'",
    "$cwd=[IO.Path]::GetFullPath(" .. q(cwd) .. ")",
    "$files=Get-ChildItem -LiteralPath $cwd -Recurse -File -ErrorAction SilentlyContinue"
         .. " | Select-Object -ExpandProperty FullName",
  }
  if #regexes > 0 then
    ps[#ps + 1] = "$rx=@(" .. table.concat(vim.tbl_map(q, regexes), ",") .. ")"
    ps[#ps + 1] = "$files=$files|Where-Object{ $l=$_; foreach($r in $rx){ if($l -match $r){return $false} }; $true }"
  end
  ps[#ps + 1] = "$rel=$files|ForEach-Object{ $_.Substring($cwd.Length+1) -replace '\\\\','/' }|Sort-Object"
  ps[#ps + 1] = "$rel"
  return table.concat(ps, "; ")
end

---Write the project file tree to the configured output file.
---Callback: (success, message, out_path|nil)
---@param callback fun(success:boolean, msg:string, path:string|nil)
function M.write_tree(callback)
  local cfg = config.get().tree
  local cwd, proj, err = current_project()
  if not cwd then callback(false, err or "cwd error", nil); return end

  local ok, derr = ensure_dir(cfg.outdir)
  if not ok then callback(false, "cannot create outdir: " .. tostring(derr), nil); return end

  local out = output_path(proj)
  local cmd = build_tree_cmd(cwd, cfg.exclude_patterns) .. " > " .. fn.shellescape(out)

  platform.run_shell(cmd, function(success, _, stderr)
    if success then
      callback(true, "tree written: " .. out, out)
    else
      callback(false, "tree write failed: " .. (stderr or ""), out)
    end
  end)
end

---Count project files.
---Callback: (success, message, count|nil)
---@param callback fun(success:boolean, msg:string, count:integer|nil)
function M.count_files(callback)
  local cfg = config.get().tree
  local cwd, _, err = current_project()
  if not cwd then callback(false, err or "cwd error", nil); return end

  local cmd = build_tree_cmd(cwd, cfg.exclude_patterns) .. " | wc -l"
  platform.run_shell(cmd, function(success, out, stderr)
    if not success then callback(false, "count failed: " .. (stderr or ""), nil); return end
    local n = tonumber((out or ""):match("(%d+)%s*$"))
    if not n then callback(false, "cannot parse count", nil); return end
    callback(true, string.format("files: %d", n), n)
  end)
end

---Copy the generated tree file to system clipboard.
---Callback: (success, message)
---@param callback fun(success:boolean, msg:string)
function M.copy_to_clipboard(callback)
  local _, proj, err = current_project()
  if not proj then callback(false, err or "cwd error"); return end

  local out = output_path(proj)
  if fn.filereadable(out) == 0 then
    callback(false, "tree file not found: " .. out)
    return
  end

  local ok_r, lines = pcall(fn.readfile, out)
  if ok_r and type(lines) == "table" then
    if platform.copy_to_clipboard(table.concat(lines, "\n")) then
      callback(true, "tree copied to clipboard")
      return
    end
  end
  callback(false, "clipboard backend unavailable")
end

return M
