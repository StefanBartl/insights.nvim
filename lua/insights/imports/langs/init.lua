---@module 'insights.imports.langs'
---@brief Registry of per-language import scanners.
---
--- Every entry implements the shared `ImportLang` contract:
---   id, label, extensions, rg_prefilter,
---   scan_source(src) -> RawImport[]   (regex/text scan of a whole file)
---   is_external(module, cwd) -> boolean
--- Lua additionally provides `ts_scan_source`/`ts_available` for its
--- Tree-sitter-accurate path (see `insights.imports.ts_requires`).
local M = {}

---@type table<string, table>
M.registry = {
  lua        = require("insights.imports.langs.lua"),
  python     = require("insights.imports.langs.python"),
  javascript = require("insights.imports.langs.javascript"),
  go         = require("insights.imports.langs.go"),
  rust       = require("insights.imports.langs.rust"),
  c          = require("insights.imports.langs.c"),
}

--- Deterministic iteration order.
M.order = { "lua", "python", "javascript", "go", "rust", "c" }

--- Short display tag for the report (`[lua ]`, `[py  ]`, …).
M.tags = {
  lua        = "lua",
  python     = "py",
  javascript = "js",
  go         = "go",
  rust       = "rs",
  c          = "c",
}

return M
