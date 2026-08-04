---@module 'insights.conflicts'
--- Unresolved-merge-conflict report: asks git for files in the "unmerged"
--- state and puts them in the quickfix list. A conflict scan is a
--- project-health report, same category as the symbol and metric reports.

local notify = require("insights.util.notify").create("[insights.conflicts]")

local M = {}

local fn = vim.fn

---@internal
---Run a git command and return its stdout only.
---
---`vim.system` rather than `systemlist`, because the latter folds stderr into
---its result: git's "LF will be replaced by CRLF" warnings would then be
---parsed as conflicting file names.
---@param cmd string[]
---@return table  # { code, stdout, stderr }
local function run(cmd)
  return vim.system(cmd, { text = true }):wait()
end

---@internal
---Is the cwd inside a git work tree?
---@param git_cmd string
---@return boolean
local function in_git_repo(git_cmd)
  local ok, res = pcall(run, { git_cmd, "rev-parse", "--is-inside-work-tree" })
  return ok and res.code == 0
end

---List files git reports as unmerged.
---@param cfg Insights.ConflictsConfig
---@return string[]|nil files, string|nil err
function M.list(cfg)
  local git = cfg.git_cmd or "git"
  if fn.executable(git) ~= 1 then
    return nil, "git not executable: " .. git
  end
  if not in_git_repo(git) then
    return nil, "not inside a git repository"
  end

  local ok, res = pcall(run, { git, "diff", "--name-only", "--diff-filter=" .. (cfg.diff_filter or "U") })
  if not ok then
    return nil, "git diff failed: " .. tostring(res)
  end
  if res.code ~= 0 then
    return nil, "git diff failed: " .. vim.trim(res.stderr or "")
  end

  local files = {}
  for _, line in ipairs(vim.split(res.stdout or "", "\n", { plain = true })) do
    line = vim.trim(line)
    if line ~= "" then
      files[#files + 1] = line
    end
  end
  return files, nil
end

---Scan for conflicts and populate the quickfix list.
---@param opts { silent?: boolean }|nil  silent = no notification when clean
---@return integer count
function M.run(opts)
  opts = opts or {}
  local cfg = require("insights.config").get().conflicts or {}

  local files, err = M.list(cfg)
  if not files then
    if not opts.silent then
      notify.warn(err or "conflict scan failed")
    end
    return 0
  end

  if #files == 0 then
    if not opts.silent then
      notify.info("no unresolved conflicts")
    end
    return 0
  end

  local qf = {}
  for i, file in ipairs(files) do
    qf[i] = { filename = file, lnum = 1, col = 1, text = "Git conflict" }
  end
  fn.setqflist(qf, "r")
  fn.setqflist({}, "a", { title = "Insights: git conflicts" })

  if cfg.open_qf ~= false then
    vim.cmd("copen")
  end
  if cfg.notify ~= false then
    notify.warn(("%d unresolved conflict%s:\n%s")
      :format(#files, #files == 1 and "" or "s", table.concat(files, "\n")))
  end

  return #files
end

return M
