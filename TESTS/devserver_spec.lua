-- TESTS/devserver_spec.lua — insights.devserver: the pattern match that decides
-- whether a terminal job is a dev server worth tracking, and the tracking
-- ledger itself.
--
-- Only the pure parts are covered here. `kill_tree` spawns a real process
-- tree and belongs to a manual pass, not to a headless suite.

return function(H)
  local devserver = require("insights.devserver")

  -- match ---------------------------------------------------------------------
  local patterns = { "npm run dev", "vite", "cargo watch" }

  H.eq(devserver.match("npm run dev", patterns), "npm run dev", "an exact command matches")
  H.eq(
    devserver.match("cd app && npm run dev -- --port 3000", patterns),
    "npm run dev",
    "and so does one with the pattern somewhere inside it"
  )
  H.eq(devserver.match("VITE_X=1 vite", patterns), "vite", "the first matching pattern is returned")

  -- Case-insensitive on purpose: a shell command's case is not something the
  -- user should have to predict when writing the pattern list.
  H.eq(devserver.match("NPM RUN DEV", patterns), "npm run dev", "matching ignores case")

  -- Non-matches ---------------------------------------------------------------
  H.eq(devserver.match("git status", patterns), nil, "an unrelated command does not match")
  H.eq(devserver.match("", patterns), nil, "an empty command matches nothing")
  -- Both calls hand it the wrong type on purpose: refusing those is the
  -- behaviour under test.
  ---@diagnostic disable-next-line: param-type-mismatch
  H.eq(devserver.match(nil, patterns), nil, "and neither does a nil one")
  H.eq(devserver.match("npm run dev", {}), nil, "an empty pattern list matches nothing")
  ---@diagnostic disable-next-line: param-type-mismatch
  H.eq(devserver.match("npm run dev", nil), nil, "nor a nil one")

  -- Matching is literal, not a Lua pattern ------------------------------------
  -- A pattern list is user configuration, and `.` or `-` in a command name
  -- would otherwise quietly mean something else.
  H.eq(devserver.match("npm-run-dev", { "npm.run.dev" }), nil, "dots are literal, not wildcards")

  -- The ledger ----------------------------------------------------------------
  -- `tracked()` is keyed by channel, not a list, so count the pairs.
  local function count()
    local n = 0
    for _ in pairs(devserver.tracked()) do
      n = n + 1
    end
    return n
  end

  devserver.reset()
  H.eq(count(), 0, "reset empties the ledger")

  -- `track` resolves the channel to a real OS pid, so a fabricated channel
  -- number records nothing -- an entry without a pid could not be killed
  -- later, and a silently-half-tracked server is worse than an untracked one.
  devserver.track(99999, "npm run dev", true)
  H.eq(count(), 0, "a channel with no job behind it is not recorded")

  -- The stand-in dev server stays alive until the spec stops it: no `-c qa!`,
  -- which would only make its lifetime a race against the assertions. It is
  -- stopped and reaped below even when an assertion raises, so no process
  -- outlives the file.
  local chan = vim.fn.jobstart({ vim.v.progpath, "--headless", "-u", "NONE" })
  H.ok(chan > 0, "a real job started")
  local ok_body, err_body = pcall(function()
    devserver.track(chan, "npm run dev", true)
    H.eq(count(), 1, "a real channel is recorded")

    local entry = devserver.tracked()[chan]
    H.ok(entry, "keyed by the channel it came from")
    H.eq(entry.cmd, "npm run dev", "the command is stored for the prompt text")
    H.eq(entry.kill_on_exit, true, "and so is the decision the user made")
    H.ok(type(entry.pid) == "number", "with the OS pid VimLeavePre will need")

    -- tracked() hands out a copy, not the live ledger (ERR-54): a caller that
    -- sorts or otherwise mutates its result -- the natural thing to do with a
    -- list for display -- must not corrupt what kill_all() reads later.
    local snapshot = devserver.tracked()
    snapshot[chan].kill_on_exit = false
    snapshot[chan] = nil
    H.eq(
      devserver.tracked()[chan].kill_on_exit,
      true,
      "mutating a snapshot leaves the ledger untouched"
    )

    devserver.reset()
    H.eq(count(), 0, "and reset clears it again")
  end)

  devserver.reset()
  pcall(vim.fn.jobstop, chan)
  pcall(vim.fn.jobwait, { chan }, 2000)
  if not ok_body then
    error(err_body, 0)
  end
end
