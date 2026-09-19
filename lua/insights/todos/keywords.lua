---@module 'insights.todos.keywords'
--- The shipped keyword table and colour categories for `insights.todos`.
---
--- These came out of a host config (`config/todo_comments/keywords/init.lua`
--- and `colors/strong.lua`) that had been feeding them to todo-comments.nvim.
--- The table is the *data* half of that plugin -- which words are annotations,
--- which alias which, what colour class each belongs to -- and it was always
--- the user's own. It ships here as the default so a host that never touches
--- `todos.keywords` gets the same set, and one that does only has to state the
--- difference: `keywords = { FOO = { color = "info" }, HACK = false }` adds one
--- and drops one, everything else stays.
---
--- A colour category is a list of *candidates*, tried in order: a highlight
--- group name is used if that group defines a foreground in the active theme,
--- a `#rrggbb` literal is used as-is. So `{ "DiagnosticError", "ErrorMsg",
--- "#f7768e" }` follows the theme where the theme has an opinion and falls
--- back to a fixed red where it does not.

local M = {}

---@class Insights.Todos.Keyword
---@field icon? string     Sign-column glyph; at most two display cells, else the first letter is used.
---@field color? string    Category name in `todos.colors`; missing = "default".
---@field alt? string[]    Aliases recognised as this keyword.

---@type table<string, Insights.Todos.Keyword>
M.KEYWORDS = {
  FIX = { icon = " ", color = "error", alt = { "FIXME", "BUG", "FIXIT", "ISSUE" } },
  INFO = { icon = " ", color = "info" },
  DEBUG = { icon = " ", color = "hint" },
  TODO = { icon = " ", color = "info" },
  ROADMAP = { icon = " ", color = "info" },
  AUDIT = {
    icon = " ",
    color = "audit",
    alt = { "VERIFY", "REVIEW", "DOUBLECHECK", "QC", "CHECK", "CHECKIT", "RECHECK", "VALIDATE" },
  },
  HACK = { icon = " ", color = "warning" },
  WARN = { icon = " ", color = "warning", alt = { "WARNING", "XXX" } },
  PERF = { icon = " ", alt = { "OPTIM", "PERFORMANCE", "OPTIMIZE" } },
  NOTE = { icon = " ", color = "hint" },
  TEST = { icon = "⏲ ", color = "test", alt = { "TESTING", "PASSED", "FAILED" } },
  EXP = { icon = "🔬", color = "test", alt = { "EXPERIMENT", "EXPERIMENTAL" } },
  REF = {
    icon = "󰁨 ",
    color = "hint",
    alt = { "REFACTOR", "REWRITE", "CLEANUP", "IMPROVE", "RESTRUCTURE" },
  },
  ADD = { icon = " ", color = "info", alt = { "EXT", "NEXT", "FUTURE", "ENHANCE", "HOOK" } },
  FEAT = { icon = " ", color = "info", alt = { "FEATURE" } },
  WATCH = {
    icon = " ",
    color = "warning",
    alt = { "MONITOR", "OBSERVE", "TRACK", "INSPECT", "SURVEILLANCE" },
  },
  REMOVE = { icon = " ", color = "warning", alt = { "DELETE", "DEL", "UNUSED" } },
  DEVONLY = { icon = "", color = "hint", alt = { "TEMP", "DEV", "WIP" } },
}

--- Colour candidates per category, best first. See the module doc-comment
--- for how a candidate is chosen.
---@type table<string, string[]>
M.COLORS = {
  error = { "DiagnosticError", "ErrorMsg", "#f7768e" },
  warning = { "DiagnosticWarn", "WarningMsg", "#ff9e64" },
  info = { "DiagnosticInfo", "#7aa2f7" },
  hint = { "DiagnosticHint", "#1abc9c" },
  default = { "Identifier", "#bb9af7" },
  test = { "Identifier", "#9ece6a" },
  audit = { "DiagnosticHint", "Type", "#00BFA5" },
}

return M
