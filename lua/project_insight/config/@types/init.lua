---@meta
---@module 'project_insight.config.@types'
--- Type definitions for the setup() options table. Loaded purely for LSP/
--- LuaLS diagnostics — required from config/init.lua, returns nothing usable.

---@alias ProjectInsight.CompressEngine
---| '"auto"'        # tar on Unix, Compress-Archive on Windows (default)
---| '"tar"'         # find + tar → .tar.gz  (Unix/macOS)
---| '"zip"'         # find + zip → .zip     (Unix/macOS, requires zip)
---| '"powershell"'  # PowerShell Compress-Archive → .zip  (Windows)

---@alias ProjectInsight.SymbolScope "cwd"|"buffer"
---@alias ProjectInsight.ImportsEngine "auto"|"treesitter"|"ripgrep"
---@alias ProjectInsight.DefinitionView "edit"|"float"

---@class ProjectInsight.Symbols.Languages
---@field lua boolean
---@field python boolean
---@field javascript boolean
---@field typescript boolean
---@field go boolean
---@field rust boolean
---@field c boolean
---@field cpp boolean
---@field java boolean
---@field ruby boolean
---@field php boolean

---@class ProjectInsight.Symbols.Indexing
---@field exclude_patterns string[]
---@field max_file_size_kb integer
---@field follow_symlinks boolean

---@class ProjectInsight.Symbols.Cache
---@field enabled boolean
---@field dir string
---@field ttl_seconds integer  0 = never expire

---@class ProjectInsight.SymbolsConfig
---@field enable boolean
---@field default_scope ProjectInsight.SymbolScope
---@field languages ProjectInsight.Symbols.Languages
---@field use_treesitter_for_lua boolean
---@field indexing ProjectInsight.Symbols.Indexing
---@field cache ProjectInsight.Symbols.Cache

---@class ProjectInsight.MetricsConfig
---@field enable boolean
---@field output_file string
---@field show_ratios boolean
---@field show_deviations boolean
---@field top_n integer
---@field exclude_type_files boolean

---@class ProjectInsight.TreeConfig
---@field enable boolean
---@field exclude_patterns string[]
---@field outdir string
---@field outfile_fmt string  "%s" expands to the project name

---@class ProjectInsight.FileinfoConfig
---@field enable boolean
---@field keymap string|false

---@class ProjectInsight.KeymapsConfig
---@field symbols_telescope string|false
---@field symbols_fzf string|false

---@class ProjectInsight.UIConfig
---@field close_keys string[]  buffer-local keys that close a scratch buffer / fileinfo float
---@field follow_key string    buffer-local key that follows path:line in a scratch buffer

---@class ProjectInsight.CompressConfig
---@field enable boolean
---@field engine ProjectInsight.CompressEngine
---@field outdir string  "" = compressed/ next to the source directory

---@class ProjectInsight.Imports.DefinitionKeymaps
---@field jump string|false
---@field preview string|false

---@class ProjectInsight.Imports.Definition
---@field view ProjectInsight.DefinitionView
---@field border string
---@field keymaps ProjectInsight.Imports.DefinitionKeymaps

---@class ProjectInsight.ImportsConfig
---@field enable boolean
---@field engine ProjectInsight.ImportsEngine
---@field output_file string
---@field groups table<string, string[]>
---@field classify_external boolean
---@field definition ProjectInsight.Imports.Definition

---@class ProjectInsightConfig
---@field symbols ProjectInsight.SymbolsConfig
---@field metrics ProjectInsight.MetricsConfig
---@field tree ProjectInsight.TreeConfig
---@field fileinfo ProjectInsight.FileinfoConfig
---@field keymaps ProjectInsight.KeymapsConfig
---@field ui ProjectInsight.UIConfig
---@field compress ProjectInsight.CompressConfig
---@field imports ProjectInsight.ImportsConfig
---@field commands boolean  false = register no user commands at all

return {}
