---@module 'project_insight.compress'
---@brief Async project compression for :ProjectInsight compress.
---
--- Supported engines:
---   "tar"        — find + tar  → .tar.gz   (Unix/macOS)
---   "zip"        — find + zip  → .zip      (Unix/macOS, requires zip)
---   "powershell" — Compress-Archive → .zip (Windows)
---   "auto"       — tar on Unix, powershell on Windows (default)
---
--- outdir resolution (compress.outdir in config):
---   ""  (default) → <path>/compressed/    (adjacent to the project)
---   non-empty     → <outdir>/<name>-compressed/

local platform = require("project_insight.util.platform")
local notify   = require("project_insight.util.notify").create("[project_insight.compress]")

local M = {}

-- ---------------------------------------------------------------------------
-- Outdir resolution
-- ---------------------------------------------------------------------------

---Resolve and create the output directory.
---@param path       string  Absolute directory being compressed.
---@param cfg_outdir string  compress.outdir from config ("" = adjacent).
---@return string|nil outdir
---@return string|nil errmsg
local function resolve_outdir(path, cfg_outdir)
  local sep = platform.is_windows() and "\\" or "/"
  local outdir
  if not cfg_outdir or cfg_outdir == "" then
    outdir = path .. sep .. "compressed"
  else
    local name = vim.fn.fnamemodify(path, ":t")
    outdir = vim.fn.expand(cfg_outdir) .. sep .. name .. "-compressed"
  end
  local ok = pcall(vim.fn.mkdir, outdir, "p")
  if not ok then
    return nil, "could not create output directory: " .. outdir
  end
  return outdir, nil
end

-- ---------------------------------------------------------------------------
-- Engine implementations
-- ---------------------------------------------------------------------------

local engines = {}

function engines.tar(path, outdir, on_complete)
  local name      = vim.fn.fnamemodify(path, ":t")
  local out_path  = outdir .. "/" .. name .. ".tar.gz"
  local list_path = outdir .. "/file-list.txt"
  local parent    = vim.fn.shellescape(vim.fn.fnamemodify(path, ":h"))

  local cmd_list = "find " .. vim.fn.shellescape(path)
                   .. " -not -path '*/.git/*' > " .. vim.fn.shellescape(list_path)
  local cmd_arc  = "tar --exclude=" .. vim.fn.shellescape(path .. "/.git")
                   .. " -czf " .. vim.fn.shellescape(out_path)
                   .. " -C " .. parent
                   .. " " .. vim.fn.shellescape(name)

  platform.run_shell(cmd_list, function(ok1, _, err1)
    if not ok1 then on_complete(false, "file listing failed: " .. err1); return end
    platform.run_shell(cmd_arc, function(ok2, _, err2)
      if not ok2 then on_complete(false, "tar failed: " .. err2)
      else            on_complete(true,  "compressed → " .. out_path) end
    end)
  end)
end

function engines.zip(path, outdir, on_complete)
  local name      = vim.fn.fnamemodify(path, ":t")
  local out_path  = outdir .. "/" .. name .. ".zip"
  local list_path = outdir .. "/file-list.txt"
  local parent    = vim.fn.shellescape(vim.fn.fnamemodify(path, ":h"))

  local cmd_list = "find " .. vim.fn.shellescape(path)
                   .. " -not -path '*/.git/*' > " .. vim.fn.shellescape(list_path)
  -- zip --exclude uses shell-glob paths relative to the source root
  local cmd_arc  = "cd " .. parent
                   .. " && zip -r " .. vim.fn.shellescape(out_path)
                   .. " " .. vim.fn.shellescape(name)
                   .. " --exclude '*.git/*'"

  platform.run_shell(cmd_list, function(ok1, _, err1)
    if not ok1 then on_complete(false, "file listing failed: " .. err1); return end
    platform.run_shell(cmd_arc, function(ok2, _, err2)
      if not ok2 then on_complete(false, "zip failed: " .. err2)
      else            on_complete(true,  "compressed → " .. out_path) end
    end)
  end)
end

function engines.powershell(path, outdir, on_complete)
  local name      = vim.fn.fnamemodify(path, ":t")
  local out_path  = outdir .. "\\" .. name .. ".zip"
  local list_path = outdir .. "\\file-list.txt"

  local cmd_list = table.concat({
    "Get-ChildItem -Recurse -Path '" .. path .. "'",
    "| Where-Object { $_.FullName -notlike '*\\.git\\*' }",
    "| Select-Object -ExpandProperty FullName",
    "| Out-File -FilePath '" .. list_path .. "'",
  }, " ")
  local cmd_arc = "Compress-Archive -Path '" .. path
                  .. "' -DestinationPath '" .. out_path .. "' -Force"

  platform.run_shell(cmd_list, function(ok1, _, err1)
    if not ok1 then on_complete(false, "file listing failed: " .. err1); return end
    platform.run_shell(cmd_arc, function(ok2, _, err2)
      if not ok2 then on_complete(false, "Compress-Archive failed: " .. err2)
      else            on_complete(true,  "compressed → " .. out_path) end
    end)
  end)
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

---Compress `path` using the engine and outdir from `cfg`.
---Runs asynchronously; calls on_complete(success, message) when done.
---@param path        string  Absolute directory to compress.
---@param cfg         table   The compress config block.
---@param on_complete fun(success: boolean, message: string)
function M.compress(path, cfg, on_complete)
  local engine = cfg.engine or "auto"
  if engine == "auto" then
    engine = platform.is_windows() and "powershell" or "tar"
  end

  local runner = engines[engine]
  if not runner then
    on_complete(false, "unknown compress engine: '" .. engine
      .. "' — valid: auto | tar | zip | powershell")
    return
  end

  local outdir, err = resolve_outdir(path, cfg.outdir or "")
  if not outdir then
    on_complete(false, err or "unknown error")
    return
  end

  notify.info(string.format("engine=%s  out=%s", engine, outdir))
  runner(path, outdir, on_complete)
end

return M
