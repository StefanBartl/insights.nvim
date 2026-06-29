---@module 'project_insight.imports.resolve'
---@brief Resolve a Lua module path to the file that defines it — without
---       executing `require(...)` (no side effects).
---
--- Resolution order (first hit wins):
---   1. project-local candidates under the cwd (lua/<rel>.lua, <rel>/init.lua, …)
---   2. Neovim's module loader cache (`vim.loader.find`)
---   3. `package.searchpath(module, package.path)`
---   4. runtime files (`nvim_get_runtime_file`)
local M = {}

--- Project-local candidate paths for a module, relative to `cwd`.
--- Mirrors the candidate set used by imports/init.lua `is_external`, so a module
--- tagged as project-local there resolves to the same file here.
---@param module string
---@param cwd string
---@return string[]
local function local_candidates(module, cwd)
  local rel = (module:gsub("%.", "/"))
  return {
    cwd .. "/lua/" .. rel .. ".lua",
    cwd .. "/lua/" .. rel .. "/init.lua",
    cwd .. "/" .. rel .. ".lua",
    cwd .. "/" .. rel .. "/init.lua",
  }
end

--- Resolve `module` to an absolute file path, or nil if it cannot be located.
---@param module string
---@param cwd string|nil   defaults to the current working directory
---@return string|nil path
function M.module_path(module, cwd)
  cwd = cwd or vim.fn.getcwd()

  -- 1. project-local files take precedence so cwd modules win over a stale
  --    copy on the runtimepath.
  for _, p in ipairs(local_candidates(module, cwd)) do
    if vim.fn.filereadable(p) == 1 then
      return vim.fn.fnamemodify(p, ":p")
    end
  end

  -- 2. Neovim's loader cache (LuaLS does not know loader.find → disable hint).
  ---@diagnostic disable-next-line: undefined-field
  if vim.loader and vim.loader.find then
    ---@diagnostic disable-next-line: undefined-field
    local ok, res = pcall(vim.loader.find, module)
    -- vim.loader.find returns a list of { modpath = "…" } tables.
    if ok and type(res) == "table" and res[1] and type(res[1].modpath) == "string" then
      return res[1].modpath
    end
  end

  -- 3. package.searchpath against the active package.path.
  local ok, p = pcall(package.searchpath, module, package.path)
  if ok and type(p) == "string" and p ~= "" then
    return p
  end

  -- 4. runtime files (covers plugins on the runtimepath).
  local rel = (module:gsub("%.", "/"))
  for _, suffix in ipairs({ ".lua", "/init.lua" }) do
    local hits = vim.api.nvim_get_runtime_file("lua/" .. rel .. suffix, true)
    if hits and #hits > 0 then
      return hits[1]
    end
  end

  return nil
end

return M
