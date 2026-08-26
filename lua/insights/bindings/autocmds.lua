---@module 'insights.bindings.autocmds'
--- The plugin's only automatic triggers. Everything else is invoked
--- explicitly via :Insights or a configured keymap.
---
---   conflicts   — populate the quickfix list with unresolved conflicts
---   unimported  — check component references on write
---   devserver   — notice dev servers in terminals, kill them on exit
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
---@param events string|string[]|nil
---@param default string[]
---@return string[]
local function norm_events(events, default)
  if type(events) == "string" then
    return { events }
  end
  if type(events) == "table" and #events > 0 then
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
  -- `run_async`, not `run`: nobody asked for this scan, so it must not hold up
  -- the editor. The blocking version does two git spawns with `:wait()`, which
  -- on the default VimEnter event cost ~120ms of main-loop block on Windows.
  autocmd.create(norm_events(cfg.events, { "VimEnter" }), function()
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
  autocmd.create(norm_events(cfg.events, { "BufWritePost" }), function(ev)
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

---@param cfg InsightsConfig|nil  defaults to the merged config
function M.setup(cfg)
  cfg = cfg or require("insights.config").get()
  setup_conflicts(cfg.conflicts)
  setup_unimported(cfg.unimported)
  setup_devserver(cfg.devserver)
end

return M
