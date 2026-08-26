---@module 'insights.bindings.keymaps'
--- Optional global keymaps, config-driven. Set the corresponding config key
--- to false to disable. Every mapping carries a `desc`, so which-key.nvim
--- discovers them automatically.
local M = {}

local map = require("lib.nvim.bindings.keymap")
local symbols_open = require("insights.symbols.open")

---@internal
---Wire one `symbols_*` keymap.
---
--- The UI is fixed by which config key this is -- that is what the key names
--- mean -- but scope, type and `rebuild` come from the config, so
--- `<leader>ps` can be "tables in this buffer" instead of only the
--- cwd/functions default that used to be hardcoded here.
---
--- Dispatch goes through `symbols.open`, the same entry point `:Insights
--- symbols` uses. Previously these two mappings scanned and opened a picker
--- themselves, which is how they came to be missing the "nothing found" guard
--- and `rebuild` that the command path had.
---@param value string|false|table|nil
---@param key string
---@param ui string
local function symbols_keymap(value, key, ui)
  local spec = symbols_open.normalize_keymap(value, key)
  if not spec then
    return
  end

  local desc = ("insights: symbols (%s, %s %s)"):format(
    ui,
    spec.scope or "cwd",
    spec.type or "functions"
  )

  map("n", spec.lhs, function()
    symbols_open.open({
      scope = spec.scope,
      type = spec.type,
      ui = ui,
      rebuild = spec.rebuild,
    })
  end, {}, desc)
end

---@param cfg InsightsConfig
function M.setup(cfg)
  local fi = cfg.fileinfo or {}
  if fi.enable ~= false and fi.keymap and fi.keymap ~= "" and fi.keymap ~= false then
    map("n", fi.keymap, function()
      require("insights.fileinfo").show()
    end, {}, "insights: file info float")
  end

  local km = cfg.keymaps or {}
  symbols_keymap(km.symbols_telescope, "symbols_telescope", "telescope")
  symbols_keymap(km.symbols_fzf, "symbols_fzf", "fzf")
end

return M
