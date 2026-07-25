# Architecture

```
lua/insights/
  init.lua              setup() + public Lua façade
  config/
    init.lua            merges user opts over DEFAULTS
    DEFAULTS.lua         plugin-side default configuration
  bindings/
    usrcmds.lua         :Insights dispatcher + tab-completion
    keymaps.lua         optional global keymaps (which-key discoverable)
    autocmds.lua        no-op — insights registers no autocmds
  util/
    notify.lua          re-exports lib.nvim's notify factory
    platform.lua        is_windows() (via lib.nvim), run_shell(), copy_to_clipboard()
  scan/
    rg.lua              ripgrep command builder + sync executor
    cache.lua           CWD-keyed JSON cache (mtime-aware TTL)
  symbols/
    patterns.lua        PCRE2 patterns + extension maps (11 languages)
    parser.lua          rg --vimgrep output → SymbolEntry
    rg_index.lua        rg-based indexer with cache integration
    ts_lua.lua          Tree-sitter Lua function scanner (AST traversal)
    ts_lua_tables.lua   Tree-sitter Lua table constructor scanner
    ts_lua_strings.lua  Tree-sitter Lua string literal scanner
    init.lua            unified entry: rg + optional TS merge; get_tables/get_strings
  metrics/
    analyzer.lua        per-file line/word stats, ratios, percentages, formatting
    report.lua          ASCII tables (file/folder/total/ratios/top-N/guidelines)
    misc.lua            Markdown/TXT/JSON documentation-file analysis
    init.lua            scan, option resolution, report assembly, file output
  tree/init.lua         async file tree, count, clipboard
  fileinfo/init.lua     fs.stat floating window
  ui/
    telescope.lua       telescope entry_maker + picker
    fzf.lua             fzf-lua picker
    scratch.lua         read-only scratch buffer display
  compress/init.lua     async compression — engine dispatch (tar / zip / powershell)
  imports/
    init.lua            multi-language import analysis — dispatch, counts, report
    ts_requires.lua     Tree-sitter require() scanner (AST-accurate, Lua)
    resolve.lua         module path → file resolution (no require side-effects, Lua)
    definition.lua      locate + jump/preview the definition behind a Lua import
    langs/
      init.lua          language registry (id → scanner module)
      util.lua          shared regex-scan helpers (line offsets, comma/brace splitting)
      lua.lua           Lua require() — wraps ts_requires.lua + regex fallback
      python.lua        Python import/from-import scanner
      javascript.lua    JS/TS import/require scanner
      go.lua            Go import scanner
      rust.lua          Rust use-declaration scanner
      c.lua             C/C++ #include scanner
  health.lua            :checkhealth insights
plugin/insights.lua   guard + lazy-load trigger
```
