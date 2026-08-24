---@module 'insights.symbols.open'
--- The one place a symbol picker gets opened.
---
--- `:Insights symbols` and the two `symbols_*` keymaps both want the same
--- thing: pick a scope and a symbol type, scan, and show the result in a UI.
--- They used to do it separately, and drifted -- the keymaps hardcoded
--- cwd/functions/one UI, and had lost the "nothing found" guard and `rebuild`
--- that the command path has. Anything shared between the two lives here now,
--- so a fix lands once.
---
--- The token lists are here rather than in `bindings/usrcmds.lua` for the same
--- reason: they drive the command's `<Tab>` completion *and* the validation of
--- a keymap's configured scope/type, and two copies of "which scopes exist"
--- is exactly the kind of thing that goes stale on one side only.

local notify = require("insights.util.notify").create("[insights.symbols]")

local M = {}

---@type string[]
M.SCOPES = { "cwd", "buffer" }

---@type string[]
M.TYPES = { "functions", "tables", "strings" }

---@type string[]
M.UIS = { "telescope", "fzf", "scratch" }

---Whichever picker is actually installed, best first.
---@return string
function M.default_ui()
  if pcall(require, "telescope") then
    return "telescope"
  end
  if pcall(require, "fzf-lua") then
    return "fzf"
  end
  return "scratch"
end

---@internal
---@param entries table[]
---@param ui string
---@param label string
local function open_picker(entries, ui, label)
  local title = string.format("Symbols (%s) — %d found", label, #entries)
  if ui == "fzf" then
    require("insights.ui.fzf").open(entries, title)
  elseif ui == "scratch" then
    local lines = {}
    for _, e in ipairs(entries) do
      lines[#lines + 1] = string.format(
        "%s:%d  [%s] %s",
        e.filename or "?",
        e.lnum or 0,
        e.func_type or "?",
        e.name or "?"
      )
    end
    require("insights.ui.scratch").open(lines, title)
  else
    require("insights.ui.telescope").open(entries, title)
  end
end

---Scan for symbols and show them.
---
--- Every field is optional; the defaults are the ones `:Insights symbols`
--- with no arguments has always used.
---@param opts { scope?: string, type?: string, ui?: string, rebuild?: boolean }|nil
function M.open(opts)
  opts = opts or {}

  local scope = opts.scope or "cwd"
  local sym_type = opts.type or "functions"
  local ui = opts.ui or M.default_ui()

  local symbols = require("insights.symbols")
  local entries, msg

  if sym_type == "tables" then
    notify.info("scanning Lua tables…")
    entries, msg = symbols.get_tables(scope)
  elseif sym_type == "strings" then
    notify.info("scanning Lua strings…")
    entries, msg = symbols.get_strings(scope)
  else
    notify.info("scanning symbols…")
    entries, msg = symbols.get(scope, opts.rebuild == true)
  end

  if msg then
    notify.info(msg)
  end

  if not entries or #entries == 0 then
    notify.warn("nothing found")
    return
  end

  open_picker(entries, ui, scope .. " " .. sym_type)
end

---Normalize a `keymaps.symbols_*` config value.
---
--- Accepts the historical plain-string form (`"<leader>ps"`, meaning cwd +
--- functions) and the table form that can also name a scope, a type, and
--- `rebuild`. Returns nil when the mapping is disabled.
---
--- An unknown scope or type is reported and then *ignored*, falling back to
--- the default rather than passing a typo down to a scanner that would answer
--- with a confusing "nothing found".
---@param value string|false|table|nil
---@param key string  # config key name, for the error message
---@return { lhs: string, scope?: string, type?: string, rebuild?: boolean }|nil
function M.normalize_keymap(value, key)
  if value == nil or value == false or value == "" then
    return nil
  end

  if type(value) == "string" then
    return { lhs = value }
  end

  if type(value) ~= "table" or type(value.lhs) ~= "string" or value.lhs == "" then
    notify.warn(("keymaps.%s: expected a string or a table with an `lhs` string"):format(key))
    return nil
  end

  local spec = { lhs = value.lhs, rebuild = value.rebuild == true }

  if value.scope ~= nil then
    if vim.tbl_contains(M.SCOPES, value.scope) then
      spec.scope = value.scope
    else
      notify.warn(
        ("keymaps.%s: unknown scope %s, using %q"):format(
          key,
          vim.inspect(value.scope),
          M.SCOPES[1]
        )
      )
    end
  end

  if value.type ~= nil then
    if vim.tbl_contains(M.TYPES, value.type) then
      spec.type = value.type
    else
      notify.warn(
        ("keymaps.%s: unknown type %s, using %q"):format(key, vim.inspect(value.type), M.TYPES[1])
      )
    end
  end

  return spec
end

return M
