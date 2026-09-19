-- TESTS/conflicts_spec.lua — the unresolved-merge-conflict scan.
--
-- **No git process is started.** Both entry points go through `vim.system`,
-- which is replaced for the duration by a fake that answers whatever the case
-- under test needs -- including the answers a real repository would rarely
-- give (git missing, not a work tree, a diff that fails). `lib.nvim.ui.list`
-- is replaced too, so the quickfix list is captured rather than populated and
-- `:copen` never runs.
--
-- The stdout/stderr split is the reason the module uses `vim.system` at all:
-- `systemlist` folds git's "LF will be replaced by CRLF" warnings into its
-- result, and they would be parsed as conflicting file names.

return function(H)
  local config = require("insights.config")

  -- Restored by name at the end, not `pairs(saved)`: storing `nil` in a Lua
  -- table does not create a key, so a module not yet loaded before this spec
  -- would silently never get its `package.loaded` slot cleared back to nil,
  -- leaking this spec's stub into every later spec's `require`.
  local replaced_modules = { "lib.nvim.ui.list", "lib.nvim.cross.executable", "insights.conflicts" }
  local saved = {}
  for _, name in ipairs(replaced_modules) do
    saved[name] = package.loaded[name]
  end

  local qf_calls = {}
  package.loaded["lib.nvim.ui.list"] = {
    qf = function(items, title, opts)
      qf_calls[#qf_calls + 1] = { items = items, title = title, opts = opts }
    end,
  }

  local git_present = true
  package.loaded["lib.nvim.cross.executable"] = {
    exists = function()
      return git_present
    end,
  }

  package.loaded["insights.conflicts"] = nil
  local conflicts = require("insights.conflicts")

  -- The fake git. `answers` is consulted per sub-command.
  local answers, seen
  local real_system = vim.system

  ---@param cmd string[]
  ---@return table
  local function answer_for(cmd)
    local sub = cmd[2]
    return answers[sub] or { code = 0, stdout = "", stderr = "" }
  end

  vim.system = function(cmd, opts, cb)
    seen[#seen + 1] = { cmd = cmd, cwd = opts and opts.cwd }
    local res = answer_for(cmd)
    if cb then
      vim.schedule(function()
        cb(res)
      end)
      return { wait = function() end }
    end
    return {
      wait = function()
        return res
      end,
    }
  end

  local function reset()
    qf_calls, seen = {}, {}
    answers = {
      ["rev-parse"] = { code = 0, stdout = "true\n", stderr = "" },
      ["diff"] = { code = 0, stdout = "a.txt\nb.txt\n", stderr = "" },
    }
    git_present = true
  end

  local ok_body, err_body = pcall(function()
    config.setup({ conflicts = { enable = true, notify = false } })

    -- ── list ───────────────────────────────────────────────────────────────
    reset()
    local files, err = conflicts.list(config.get().conflicts)
    H.eq(err, nil, "a clean run has no error")
    H.eq(#files, 2, "one entry per unmerged file")
    H.eq(files[1], "a.txt", "in the order git printed them")
    H.eq(seen[1].cmd[2], "rev-parse", "the work-tree check runs first")
    H.eq(seen[2].cmd[2], "diff", "then the diff")
    H.ok(vim.tbl_contains(seen[2].cmd, "--diff-filter=U"), "asking for unmerged files")
    H.ok(vim.tbl_contains(seen[2].cmd, "--name-only"), "and only their names")
    H.eq(seen[1].cwd, seen[2].cwd, "both calls are scoped to the same snapshotted directory")

    -- A blank line in git's output is not a file name.
    reset()
    answers["diff"] = { code = 0, stdout = "a.txt\n\n  \nb.txt\n", stderr = "" }
    H.eq(#conflicts.list(config.get().conflicts), 2, "blank lines are not file names")

    reset()
    answers["diff"] = { code = 0, stdout = "", stderr = "" }
    H.eq(#conflicts.list(config.get().conflicts), 0, "no output is no conflicts, and not an error")

    -- The configured filter reaches the command.
    reset()
    conflicts.list({ git_cmd = "git", diff_filter = "M" })
    H.ok(vim.tbl_contains(seen[2].cmd, "--diff-filter=M"), "a configured diff filter is used")

    -- ERR-22 follow-up: `cfg.diff_filter or "U"` alone only catches nil/false
    -- -- a truthy non-string (e.g. `diff_filter = true`) survives it and used
    -- to crash the `"--diff-filter=" .. ...` concatenation. Must degrade to
    -- the default "U" instead.
    reset()
    ---@diagnostic disable-next-line: assign-type-mismatch
    local list_ok, list_files = pcall(conflicts.list, { git_cmd = "git", diff_filter = true })
    H.ok(list_ok, "a wrong-type diff_filter does not crash list()")
    H.eq(#list_files, 2, "and the scan still runs")
    H.ok(vim.tbl_contains(seen[2].cmd, "--diff-filter=U"), "falling back to the default filter")

    reset()
    conflicts.list({ git_cmd = "my-git" })
    H.eq(seen[1].cmd[1], "my-git", "and a configured git binary")

    -- Failure modes ---------------------------------------------------------
    reset()
    git_present = false
    local no_git, no_git_err = conflicts.list({ git_cmd = "git" })
    H.eq(no_git, nil, "without git there is nothing to list")
    H.contains(no_git_err or "", "git not executable", "and an error saying so")
    H.eq(#seen, 0, "and nothing is spawned")

    reset()
    answers["rev-parse"] = { code = 128, stdout = "", stderr = "fatal: not a git repository" }
    local outside, outside_err = conflicts.list({ git_cmd = "git" })
    H.eq(outside, nil, "outside a repository there is nothing to list")
    H.eq(outside_err, "not inside a git repository", "with that as the reason")
    H.eq(#seen, 1, "and the diff is never attempted")

    reset()
    answers["diff"] = { code = 1, stdout = "", stderr = "something broke" }
    local failed, failed_err = conflicts.list({ git_cmd = "git" })
    H.eq(failed, nil, "a failing diff has no answer")
    H.contains(failed_err or "", "git diff failed", "and reports the failure")
    H.contains(failed_err or "", "something broke", "quoting git's stderr")

    -- ── run ────────────────────────────────────────────────────────────────
    reset()
    local count = conflicts.run()
    H.eq(count, 2, "run reports how many conflicts it found")
    H.eq(#qf_calls, 1, "and fills the quickfix list once")
    H.eq(#qf_calls[1].items, 2, "with one item per file")
    H.eq(qf_calls[1].items[1].filename, "a.txt", "naming the file")
    H.eq(qf_calls[1].items[1].lnum, 1, "at the top of it")
    H.eq(qf_calls[1].items[1].text, "Git conflict", "with a fixed description")
    H.contains(qf_calls[1].title, "Insights", "under a titled list")
    H.eq(qf_calls[1].opts.action, "r", "replacing the previous scan rather than pushing a second")
    H.eq(qf_calls[1].opts.open, true, "and opening it by default")

    config.setup({ conflicts = { enable = true, notify = false, open_qf = false } })
    reset()
    conflicts.run()
    H.eq(qf_calls[1].opts.open, false, "open_qf = false leaves the list closed")
    config.setup({ conflicts = { enable = true, notify = false } })

    -- A clean tree touches the quickfix list at all: replacing it with an
    -- empty list would clear a list the user is reading.
    reset()
    answers["diff"] = { code = 0, stdout = "", stderr = "" }
    H.eq(conflicts.run(), 0, "a clean tree reports zero")
    H.eq(#qf_calls, 0, "and does not touch the quickfix list")

    reset()
    git_present = false
    H.eq(conflicts.run({ silent = true }), 0, "a failed scan reports zero")
    H.eq(#qf_calls, 0, "and populates nothing")

    -- ── run_async ──────────────────────────────────────────────────────────
    reset()
    local async_count
    conflicts.run_async({}, function(c)
      async_count = c
    end)
    H.ok(
      vim.wait(2000, function()
        return async_count ~= nil
      end),
      "run_async calls back"
    )
    H.eq(async_count, 2, "with the same count")
    H.eq(#qf_calls, 1, "and the same quickfix list")
    H.eq(seen[1].cwd, seen[2].cwd, "both spawns scoped to one snapshotted directory")

    reset()
    git_present = false
    async_count = nil
    conflicts.run_async({ silent = true }, function(c)
      async_count = c
    end)
    H.ok(
      vim.wait(2000, function()
        return async_count ~= nil
      end),
      "the missing-git path calls back too"
    )
    H.eq(async_count, 0, "with nothing found")
    H.eq(#seen, 0, "having spawned nothing")

    reset()
    answers["rev-parse"] = { code = 128, stdout = "", stderr = "" }
    async_count = nil
    conflicts.run_async({ silent = true }, function(c)
      async_count = c
    end)
    H.ok(
      vim.wait(2000, function()
        return async_count ~= nil
      end),
      "and so does the not-a-repository path"
    )
    H.eq(async_count, 0, "with nothing found")
    H.eq(#seen, 1, "and no diff attempted")

    reset()
    answers["diff"] = { code = 1, stdout = "", stderr = "boom" }
    async_count = nil
    conflicts.run_async({ silent = true }, function(c)
      async_count = c
    end)
    H.ok(
      vim.wait(2000, function()
        return async_count ~= nil
      end),
      "a failing diff still calls back"
    )
    H.eq(async_count, 0, "reporting nothing found")

    -- run_async with no callback must not raise: that is how the VimEnter
    -- autocmd calls it.
    reset()
    H.ok(pcall(conflicts.run_async, { silent = true }), "a callback is optional")
    vim.wait(200)

    -- ERR-22 follow-up, run_async's own diff-filter call site: the same
    -- wrong-type diff_filter must not crash the async path either, since it
    -- builds the same command through a separate `spawn()` call.
    config.setup({ conflicts = { enable = true, notify = false, diff_filter = true } })
    reset()
    local async_ok, async_result
    local ok_async_call = pcall(conflicts.run_async, {}, function(c)
      async_result = c
    end)
    H.ok(ok_async_call, "a wrong-type diff_filter does not crash run_async()")
    async_ok = vim.wait(2000, function()
      return async_result ~= nil
    end)
    H.ok(async_ok, "and it still calls back")
    H.eq(async_result, 2, "falling back to the default filter, same as the sync path")
    H.ok(vim.tbl_contains(seen[2].cmd, "--diff-filter=U"), "using the default filter on the wire")
    config.setup({ conflicts = { enable = true, notify = false } })
  end)

  vim.system = real_system
  for _, name in ipairs(replaced_modules) do
    package.loaded[name] = saved[name]
  end
  config.setup({})

  if not ok_body then
    error(err_body, 0)
  end
end
