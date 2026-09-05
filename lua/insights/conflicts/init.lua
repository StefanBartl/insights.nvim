---@module 'insights.conflicts'
--- Unresolved-merge-conflict report: asks git for files in the "unmerged"
--- state and puts them in the quickfix list. A conflict scan is a
--- project-health report, same category as the symbol and metric reports.

local notify = require("insights.util.notify").create("[insights.conflicts]")

-- Memoized PATH lookup. `vim.fn.executable()` walks every $PATH entry and stats
-- candidates; on Windows each stat also passes the AV filter driver, so a single
-- call costs milliseconds. This is on the VimEnter path, so it is worth the
-- indirection -- and lib.nvim.cross is already used elsewhere in this plugin.
local executable = require("lib.nvim.cross.executable")
local list = require("lib.nvim.ui.list")

local M = {}

---@internal
---Run a git command and return its stdout only.
---
---`vim.system` rather than `systemlist`, because the latter folds stderr into
---its result: git's "LF will be replaced by CRLF" warnings would then be
---parsed as conflicting file names.
---
---`cwd` is passed explicitly (snapshotted once by the caller) rather than
---left to `vim.system`'s own default of the editor's current directory: `run`
---is called twice per scan (`rev-parse` then `diff`), and pinning the value
---once keeps both calls scoped to the same repo even if something changes
---the global cwd in between.
---@param cmd string[]
---@param cwd string
---@return table  # { code, stdout, stderr }
local function run(cmd, cwd)
  return vim.system(cmd, { text = true, cwd = cwd }):wait()
end

---@internal
---Is the cwd inside a git work tree?
---@param git_cmd string
---@param cwd string
---@return boolean
local function in_git_repo(git_cmd, cwd)
  local ok, res = pcall(run, { git_cmd, "rev-parse", "--is-inside-work-tree" }, cwd)
  return ok and res.code == 0
end

---@internal
---Turn `git diff --name-only` output into a file list.
---@param stdout string|nil
---@return string[]
local function parse_files(stdout)
  local files = {}
  for _, line in ipairs(vim.split(stdout or "", "\n", { plain = true })) do
    line = vim.trim(line)
    if line ~= "" then
      files[#files + 1] = line
    end
  end
  return files
end

---List files git reports as unmerged.
---@param cfg Insights.ConflictsConfig
---@return string[]|nil files, string|nil err
function M.list(cfg)
  local git = cfg.git_cmd or "git"
  local cwd = vim.fn.getcwd()
  if not executable.exists(git) then
    return nil, "git not executable: " .. git
  end
  if not in_git_repo(git, cwd) then
    return nil, "not inside a git repository"
  end

  local ok, res = pcall(
    run,
    { git, "diff", "--name-only", "--diff-filter=" .. (cfg.diff_filter or "U") },
    cwd
  )
  if not ok then
    return nil, "git diff failed: " .. tostring(res)
  end
  if res.code ~= 0 then
    return nil, "git diff failed: " .. vim.trim(res.stderr or "")
  end

  return parse_files(res.stdout), nil
end

---@internal
---Report a finished scan: quickfix list, `:copen`, notification.
---Shared by the blocking and the non-blocking entry point.
---@param files string[]|nil
---@param err string|nil
---@param cfg Insights.ConflictsConfig
---@param opts { silent?: boolean }
---@return integer count
local function report(files, err, cfg, opts)
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
  list.qf(qf, "Insights: git conflicts", {
    -- Replaces rather than pushes: a re-scan is an update of this report, not
    -- a second one to page back through.
    action = "r",
    open = cfg.open_qf ~= false,
  })
  if cfg.notify ~= false then
    notify.warn(
      ("%d unresolved conflict%s:\n%s"):format(
        #files,
        #files == 1 and "" or "s",
        table.concat(files, "\n")
      )
    )
  end

  return #files
end

---Scan for conflicts and populate the quickfix list. Blocks on two git calls.
---
---Use this when someone explicitly asked for a scan (`:Insights conflicts`,
---`insights.run_conflicts()`) and is waiting for the answer. For a scan nobody
---asked for -- the `VimEnter` autocmd above all -- use `run_async`, which does
---the same work without holding up the editor.
---@param opts { silent?: boolean }|nil  silent = no notification when clean
---@return integer count
function M.run(opts)
  opts = opts or {}
  local cfg = require("insights.config").get().conflicts or {}
  local files, err = M.list(cfg)
  return report(files, err, cfg, opts)
end

---Non-blocking counterpart to `run`.
---
---The two git calls go through `vim.system`'s callback form instead of
---`:wait()`. On the `VimEnter` path that matters: the blocking version was
---measured at ~120ms of main-loop block on Windows (two git spawns with an EDR
---scanner in the path), the largest single item in one config's startup.
---@param opts { silent?: boolean }|nil
---@param on_done fun(count: integer)|nil  # called once the report is applied
---@return nil
function M.run_async(opts, on_done)
  opts = opts or {}
  local cfg = require("insights.config").get().conflicts or {}
  local git = cfg.git_cmd or "git"
  -- Snapshotted once: the two spawns below are separated by a scheduled
  -- callback (a full event-loop turn), so without this the rev-parse and the
  -- diff could end up scoped to different directories if something else
  -- changes the global cwd in between.
  local cwd = vim.fn.getcwd()

  local function finish(files, err)
    local count = report(files, err, cfg, opts)
    if on_done then
      on_done(count)
    end
  end

  if not executable.exists(git) then
    return finish(nil, "git not executable: " .. git)
  end

  ---@param cmd string[]
  ---@param cb fun(res: table)
  local function spawn(cmd, cb)
    local ok = pcall(vim.system, cmd, { text = true, cwd = cwd }, function(res)
      vim.schedule(function()
        cb(res)
      end)
    end)
    if not ok then
      vim.schedule(function()
        finish(nil, "git failed to spawn: " .. table.concat(cmd, " "))
      end)
    end
  end

  spawn({ git, "rev-parse", "--is-inside-work-tree" }, function(res)
    if res.code ~= 0 then
      return finish(nil, "not inside a git repository")
    end

    spawn(
      { git, "diff", "--name-only", "--diff-filter=" .. (cfg.diff_filter or "U") },
      function(diff)
        if diff.code ~= 0 then
          return finish(nil, "git diff failed: " .. vim.trim(diff.stderr or ""))
        end
        finish(parse_files(diff.stdout), nil)
      end
    )
  end)
end

return M
