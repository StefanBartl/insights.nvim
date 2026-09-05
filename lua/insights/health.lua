---@module 'insights.health'
--- :checkhealth insights — verifies dependencies, external tools and
--- config-driven feature availability, one section per feature area.
local M = {}

local ok_s = vim.health.ok or vim.health.report_ok
local warn_s = vim.health.warn or vim.health.report_warn
local err_s = vim.health.error or vim.health.report_error
local info_s = vim.health.info or vim.health.report_info
local start_s = vim.health.start or vim.health.report_start

---@internal
---@param bin string
---@return boolean
local function exe(bin)
  return vim.fn.executable(bin) == 1
end

---@internal
---@return boolean
local function platform_is_windows()
  return require("insights.util.platform").is_windows()
end

---@internal
local function check_lib()
  start_s("lib.nvim")
  if pcall(require, "lib.nvim.notify") then
    ok_s("lib.nvim installed (notify + cross-platform helpers)")
  else
    err_s("lib.nvim not found", { "Install StefanBartl/lib.nvim as a dependency" })
  end
  if pcall(require, "lib.nvim.ui.kit") then
    ok_s("lib.nvim.ui.kit available (dev-server prompt)")
  else
    err_s(
      "lib.nvim.ui.kit not found — required for the dev-server prompt",
      { "Update StefanBartl/lib.nvim" }
    )
  end
  if pcall(require, "lib.nvim.bindings.usercmd.composer") then
    ok_s("lib.nvim.bindings.usercmd.composer available (:Insights command layer)")
  else
    err_s(
      ":Insights will fail to register — lib.nvim.bindings.usercmd.composer not found",
      { "Update StefanBartl/lib.nvim" }
    )
  end
end

---@internal
local function check_autocmds()
  start_s("Automatic triggers")
  local ok, cfg_mod = pcall(require, "insights.config")
  if not ok then
    err_s("cannot load config", { "Call require('insights').setup() in your config" })
    return
  end
  local cfg = cfg_mod.get()

  local conflicts = cfg.conflicts or {}
  if conflicts.enable then
    if exe(conflicts.git_cmd or "git") then
      ok_s("conflicts: enabled on " .. table.concat(conflicts.events or {}, ", "))
    else
      warn_s("conflicts enabled but git not executable: " .. (conflicts.git_cmd or "git"), {
        "Install git, or set conflicts.enable = false",
      })
    end
  else
    info_s("conflicts disabled (conflicts.enable = false)")
  end

  local unimported = cfg.unimported or {}
  if unimported.enable then
    ok_s("unimported: enabled for " .. table.concat(unimported.filetypes or {}, ", "))
  else
    info_s("unimported disabled (unimported.enable = false)")
  end

  local dev = cfg.devserver or {}
  if dev.enable then
    ok_s(
      string.format(
        "devserver: enabled, %d pattern(s), prompt = %s",
        #(dev.patterns or {}),
        tostring(dev.prompt ~= false)
      )
    )
    if platform_is_windows() then
      if exe("taskkill") then
        ok_s("taskkill available — dev-server process tree can be killed")
      else
        warn_s("taskkill not found — dev-server kill may not work", {
          "taskkill ships with Windows; check that it is on $PATH",
        })
      end
    else
      if exe("kill") then
        ok_s("kill available — dev-server process group can be killed")
      else
        warn_s("kill not found — dev-server kill may not work", {
          "Install procps (Linux) or the base utilities providing kill(1)",
        })
      end
    end
  else
    info_s("devserver disabled (devserver.enable = false)")
  end
end

---@internal
local function check_neovim()
  start_s("Neovim version")
  local v = vim.version()
  if v.major > 0 or v.minor >= 9 then
    ok_s(string.format("Neovim %d.%d.%d (>= 0.9 required)", v.major, v.minor, v.patch))
  else
    err_s(
      string.format("Neovim %d.%d.%d — insights requires 0.9+", v.major, v.minor, v.patch),
      { "Upgrade Neovim to 0.9+" }
    )
  end
  if v.major > 0 or v.minor >= 10 then
    ok_s("vim.system available (Neovim 0.10+)")
  else
    warn_s("Neovim < 0.10 — vim.system not available; async tree/count may not work", {
      "Upgrade Neovim to 0.10+",
    })
  end
end

---@internal
local function check_tools()
  start_s("External tools")
  if exe("rg") then
    ok_s("rg (ripgrep) — symbol indexer ready")
  else
    err_s("rg not found — symbol indexing will not work", {
      "Install ripgrep (https://github.com/BurntSushi/ripgrep)",
    })
  end
  -- No fd probe here. It used to report one, admitting in the same breath
  -- that it is "not used currently" — and nothing in this plugin has ever
  -- called it. A health check that reports on a tool the code never reaches
  -- teaches the reader that its lines are not to be trusted, and it cannot
  -- move into docs/install.json either: `why` is a mandatory field there,
  -- and there is no honest sentence to put in it. If a scanner ever grows
  -- an fd path, that is the moment to declare it.
  if platform_is_windows() then
    ok_s("PowerShell — used for file tree on Windows")
  else
    if exe("find") and exe("sed") then
      ok_s("find + sed — used for file tree on Unix")
    else
      warn_s("find or sed not found — file tree / count may fail on this system", {
        "Install findutils and sed",
      })
    end
  end
end

---@internal
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

---@internal
local function check_pdfport()
  start_s("Optional: PDF export (metrics.output_file ending .pdf)")
  local ok_pp, pdfport = pcall(require, "pdfport")
  if ok_pp and type(pdfport.can_create) == "function" and pdfport.can_create("text") then
    ok_s("pdfport.nvim — metrics.output_file ending .pdf can be written")
  elseif ok_pp then
    info_s(
      "pdfport.nvim installed, but no text producer is available (needs pandoc + a PDF engine — see pdfport.nvim's :checkhealth)"
    )
  else
    info_s(
      "pdfport.nvim not installed — metrics.output_file still works for .md/plain text (https://github.com/StefanBartl/pdfport.nvim)"
    )
  end
end

---@internal
local function check_treesitter()
  start_s("Tree-sitter (optional Lua scanner)")
  if pcall(require, "nvim-treesitter") then
    ok_s("nvim-treesitter installed")
  else
    info_s(
      "nvim-treesitter not installed — TS Lua scanner unavailable (rg scanner works without it)"
    )
  end
end

---@internal
local function check_config()
  start_s("Configuration")
  local ok, cfg_mod = pcall(require, "insights.config")
  if not ok then
    err_s("cannot load config", { "Call require('insights').setup() in your config" })
    return
  end
  local cfg = cfg_mod.get()
  local sym = cfg.symbols or {}

  local enabled_langs = {}
  for lang, en in pairs(sym.languages or {}) do
    if en then
      enabled_langs[#enabled_langs + 1] = lang
    end
  end
  info_s("symbols.default_scope = " .. (sym.default_scope or "cwd"))
  info_s("symbols.languages = " .. table.concat(enabled_langs, ", "))
  info_s("symbols.cache.enabled = " .. tostring(sym.cache and sym.cache.enabled))
  info_s("metrics.output_file = " .. (cfg.metrics and cfg.metrics.output_file or "?"))
  info_s("tree.outdir = " .. (cfg.tree and cfg.tree.outdir or "?"))
  info_s("imports.enable = " .. tostring(cfg.imports and cfg.imports.enable))
  info_s("imports.engine = " .. (cfg.imports and cfg.imports.engine or "auto"))
end

---@internal
local function check_compress()
  start_s("Compress feature")
  local ok, cfg_mod = pcall(require, "insights.config")
  if not ok then
    err_s("cannot load config", { "Call require('insights').setup() in your config" })
    return
  end
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
      if can_create then
        ok_s("compress.outdir created: " .. outdir)
      else
        warn_s("compress.outdir not writable: " .. outdir, {
          "Point compress.outdir at a writable directory",
        })
      end
    end
  else
    info_s('compress.outdir = "" → will write to <path>/compressed/ at runtime')
  end

  local effective = (engine == "auto") and (platform_is_windows() and "powershell" or "tar")
    or engine

  if effective == "powershell" then
    if platform_is_windows() then
      ok_s("engine=powershell — PowerShell Compress-Archive available")
    else
      warn_s("engine=powershell requested but not on Windows", {
        "Set compress.engine to 'tar', 'zip' or 'auto' on this platform",
      })
    end
  elseif effective == "tar" then
    if exe("tar") then
      ok_s("tar available")
    else
      warn_s("tar not found", { "Install tar, or set compress.engine to another value" })
    end
    if exe("find") then
      ok_s("find available")
    else
      warn_s("find not found", { "Install findutils" })
    end
  elseif effective == "zip" then
    if exe("zip") then
      ok_s("zip available")
    else
      warn_s("zip not found", { "Install zip, or set compress.engine to another value" })
    end
    if exe("find") then
      ok_s("find available")
    else
      warn_s("find not found", { "Install findutils" })
    end
  end
end

---@internal
---@internal
--- The hover contribution, and the one state that makes it look broken.
---
--- A cold import index means the preview says nothing at all -- deliberately,
--- because building one from a cursor movement would cost the 631 ms to 1.9 s
--- a full scan takes. From outside the float that is indistinguishable from a
--- feature that does not work, so it is said here instead.
---@return nil
local function check_hover()
  start_s("Hover contribution")

  local ok_cfg, cfg_mod = pcall(require, "insights.config")
  if ok_cfg and cfg_mod.get().hover == false then
    info_s("hover = false -- nothing registered")
    return
  end

  if not pcall(require, "hover.registry") then
    info_s("hover.nvim not installed -- nothing registered, nothing missing")
    return
  end

  local ok_idx, index = pcall(require, "insights.imports.index")
  if not ok_idx then
    err_s("cannot load insights.imports.index", { "Reinstall insights.nvim" })
    return
  end

  local entry = index.get()
  if not entry then
    info_s("import index is cold -- the hover says nothing until `:Insights imports` has run once")
    return
  end
  if entry.stale then
    info_s("import index is stale (a file was written since); the hover says so in the float")
    return
  end
  ok_s("import index is warm -- the hover can answer")
end

local function check_cache()
  start_s("Symbol cache")
  local ok, cfg_mod = pcall(require, "insights.config")
  if not ok then
    return
  end
  local c = cfg_mod.get().symbols.cache
  if not c.enabled then
    info_s("cache disabled")
    return
  end

  local ok2, cache_mod = pcall(require, "insights.scan.cache")
  if not ok2 then
    err_s("cannot load cache module", { "Reinstall insights.nvim" })
    return
  end

  local stats = cache_mod.stats(c.dir, "symbols")
  if stats then
    ok_s(
      string.format(
        "cache: %d symbols, last indexed %s",
        stats.entry_count,
        os.date("%Y-%m-%d %H:%M", stats.indexed_at or 0)
      )
    )
    info_s("  path: " .. stats.path)
  else
    info_s("no cache for current CWD — run :Insights cache build")
  end
end

---@internal
---Reports insights.nvim's own docs/install.json via lib.nvim.deps — the
---same rg/dot checks check_tools() already probes, but with their
---declared `why` and a pointer to `:Lib deps show`. Does nothing if
---lib.nvim.deps is unavailable (older lib.nvim).
local function check_lib_deps()
  local ok, deps_health = pcall(require, "lib.nvim.deps.health")
  if not ok then
    return
  end
  start_s("Declared tools (lib.nvim.deps)")
  deps_health.report_for("insights.nvim")
end

function M.check()
  check_neovim()
  check_lib()
  check_tools()
  check_pickers()
  check_pdfport()
  check_treesitter()
  check_config()
  check_autocmds()
  check_compress()
  check_cache()
  check_hover()
  check_lib_deps()

  require("lib.nvim.bindings.usercmd.composer").checkhealth("Insights")
end

return M
