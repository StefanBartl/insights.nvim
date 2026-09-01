---@module 'insights.bindings.keymaps'
--- The optional global keymaps, declared as named actions.
---
--- Declared through `lib.nvim.bindings.keymap`'s registry. Two things about
--- insights' config shape are deliberately preserved rather than tidied away,
--- because changing either would break existing setups silently:
---
--- * A symbols mapping may carry its own options -- `symbols_telescope =
---   { lhs = "<leader>ps", scope = "buffer", type = "tables" }`. The registry
---   takes the `lhs`; the rest is read here, from the same value, so the two
---   can never disagree.
--- * `fileinfo`'s key lives at `fileinfo.keymap`, not in `keymaps`. It stays
---   there and is used as that action's default, so `keymaps.fileinfo` now
---   *also* works without `fileinfo.keymap` ceasing to.
---
--- Every mapping carries a `desc`, so which-key discovers them by itself.

local keymap = require("lib.nvim.bindings.keymap")
local symbols_open = require("insights.symbols.open")

local M = {}

---@internal
--- The callback for one `symbols_*` action.
---
--- The UI is fixed by which config key this is -- that is what the key names
--- mean -- while scope, type and `rebuild` come from the config, so
--- `<leader>ps` can be "tables in this buffer" instead of only the
--- cwd/functions default that used to be hardcoded here.
---
--- Dispatch goes through `symbols.open`, the same entry point `:Insights
--- symbols` uses. These two mappings once scanned and opened a picker
--- themselves, which is how they came to be missing the "nothing found" guard
--- and the `rebuild` handling that the command path had.
---@param value string|false|table|nil
---@param key string
---@param ui string
---@return fun() action The handler the keymap binds.
---@return string desc The description shown in `:map` and which-key.
local function symbols_action(value, key, ui)
  local spec = symbols_open.normalize_keymap(value, key) or {}

  local desc = ("symbols (%s, %s %s)"):format(ui, spec.scope or "cwd", spec.type or "functions")

  return function()
    symbols_open.open({
      scope = spec.scope,
      type = spec.type,
      ui = ui,
      rebuild = spec.rebuild,
    })
  end,
    desc
end

--- Declare and bind the global keymap actions.
---@param cfg InsightsConfig
---@return Lib.Keymap.Registered[]
function M.setup(cfg)
  local km = cfg.keymaps or {}
  local fi = cfg.fileinfo or {}

  local tele_rhs, tele_desc = symbols_action(km.symbols_telescope, "symbols_telescope", "telescope")
  local fzf_rhs, fzf_desc = symbols_action(km.symbols_fzf, "symbols_fzf", "fzf")

  ---@type Lib.Keymap.Spec
  local spec = {
    order = { "symbols_telescope", "symbols_fzf", "fileinfo" },
    actions = {
      symbols_telescope = { rhs = tele_rhs, desc = tele_desc },
      symbols_fzf = { rhs = fzf_rhs, desc = fzf_desc },

      -- `fileinfo.enable = false` switches the feature off entirely, which is
      -- a stronger statement than "do not bind a key for it": leaving the
      -- default off keeps the action declared (health and docs still see it)
      -- while binding nothing.
      fileinfo = {
        default = (fi.enable ~= false) and fi.keymap or nil,
        rhs = function()
          require("insights.fileinfo").show()
        end,
        desc = "file info float",
      },
    },
  }

  return keymap.register("insights", spec, km)
end

return M
