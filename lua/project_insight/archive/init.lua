---@module 'project_insight.archive'
---@brief Async project archival for :ProjectInsight archive.
---@description
--- Creates a compressed archive and a file listing of the current working
--- directory (excluding .git) in a configurable output directory.
---
--- Platform strategy:
---   Unix/macOS  : find + tar (.tar.gz)
---   Windows     : PowerShell Get-ChildItem + Compress-Archive (.zip)
---
--- All async work goes through project_insight.util.platform.run_shell,
--- which dispatches to vim.system (Neovim 0.10+) on all platforms.

local platform = require("project_insight.util.platform")
local notify   = require("project_insight.util.notify").create("[project_insight.archive]")

local M = {}

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

---Resolve and create the output directory for this project's archive.
---@param outdir_base string  Base output directory from config.
---@return string|nil outdir
---@return string|nil errmsg
local function prepare_outdir(outdir_base)
  local cwd_name = vim.fn.fnamemodify(vim.fn.getcwd(), ":t")
  if cwd_name == "" then
    return nil, "invalid working directory"
  end
  local outdir = vim.fn.expand(outdir_base) .. "/" .. cwd_name .. "-archive"
  -- mkdir is synchronous here; directory creation is fast and blocking is fine.
  local ok = pcall(vim.fn.mkdir, outdir, "p")
  if not ok then
    return nil, "could not create output directory: " .. outdir
  end
  return outdir, nil
end

---Build the platform-specific shell commands.
---@param outdir string  Resolved output directory.
---@return table cmds  Fields: list (string), archive (string), archive_path (string)
local function build_commands(outdir)
  local cwd      = vim.fn.getcwd()
  local cwd_name = vim.fn.fnamemodify(cwd, ":t")

  if platform.is_windows() then
    -- PowerShell paths: use single-quoted string literals.
    local archive_path = outdir .. "\\" .. cwd_name .. ".zip"
    local list_path    = outdir .. "\\file-list.txt"
    return {
      list = table.concat({
        "Get-ChildItem -Recurse -Path '" .. cwd .. "'",
        "| Where-Object { $_.FullName -notlike '*\\.git\\*' }",
        "| Select-Object -ExpandProperty FullName",
        "| Out-File -FilePath '" .. list_path .. "'",
      }, " "),
      archive = "Compress-Archive -Path '" .. cwd .. "' -DestinationPath '"
                .. archive_path .. "' -Force",
      archive_path = archive_path,
    }
  else
    local archive_path = outdir .. "/" .. cwd_name .. ".tar.gz"
    local list_path    = outdir .. "/file-list.txt"
    local parent       = vim.fn.shellescape(vim.fn.fnamemodify(cwd, ":h"))
    return {
      list = "find " .. vim.fn.shellescape(cwd)
             .. " -not -path '*/.git/*' > " .. vim.fn.shellescape(list_path),
      archive = "tar --exclude=" .. vim.fn.shellescape(cwd .. "/.git")
                .. " -czf " .. vim.fn.shellescape(archive_path)
                .. " -C " .. parent
                .. " " .. vim.fn.shellescape(cwd_name),
      archive_path = archive_path,
    }
  end
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

---Compress the current working directory into the configured output directory.
---Runs asynchronously; calls on_complete(success, message) when done.
---@param cfg table   The archive config block (archive.outdir).
---@param on_complete fun(success: boolean, message: string)
function M.compress(cfg, on_complete)
  local outdir, err = prepare_outdir(cfg.outdir)
  if not outdir then
    on_complete(false, err or "unknown error")
    return
  end

  local cmds = build_commands(outdir)

  -- Step 1: generate file listing
  platform.run_shell(cmds.list, function(ok1, _, stderr1)
    if not ok1 then
      on_complete(false, "file listing failed: " .. stderr1)
      return
    end

    -- Step 2: create archive
    platform.run_shell(cmds.archive, function(ok2, _, stderr2)
      if not ok2 then
        on_complete(false, "archive failed: " .. stderr2)
      else
        on_complete(true, "archived → " .. cmds.archive_path)
      end
    end)
  end)
end

return M
