---@module 'insights.bindings.keymaps'
--- Optional global keymaps, config-driven. Set the corresponding config key
--- to false to disable. Every mapping carries a `desc`, so which-key.nvim
--- discovers them automatically.
local M = {}

local map = require("lib.nvim.map")
local notify = require("insights.util.notify").create("[insights.keymaps]")

---@param cfg InsightsConfig
function M.setup(cfg)
  local fi = cfg.fileinfo or {}
  if fi.enable ~= false and fi.keymap and fi.keymap ~= "" and fi.keymap ~= false then
    map("n", fi.keymap, function()
      require("insights.fileinfo").show()
    end, {}, "insights: file info float")
  end

  local km = cfg.keymaps or {}
  if km.symbols_telescope and km.symbols_telescope ~= false then
    map("n", km.symbols_telescope, function()
      local symbols = require("insights.symbols")
      local entries, msg = symbols.get()
      if msg then notify.info(msg) end
      require("insights.ui.telescope").open(entries,
        string.format("Symbols (cwd) — %d", #entries))
    end, {}, "insights: symbols (telescope)")
  end

  if km.symbols_fzf and km.symbols_fzf ~= false then
    map("n", km.symbols_fzf, function()
      local symbols = require("insights.symbols")
      local entries, msg = symbols.get()
      if msg then notify.info(msg) end
      require("insights.ui.fzf").open(entries,
        string.format("Symbols (cwd) — %d", #entries))
    end, {}, "insights: symbols (fzf)")
  end
end

return M
