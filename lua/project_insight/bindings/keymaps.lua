---@module 'project_insight.bindings.keymaps'
--- Optional global keymaps, config-driven. Set the corresponding config key
--- to false to disable. Every mapping carries a `desc`, so which-key.nvim
--- discovers them automatically.
local M = {}

---@param cfg ProjectInsightConfig
function M.setup(cfg)
  local fi = cfg.fileinfo or {}
  if fi.enable ~= false and fi.keymap and fi.keymap ~= "" and fi.keymap ~= false then
    vim.keymap.set("n", fi.keymap, function()
      require("project_insight.fileinfo").show()
    end, { desc = "project-insight: file info float" })
  end

  local km = cfg.keymaps or {}
  if km.symbols_telescope and km.symbols_telescope ~= false then
    vim.keymap.set("n", km.symbols_telescope, function()
      local symbols = require("project_insight.symbols")
      local entries, msg = symbols.get()
      if msg then vim.notify(msg, vim.log.levels.INFO) end
      require("project_insight.ui.telescope").open(entries,
        string.format("Symbols (cwd) — %d", #entries))
    end, { desc = "project-insight: symbols (telescope)" })
  end

  if km.symbols_fzf and km.symbols_fzf ~= false then
    vim.keymap.set("n", km.symbols_fzf, function()
      local symbols = require("project_insight.symbols")
      local entries, msg = symbols.get()
      if msg then vim.notify(msg, vim.log.levels.INFO) end
      require("project_insight.ui.fzf").open(entries,
        string.format("Symbols (cwd) — %d", #entries))
    end, { desc = "project-insight: symbols (fzf)" })
  end
end

return M
