---@module 'insights.devserver'
--- Dev-server lifecycle: notice when a terminal Neovim owns starts a dev
--- server, ask once whether it should be killed when Neovim exits, and honour
--- the answer on VimLeavePre.
---
--- Only terminals started by this Neovim instance are tracked. A server
--- running in another shell is deliberately out of scope: this plugin kills
--- what it can account for, never everything on the machine matching a name.
---
--- The prompt uses lib.nvim's ui.kit confirm dialog (hard dependency).

local notify = require("insights.util.notify").create("[insights.devserver]")

local M = {}

local api, fn = vim.api, vim.fn

---Terminals we have decided about: [chan] = { pid, cmd, kill_on_exit }
---@type table<integer, { pid: integer, cmd: string, kill_on_exit: boolean }>
local tracked = {}

---Channels already prompted for, so a title change cannot re-ask.
---@type table<integer, boolean>
local asked = {}

---@return table<integer, { pid: integer, cmd: string, kill_on_exit: boolean }>
function M.tracked()
  return tracked
end

---Reset all tracking state (used by tests).
function M.reset()
  tracked, asked = {}, {}
end

---First configured pattern matching `cmd`, if any.
---@param cmd string
---@param patterns string[]
---@return string|nil
function M.match(cmd, patterns)
  if not cmd or cmd == "" then
    return nil
  end
  for _, pat in ipairs(patterns or {}) do
    if cmd:lower():find(pat:lower(), 1, true) then
      return pat
    end
  end
  return nil
end

---Kill the process tree rooted at `pid`, synchronously.
---
---Runs on VimLeavePre, so it must complete before Neovim exits — hence
---`:wait()` rather than a callback.
---@param pid integer
---@return boolean ok
function M.kill_tree(pid)
  if not pid or pid <= 0 then
    return false
  end

  local cmd
  if require("insights.util.platform").is_windows() then
    cmd = { "taskkill", "/PID", tostring(pid), "/T", "/F" }
  else
    -- Negative pid targets the process group, so the server's own children die
    -- with it; the shell is the group leader for a terminal job.
    cmd = { "kill", "-TERM", "-" .. tostring(pid) }
  end

  local ok, res = pcall(function()
    return vim.system(cmd, { text = true }):wait()
  end)
  if ok and res and res.code == 0 then
    return true
  end

  -- Fall back to the plain pid (no process group, or taskkill unavailable).
  local ok2, res2 = pcall(function()
    return vim.system({ "kill", "-TERM", tostring(pid) }, { text = true }):wait()
  end)
  return (ok2 and res2 and res2.code == 0) or false
end

---Record a decision for a terminal channel.
---@param chan integer
---@param cmd string
---@param kill boolean
function M.track(chan, cmd, kill)
  local ok, pid = pcall(fn.jobpid, chan)
  if not ok or not pid then
    return
  end
  tracked[chan] = { pid = pid, cmd = cmd, kill_on_exit = kill }
end

---Ask the user whether the server in `chan` should be killed on exit.
---@param chan integer
---@param cmd string
local function ask(chan, cmd)
  local cfg = require("insights.config").get().devserver or {}

  if cfg.prompt == false then
    M.track(chan, cmd, cfg.kill_on_exit ~= false)
    return
  end

  local kit = require("lib.nvim.ui.kit")
  kit.confirm({
    title = " Insights ",
    question = ("Dev server detected:\n%s\n\nKill it when Neovim exits?"):format(cmd),
    on_answer = function(yes)
      M.track(chan, cmd, yes and true or false)
      if yes then
        notify.info("will kill on exit: " .. cmd)
      end
    end,
  })
end

---Consider a terminal command for tracking. Called from the autocmds.
---@param chan integer
---@param cmd string
function M.consider(chan, cmd)
  local cfg = require("insights.config").get().devserver or {}
  if cfg.enable == false or asked[chan] then
    return
  end
  if not M.match(cmd, cfg.patterns or {}) then
    return
  end
  asked[chan] = true
  ask(chan, cmd)
end

---Kill tracked servers. On VimLeavePre only those the user answered "yes" for;
---`force` kills every tracked server regardless of the answer.
---@param force boolean|nil
---@return integer killed
function M.kill_all(force)
  local killed = 0
  for chan, info in pairs(tracked) do
    if force or info.kill_on_exit then
      if M.kill_tree(info.pid) then
        killed = killed + 1
      end
      pcall(fn.jobstop, chan)
    end
  end
  return killed
end

---The command a terminal channel is running, as a single string.
---@param chan integer
---@param bufnr integer
---@return string
function M.chan_cmd(chan, bufnr)
  local ok, info = pcall(api.nvim_get_chan_info, chan)
  if ok and info and type(info.argv) == "table" and #info.argv > 0 then
    return table.concat(info.argv, " ")
  end
  local ok2, title = pcall(function()
    return vim.b[bufnr].term_title
  end)
  return (ok2 and type(title) == "string") and title or ""
end

return M
