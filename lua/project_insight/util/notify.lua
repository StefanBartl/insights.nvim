---@module 'project_insight.util.notify'
--- Thin re-export of lib.nvim's notify factory, kept as a stable internal
--- module boundary (project_insight.util.notify) in case the backing
--- implementation ever changes.
return require("lib.nvim.notify")
