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

---@class ProjectInsight.ConflictsConfig
---@field enable boolean
---@field events string[]      autocmd events that trigger the scan; {} = manual only
---@field git_cmd string
---@field diff_filter string   git --diff-filter value; "U" = unmerged
---@field open_qf boolean      :copen after populating the quickfix list
---@field notify boolean       notify with the conflicting file names

---@class ProjectInsight.UnimportedConfig
---@field enable boolean
---@field events string[]      autocmd events that trigger the check
---@field filetypes string[]   filetypes the check applies to
---@field ignore string[]      component names to never report

---@class ProjectInsight.DevserverConfig
---@field enable boolean
---@field prompt boolean       ask via lib.nvim ui.kit; false = apply kill_on_exit silently
---@field kill_on_exit boolean the answer used when prompt = false
---@field patterns string[]    plain substrings matched case-insensitively against the terminal command

---@class ProjectInsightConfig
---@field symbols ProjectInsight.SymbolsConfig
---@field metrics ProjectInsight.MetricsConfig
---@field tree ProjectInsight.TreeConfig
---@field fileinfo ProjectInsight.FileinfoConfig
---@field keymaps ProjectInsight.KeymapsConfig
---@field ui ProjectInsight.UIConfig
---@field compress ProjectInsight.CompressConfig
---@field imports ProjectInsight.ImportsConfig
---@field conflicts ProjectInsight.ConflictsConfig
---@field unimported ProjectInsight.UnimportedConfig
---@field devserver ProjectInsight.DevserverConfig
---@field commands boolean  false = register no user commands at all

return {}
