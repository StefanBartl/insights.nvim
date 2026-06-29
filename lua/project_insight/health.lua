---@module 'project_insight.health'
local M = {}

local ok_s   = vim.health.ok    or vim.health.report_ok
local warn_s  = vim.health.warn  or vim.health.report_warn
local err_s   = vim.health.error or vim.health.report_error
local info_s  = vim.health.info  or vim.health.report_info
local start_s = vim.health.start or vim.health.report_start

local function exe(bin) return vim.fn.executable(bin) == 1 end
local function platform_is_windows() return vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1 end

local function check_neovim()
  start_s("Neovim version")
  local v = vim.version()
  if v.major > 0 or v.minor >= 9 then
    ok_s(string.format("Neovim %d.%d.%d (>= 0.9 required)", v.major, v.minor, v.patch))
  else
    err_s(string.format("Neovim %d.%d.%d — project-insight requires 0.9+", v.major, v.minor, v.patch))
  end
  if v.major > 0 or v.minor >= 10 then
    ok_s("vim.system available (Neovim 0.10+)")
  else
    warn_s("Neovim < 0.10 — vim.system not available; async tree/count may not work")
  end
end

local function check_tools()
  start_s("External tools")
  if exe("rg") then
    ok_s("rg (ripgrep) — symbol indexer ready")
  else
    err_s("rg not found — install ripgrep; symbol indexing will not work")
  end
  if exe("fd") or exe("fdfind") then
    ok_s("fd / fdfind — optional; not used currently")
  else
    info_s("fd not found (not required)")
  end
  if platform_is_windows() then
    ok_s("PowerShell — used for file tree on Windows")
  else
    if exe("find") and exe("sed") then
      ok_s("find + sed — used for file tree on Unix")
    else
      warn_s("find or sed not found — file tree / count may fail on this system")
    end
  end
end

local function check_pickers()
  start_s("Optional pickers")
  if pcall(require, "telescope") then
    ok_s("telescope.nvim — telescope picker available")
  else
    info_s("telescope.nvim not installed — use fzf or scratch buffer")
  end
  if pcall(require, "fzf-lua") then
    ok_s("fzf-lua — fzf picker available")
  else
    info_s("fzf-lua not installed — use telescope or scratch buffer")
  end
end

local function check_treesitter()
  start_s("Tree-sitter (optional Lua scanner)")
  if pcall(require, "nvim-treesitter") then
    ok_s("nvim-treesitter installed")
  else
    info_s("nvim-treesitter not installed — TS Lua scanner unavailable (rg scanner works without it)")
  end
end

local function check_config()
  start_s("Configuration")
  local ok, cfg_mod = pcall(require, "project_insight.config")
  if not ok then err_s("cannot load config"); return end
  local cfg = cfg_mod.get()
  local sym = cfg.symbols or {}

  local enabled_langs = {}
  for lang, en in pairs(sym.languages or {}) do
    if en then enabled_langs[#enabled_langs + 1] = lang end
  end
  info_s("symbols.default_scope = " .. (sym.default_scope or "cwd"))
  info_s("symbols.languages = " .. table.concat(enabled_langs, ", "))
  info_s("symbols.cache.enabled = " .. tostring(sym.cache and sym.cache.enabled))
  info_s("metrics.output_file = " .. (cfg.metrics and cfg.metrics.output_file or "?"))
  info_s("tree.outdir = " .. (cfg.tree and cfg.tree.outdir or "?"))
  info_s("imports.enable = " .. tostring(cfg.imports and cfg.imports.enable))
  info_s("imports.engine = " .. (cfg.imports and cfg.imports.engine or "auto"))
end

local function check_compress()
  start_s("Compress feature")
  local ok, cfg_mod = pcall(require, "project_insight.config")
  if not ok then err_s("cannot load config"); return end
  local cmp = cfg_mod.get().compress or {}

  if not cmp.enable then
    info_s("compress feature disabled (compress.enable = false)")
    return
  end

  local engine = cmp.engine or "auto"
  info_s("compress.engine = " .. engine)

  if cmp.outdir and cmp.outdir ~= "" then
    local outdir = vim.fn.expand(cmp.outdir)
    if vim.fn.isdirectory(outdir) == 1 then
      ok_s("compress.outdir exists: " .. outdir)
    else
      local can_create = pcall(vim.fn.mkdir, outdir, "p")
      if can_create then ok_s("compress.outdir created: " .. outdir)
      else               warn_s("compress.outdir not writable: " .. outdir) end
    end
  else
    info_s("compress.outdir = \"\" → will write to <path>/compressed/ at runtime")
  end

  local effective = (engine == "auto")
    and (platform_is_windows() and "powershell" or "tar")
    or  engine

  if effective == "powershell" then
    if platform_is_windows() then
      ok_s("engine=powershell — PowerShell Compress-Archive available")
    else
      warn_s("engine=powershell requested but not on Windows")
    end
  elseif effective == "tar" then
    if exe("tar") then ok_s("tar available") else warn_s("tar not found") end
    if exe("find") then ok_s("find available") else warn_s("find not found") end
  elseif effective == "zip" then
    if exe("zip") then ok_s("zip available") else warn_s("zip not found") end
    if exe("find") then ok_s("find available") else warn_s("find not found") end
  end
end

local function check_cache()
  start_s("Symbol cache")
  local ok, cfg_mod = pcall(require, "project_insight.config")
  if not ok then return end
  local c = cfg_mod.get().symbols.cache
  if not c.enabled then info_s("cache disabled"); return end

  local ok2, cache_mod = pcall(require, "project_insight.scan.cache")
  if not ok2 then err_s("cannot load cache module"); return end

  local stats = cache_mod.stats(c.dir, "symbols")
  if stats then
    ok_s(string.format("cache: %d symbols, last indexed %s",
      stats.entry_count,
      os.date("%Y-%m-%d %H:%M", stats.indexed_at or 0)))
    info_s("  path: " .. stats.path)
  else
    info_s("no cache for current CWD — run :ProjectInsight cache build")
  end
end

function M.check()
  check_neovim()
  check_tools()
  check_pickers()
  check_treesitter()
  check_config()
  check_compress()
  check_cache()
end

return M
