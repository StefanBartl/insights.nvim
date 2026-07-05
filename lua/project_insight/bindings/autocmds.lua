---@module 'project_insight.bindings.autocmds'
--- project-insight.nvim registers no autocmds: every action is triggered
--- explicitly via :ProjectInsight or a configured keymap. Kept as an empty
--- module for structural symmetry with bindings/keymaps.lua and
--- bindings/usrcmds.lua, and as the place to add one if that ever changes.
local M = {}

function M.setup() end

return M
