---@module 'project_insight.bindings.autocmds'
--- The plugin's only automatic triggers. Everything else is invoked
--- explicitly via :ProjectInsight or a configured keymap.
---
---   conflicts   — populate the quickfix list with unresolved conflicts
---   unimported  — check component references on write
---   devserver   — notice dev servers in terminals, kill them on exit
---
--- Each is gated by its `enable` key and registers nothing when disabled.
local M = {}

local api = vim.api

---Claim (and clear) a group. Clearing on every setup() makes re-running it
---idempotent, and makes `enable = false` tear down a previously enabled
---feature instead of leaving its autocmds behind.
---@param name string
---@return integer
local function augroup(name)
  return api.nvim_create_augroup("ProjectInsight_" .. name, { clear = true })
end

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

---@param cfg ProjectInsight.ConflictsConfig
local function setup_conflicts(cfg)
  local grp = augroup("conflicts")
  if not (cfg and cfg.enable) then
    return
  end
  api.nvim_create_autocmd(norm_events(cfg.events, { "VimEnter" }), {
    group = grp,
    callback = function()
      require("project_insight.conflicts").run({ silent = true })
    end,
    desc = "Project-Insight: quickfix unresolved git conflicts",
  })
end

---@param cfg ProjectInsight.UnimportedConfig
local function setup_unimported(cfg)
  local grp = augroup("unimported")
  if not (cfg and cfg.enable) then
    return
  end
  api.nvim_create_autocmd(norm_events(cfg.events, { "BufWritePost" }), {
    group = grp,
    callback = function(ev)
      local unimported = require("project_insight.unimported")
      if unimported.handles_filetype(vim.bo[ev.buf].filetype) then
        unimported.run(ev.buf, { silent = true })
      end
    end,
    desc = "Project-Insight: check for used-but-unimported components",
  })
end

---@param cfg ProjectInsight.DevserverConfig
local function setup_devserver(cfg)
  local grp = augroup("devserver")
  if not (cfg and cfg.enable) then
    return
  end
  local devserver = require("project_insight.devserver")

  -- The command a terminal was opened with (`:terminal npm run dev`).
  api.nvim_create_autocmd("TermOpen", {
    group = grp,
    callback = function(ev)
      local chan = vim.b[ev.buf].terminal_job_id
      if chan then
        devserver.consider(chan, devserver.chan_cmd(chan, ev.buf))
      end
    end,
    desc = "Project-Insight: detect dev server in a new terminal",
  })

  -- A command typed into an already-open shell only shows up when the program
  -- sets the terminal title (OSC 0/2), which lands here on Neovim 0.10+.
  api.nvim_create_autocmd("TermRequest", {
    group = grp,
    callback = function(ev)
      local chan = vim.b[ev.buf].terminal_job_id
      if chan then
        devserver.consider(chan, devserver.chan_cmd(chan, ev.buf))
      end
    end,
    desc = "Project-Insight: detect dev server from terminal title",
  })

  api.nvim_create_autocmd("VimLeavePre", {
    group = grp,
    callback = function()
      devserver.kill_all()
    end,
    desc = "Project-Insight: kill tracked dev servers on exit",
  })
end

---@param cfg ProjectInsightConfig|nil  defaults to the merged config
function M.setup(cfg)
  cfg = cfg or require("project_insight.config").get()
  setup_conflicts(cfg.conflicts)
  setup_unimported(cfg.unimported)
  setup_devserver(cfg.devserver)
end

return M
