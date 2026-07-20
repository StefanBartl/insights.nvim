---@meta
---@module 'insights.config.@types'
--- Type definitions for the setup() options table. Loaded purely for LSP/
--- LuaLS diagnostics — required from config/init.lua, returns nothing usable.

---@alias Insights.CompressEngine
---| '"auto"'        # tar on Unix, Compress-Archive on Windows (default)
---| '"tar"'         # find + tar → .tar.gz  (Unix/macOS)
---| '"zip"'         # find + zip → .zip     (Unix/macOS, requires zip)
---| '"powershell"'  # PowerShell Compress-Archive → .zip  (Windows)

---@alias Insights.SymbolScope "cwd"|"buffer"
---@alias Insights.ImportsEngine "auto"|"treesitter"|"ripgrep"
---@alias Insights.DefinitionView "edit"|"float"

---@class Insights.Symbols.Languages
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

---@class Insights.Symbols.Indexing
---@field exclude_patterns string[]
---@field max_file_size_kb integer
---@field follow_symlinks boolean

---@class Insights.Symbols.Cache
---@field enabled boolean
---@field dir string
---@field ttl_seconds integer  0 = never expire

---@class Insights.SymbolsConfig
---@field enable boolean
---@field default_scope Insights.SymbolScope
---@field languages Insights.Symbols.Languages
---@field use_treesitter_for_lua boolean
---@field indexing Insights.Symbols.Indexing
---@field cache Insights.Symbols.Cache

---@class Insights.MetricsConfig
---@field enable boolean
---@field output_file string
---@field analyze_lua boolean          analyze Lua source files
---@field analyze_misc boolean         analyze Markdown / TXT / JSON files
---@field show_file_tables boolean     detailed per-file table
---@field show_folder_tables boolean   per-folder aggregate table
---@field show_total_summary boolean   grand-total row
---@field show_ratios boolean          folder ratio analysis
---@field show_deviations boolean      deviations from global averages
---@field show_top_lists boolean       top-N files by lines/words
---@field show_misc_detailed boolean   per-file listing for misc files
---@field percent_mode "both"|"percent"|"numbers"  value display mode
---@field reverse_order boolean        summary first (vs. files first)
---@field top_n integer                items in top-N lists
---@field col_width integer            data column width in tables
---@field exclude_type_files boolean   exclude @types files from ratio analysis

---@class Insights.TreeConfig
---@field enable boolean
---@field exclude_patterns string[]
---@field outdir string
---@field outfile_fmt string  "%s" expands to the project name

---@class Insights.FileinfoConfig
---@field enable boolean
---@field keymap string|false

---@class Insights.KeymapsConfig
---@field symbols_telescope string|false
---@field symbols_fzf string|false

---@class Insights.UIConfig
---@field close_keys string[]  buffer-local keys that close a scratch buffer / fileinfo float
---@field follow_key string    buffer-local key that follows path:line in a scratch buffer

---@class Insights.CompressConfig
---@field enable boolean
---@field engine Insights.CompressEngine
---@field outdir string  "" = compressed/ next to the source directory

---@class Insights.Imports.DefinitionKeymaps
---@field jump string|false
---@field preview string|false

---@class Insights.Imports.Definition
---@field view Insights.DefinitionView
---@field border string
---@field keymaps Insights.Imports.DefinitionKeymaps

---@class Insights.ImportsConfig
---@field enable boolean
---@field engine Insights.ImportsEngine
---@field output_file string
---@field groups table<string, string[]>
---@field classify_external boolean
---@field definition Insights.Imports.Definition

---@class Insights.ConflictsConfig
---@field enable boolean
---@field events string[]      autocmd events that trigger the scan; {} = manual only
---@field git_cmd string
---@field diff_filter string   git --diff-filter value; "U" = unmerged
---@field open_qf boolean      :copen after populating the quickfix list
---@field notify boolean       notify with the conflicting file names

---@class Insights.UnimportedConfig
---@field enable boolean
---@field events string[]      autocmd events that trigger the check
---@field filetypes string[]   filetypes the check applies to
---@field ignore string[]      component names to never report

---@class Insights.DevserverConfig
---@field enable boolean
---@field prompt boolean       ask via lib.nvim ui.kit; false = apply kill_on_exit silently
---@field kill_on_exit boolean the answer used when prompt = false
---@field patterns string[]    plain substrings matched case-insensitively against the terminal command

---@class InsightsConfig
---@field symbols Insights.SymbolsConfig
---@field metrics Insights.MetricsConfig
---@field tree Insights.TreeConfig
---@field fileinfo Insights.FileinfoConfig
---@field keymaps Insights.KeymapsConfig
---@field ui Insights.UIConfig
---@field compress Insights.CompressConfig
---@field imports Insights.ImportsConfig
---@field conflicts Insights.ConflictsConfig
---@field unimported Insights.UnimportedConfig
---@field devserver Insights.DevserverConfig
---@field commands boolean  false = register no user commands at all

return {}
