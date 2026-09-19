---@module 'insights.bindings.autocmds'
--- The plugin's only automatic triggers. Everything else is invoked
--- explicitly via :Insights or a configured keymap.
---
---   conflicts   — populate the quickfix list with unresolved conflicts
---   unimported  — check component references on write
---   devserver   — notice dev servers in terminals, kill them on exit
---   todos       — colour annotation keywords in the lines on screen
---
--- Each is gated by its `enable` key and registers nothing when disabled.
local M = {}

local autocmd = require("lib.nvim.bindings.autocmd")

---@internal
---Claim (and clear) a group. Clearing on every setup() makes re-running it
---idempotent, and makes `enable = false` tear down a previously enabled
---feature instead of leaving its autocmds behind.
---@param name string
---@return integer
local function augroup(name)
  return autocmd.group("Insights_" .. name, true)
end

---@internal
---Accept a string or a list of events; fall back to `default`.
---An explicitly empty list (`events = {}`) is a deliberate opt-out and must
---stay empty here -- only a missing/non-table value falls back.
---@param events string|string[]|nil
---@param default string[]
---@return string[]
local function norm_events(events, default)
  if type(events) == "string" then
    return { events }
  end
  if type(events) == "table" then
    return events
  end
  return default
end

---@internal
---@param cfg Insights.ConflictsConfig
local function setup_conflicts(cfg)
  local grp = augroup("conflicts")
  if not (cfg and cfg.enable) then
    return
  end
  local events = norm_events(cfg.events, { "VimEnter" })
  if #events == 0 then
    -- `events = {}` opts out of automatic scanning entirely; only
    -- `:Insights conflicts` still runs it.
    return
  end
  -- `run_async`, not `run`: nobody asked for this scan, so it must not hold up
  -- the editor. The blocking version does two git spawns with `:wait()`, which
  -- on the default VimEnter event cost ~120ms of main-loop block on Windows.
  autocmd.create(events, function()
    require("insights.conflicts").run_async({ silent = true })
  end, {
    group = grp,
    desc = "Insights: quickfix unresolved git conflicts",
  })
end

---@internal
---@param cfg Insights.UnimportedConfig
local function setup_unimported(cfg)
  local grp = augroup("unimported")
  if not (cfg and cfg.enable) then
    return
  end
  local events = norm_events(cfg.events, { "BufWritePost" })
  if #events == 0 then
    -- `events = {}` opts out of the automatic on-write check.
    return
  end
  autocmd.create(events, function(ev)
    local unimported = require("insights.unimported")
    if unimported.handles_filetype(vim.bo[ev.buf].filetype) then
      unimported.run(ev.buf, { silent = true })
    end
  end, {
    group = grp,
    desc = "Insights: check for used-but-unimported components",
  })
end

---@internal
---@param cfg Insights.DevserverConfig
local function setup_devserver(cfg)
  local grp = augroup("devserver")
  if not (cfg and cfg.enable) then
    return
  end
  local devserver = require("insights.devserver")

  -- The command a terminal was opened with (`:terminal npm run dev`).
  autocmd.create("TermOpen", function(ev)
    local chan = vim.b[ev.buf].terminal_job_id
    if chan then
      devserver.consider(chan, devserver.chan_cmd(chan, ev.buf))
    end
  end, {
    group = grp,
    desc = "Insights: detect dev server in a new terminal",
  })

  -- A command typed into an already-open shell only shows up when the program
  -- sets the terminal title (OSC 0/2), which lands here on Neovim 0.10+.
  autocmd.create("TermRequest", function(ev)
    local chan = vim.b[ev.buf].terminal_job_id
    if chan then
      devserver.consider(chan, devserver.chan_cmd(chan, ev.buf))
    end
  end, {
    group = grp,
    desc = "Insights: detect dev server from terminal title",
  })

  autocmd.create("VimLeavePre", function()
    devserver.kill_all()
  end, {
    group = grp,
    desc = "Insights: kill tracked dev servers on exit",
  })
end

---@internal
---@param cfg Insights.TodosConfig
local function setup_todos(cfg)
  local grp = augroup("todos")
  local highlight = require("insights.todos.highlight")
  if not (cfg and cfg.enable and cfg.highlight and cfg.highlight.enable) then
    -- A disabled feature must also take back what an earlier setup() placed:
    -- the groups are cleared above, the extmarks here.
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      highlight.clear(buf)
    end
    return
  end

  highlight.setup_groups()

  -- Showing a buffer, or attaching a parser to it, is a full re-scan of the
  -- visible range right away -- there is nothing to debounce, nothing was
  -- on screen a moment ago.
  autocmd.create({ "BufWinEnter", "FileType" }, function(ev)
    highlight.refresh(ev.buf)
  end, {
    group = grp,
    desc = "Insights: highlight annotation keywords (buffer shown)",
  })

  -- A scroll exposes lines the last pass did not cover; a change may have
  -- added or removed a keyword. Debounced per buffer so a held-down key does
  -- not scan on every repeat.
  autocmd.create({ "TextChanged", "TextChangedI", "WinScrolled" }, function(ev)
    highlight.schedule(ev.buf)
  end, {
    group = grp,
    desc = "Insights: highlight annotation keywords (buffer changed or scrolled)",
  })

  autocmd.create({ "BufUnload", "BufWipeout" }, function(ev)
    highlight.clear(ev.buf)
  end, {
    group = grp,
    desc = "Insights: drop annotation highlight state with the buffer",
  })

  -- setup() may run after buffers are already on screen (a lazy-loaded
  -- plugin, or a re-run); those never see BufWinEnter, so scan them now.
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    highlight.refresh(vim.api.nvim_win_get_buf(win))
  end
end

---@param cfg InsightsConfig|nil  defaults to the merged config
function M.setup(cfg)
  cfg = cfg or require("insights.config").get()
  setup_conflicts(cfg.conflicts)
  setup_unimported(cfg.unimported)
  setup_devserver(cfg.devserver)
  setup_todos(cfg.todos)
end

return M
