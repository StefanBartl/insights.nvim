---@module 'insights.tree'
---@brief Async file tree writer, file counter, and clipboard copy.
local M = {}

local platform = require("insights.util.platform")
local config = require("insights.config")

local fn = vim.fn

---@internal
---Current working directory + derived project name, or an error.
---@return string|nil cwd
---@return string|nil proj
---@return string|nil err
local function current_project()
  local cwd = fn.getcwd()
  if type(cwd) ~= "string" or cwd == "" then
    return nil, nil, "invalid cwd"
  end
  local proj = fn.fnamemodify(cwd, ":t")
  if not proj or proj == "" then
    return nil, nil, "failed to derive project name"
  end
  return cwd, proj, nil
end

---@internal
---Create `dir` (and parents) if it does not already exist.
---@param dir string
---@return boolean ok, string|nil err
local function ensure_dir(dir)
  if fn.isdirectory(dir) == 1 then
    return true, nil
  end
  local ok, err = pcall(fn.mkdir, dir, "p")
  if not ok then
    return false, tostring(err)
  end
  if fn.isdirectory(dir) ~= 1 then
    return false, "mkdir returned non-directory"
  end
  return true, nil
end

---@internal
---Resolve the configured tree output path for a project name.
---@param proj string
---@return string
local function output_path(proj)
  local cfg = config.get().tree
  return cfg.outdir .. "/" .. (cfg.outfile_fmt:gsub("%%s", proj))
end

---@internal
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
      .. " | sed -e "
      .. fn.shellescape("s#^" .. escaped_cwd .. "/##")
      .. " | sort"
  end

  -- PowerShell
  local function q(s)
    return "'" .. tostring(s):gsub("'", "''") .. "'"
  end
  local regexes = {}
  for _, g in ipairs(exclude) do
    local r = g:gsub("([%^%$%(%)%%%.%[%]%+%-%?])", "%%%1"):gsub("%*", ".*"):gsub("/", "[\\\\/]")
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
    ps[#ps + 1] =
      "$files=$files|Where-Object{ $l=$_; foreach($r in $rx){ if($l -match $r){return $false} }; $true }"
  end
  ps[#ps + 1] =
    "$rel=$files|ForEach-Object{ $_.Substring($cwd.Length+1) -replace '\\\\','/' }|Sort-Object"
  ps[#ps + 1] = "$rel"
  return table.concat(ps, "; ")
end

---Write the project file tree to the configured output file.
---Callback: (success, message, out_path|nil)
---@param callback fun(success:boolean, msg:string, path:string|nil)
function M.write_tree(callback)
  local cfg = config.get().tree
  local cwd, proj, err = current_project()
  if not cwd then
    callback(false, err or "cwd error", nil)
    return
  end

  local ok, derr = ensure_dir(cfg.outdir)
  if not ok then
    callback(false, "cannot create outdir: " .. tostring(derr), nil)
    return
  end

  -- current_project() only ever returns proj alongside a truthy cwd (see its
  -- own branches above), so cwd being non-nil here guarantees proj is too.
  ---@cast proj string
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
  if not cwd then
    callback(false, err or "cwd error", nil)
    return
  end

  -- Count lines of the tree listing directly in Lua rather than piping to an
  -- external `wc` — on Windows that only works by coincidence when a Unix
  -- toolchain (e.g. Git for Windows) happens to be on PATH.
  local cmd = build_tree_cmd(cwd, cfg.exclude_patterns)
  platform.run_shell(cmd, function(success, out, stderr)
    if not success then
      callback(false, "count failed: " .. (stderr or ""), nil)
      return
    end
    local n = 0
    for _ in (out or ""):gmatch("[^\r\n]+") do
      n = n + 1
    end
    callback(true, string.format("files: %d", n), n)
  end)
end

---Copy the generated tree file to system clipboard.
---Callback: (success, message)
---@param callback fun(success:boolean, msg:string)
function M.copy_to_clipboard(callback)
  local _, proj, err = current_project()
  if not proj then
    callback(false, err or "cwd error")
    return
  end

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
