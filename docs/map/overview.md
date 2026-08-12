# insights.nvim — module map

> **Generated** by `documentation`. Do not edit by hand — run `:DocMap`
> (or `nvim --headless -l scripts/gen_map.lua`) to regenerate.

**12 modules** · 5 namespaces · 32 helper files

The [interactive map](index.html) has filtering, full descriptions and
source links; this page is the version the code host renders directly.


## Namespaces

```mermaid
flowchart LR
  nlua["insights.nvim"]
  nlua_insights["insightsbr/smallCombines: - function_index (ripgrep symbol…/small"]
  nlua_insights_bindings["bindings"]
  nlua_insights_compress["compressbr/smallSupported engines: 'tar' — find + tar →…/small"]
  nlua_insights_config["configbr/smallMerges user options (from setup()) over the…/small"]
  nlua_insights_conflicts["conflictsbr/smallUnresolved-merge-conflict report: asks git…/small"]
  nlua_insights_devserver["devserverbr/smallDev-server lifecycle: notice when a…/small"]
  nlua_insights_fileinfo["fileinfobr/smallFloating window with filesystem metadata…/small"]
  nlua_insights_imports["importsbr/smallGo, Rust and C/C++./small"]
  nlua_insights_metrics["metricsbr/smalltop-N lists, and documentation-file…/small"]
  nlua_insights_scan["scan"]
  nlua_insights_symbols["symbolsbr/smallThis module merges the function_index…/small"]
  nlua_insights_tree["treebr/smallAsync file tree writer, file counter, and…/small"]
  nlua_insights_ui["ui"]
  nlua_insights_unimported["unimportedbr/smallStatic per-buffer check for component-style…/small"]
  nlua_insights_util["util"]
  nlua --> nlua_insights
  nlua_insights --> nlua_insights_bindings
  nlua_insights --> nlua_insights_compress
  nlua_insights --> nlua_insights_config
  nlua_insights --> nlua_insights_conflicts
  nlua_insights --> nlua_insights_devserver
  nlua_insights --> nlua_insights_fileinfo
  nlua_insights --> nlua_insights_imports
  nlua_insights --> nlua_insights_metrics
  nlua_insights --> nlua_insights_scan
  nlua_insights --> nlua_insights_symbols
  nlua_insights --> nlua_insights_tree
  nlua_insights --> nlua_insights_ui
  nlua_insights --> nlua_insights_unimported
  nlua_insights --> nlua_insights_util
```


## Dependencies

Which parts of the tree require which, rolled up to the second level.
The [interactive map](index.html)'s **Deps** view has this per module,
in both directions, with load-time and lazy requires told apart.

```mermaid
flowchart LR
  nlua_insights_bindings["bindings"]
  nlua_insights_compress["insights.compress"]
  nlua_insights_config["insights.config"]
  nlua_insights_conflicts["insights.conflicts"]
  nlua_insights_devserver["insights.devserver"]
  nlua_insights_fileinfo["insights.fileinfo"]
  nlua_insights_health_lua["insights.health"]
  nlua_insights_imports["insights.imports"]
  nlua_insights_metrics["insights.metrics"]
  nlua_insights_scan["scan"]
  nlua_insights_symbols["insights.symbols"]
  nlua_insights_tree["insights.tree"]
  nlua_insights_ui["ui"]
  nlua_insights_unimported["insights.unimported"]
  nlua_insights_util["util"]
  nlua_insights_bindings --> nlua_insights_compress
  nlua_insights_bindings --> nlua_insights_config
  nlua_insights_bindings --> nlua_insights_conflicts
  nlua_insights_bindings --> nlua_insights_devserver
  nlua_insights_bindings --> nlua_insights_fileinfo
  nlua_insights_bindings --> nlua_insights_imports
  nlua_insights_bindings --> nlua_insights_metrics
  nlua_insights_bindings --> nlua_insights_scan
  nlua_insights_bindings --> nlua_insights_symbols
  nlua_insights_bindings --> nlua_insights_tree
  nlua_insights_bindings --> nlua_insights_ui
  nlua_insights_bindings --> nlua_insights_unimported
  nlua_insights_bindings --> nlua_insights_util
  nlua_insights_compress --> nlua_insights_util
  nlua_insights_conflicts --> nlua_insights_config
  nlua_insights_conflicts --> nlua_insights_util
  nlua_insights_devserver --> nlua_insights_config
  nlua_insights_devserver --> nlua_insights_util
  nlua_insights_fileinfo --> nlua_insights_config
  nlua_insights_fileinfo --> nlua_insights_util
  nlua_insights_health_lua --> nlua_insights_config
  nlua_insights_health_lua --> nlua_insights_scan
  nlua_insights_health_lua --> nlua_insights_util
  nlua_insights_imports --> nlua_insights_config
  nlua_insights_imports --> nlua_insights_scan
  nlua_insights_imports --> nlua_insights_ui
  nlua_insights_imports --> nlua_insights_util
  nlua_insights_metrics --> nlua_insights_config
  nlua_insights_metrics --> nlua_insights_ui
  nlua_insights_metrics --> nlua_insights_util
  nlua_insights_symbols --> nlua_insights_config
  nlua_insights_symbols --> nlua_insights_scan
  nlua_insights_symbols --> nlua_insights_util
  nlua_insights_tree --> nlua_insights_config
  nlua_insights_tree --> nlua_insights_util
  nlua_insights_ui --> nlua_insights_config
  nlua_insights_ui --> nlua_insights_util
  nlua_insights_unimported --> nlua_insights_config
  nlua_insights_unimported --> nlua_insights_util
```


## Modules

| Module | Description | Fns | Docs |
|---|---|---|---|
| `insights` | Combines: - function_index (ripgrep symbol indexer, multi-language) - gather (Tree-sitter Lua symbol scanner) - lua_project_file_stats (Lua code metrics) -… | 11 | [src](../../lua/insights/init.lua) |
| &nbsp;&nbsp;`bindings` |  |  |  |
| &nbsp;&nbsp;`insights.compress` | Supported engines: "tar" — find + tar → .tar.gz (Unix/macOS) "zip" — find + zip → .zip (Unix/macOS, requires zip) "powershell" — Compress-Archive… | 5 | [src](../../lua/insights/compress/init.lua) |
| &nbsp;&nbsp;`insights.config` | Merges user options (from setup()) over the plugin's defaults. | 3 | [src](../../lua/insights/config/init.lua) |
| &nbsp;&nbsp;`insights.conflicts` | Unresolved-merge-conflict report: asks git for files in the "unmerged" state and puts them in the quickfix list. | 4 | [src](../../lua/insights/conflicts/init.lua) |
| &nbsp;&nbsp;`insights.devserver` | Dev-server lifecycle: notice when a terminal Neovim owns starts a dev server, ask once whether it should be killed when Neovim exits, and honour the answer on… | 9 | [src](../../lua/insights/devserver/init.lua) |
| &nbsp;&nbsp;`insights.fileinfo` | Floating window with filesystem metadata for the current buffer. | 5 | [src](../../lua/insights/fileinfo/init.lua) |
| &nbsp;&nbsp;`insights.imports` | Go, Rust and C/C++. | 27 | [src](../../lua/insights/imports/init.lua) |
| &nbsp;&nbsp;&nbsp;&nbsp;`insights.imports.langs` | Every entry implements the shared `ImportLang` contract: id, label, extensions, rg_prefilter, scan_source(src) -> RawImport[] (regex/text scan of a whole… |  | [src](../../lua/insights/imports/langs/init.lua) |
| &nbsp;&nbsp;`insights.metrics` | top-N lists, and documentation-file (Markdown/TXT/JSON) analysis. | 11 | [src](../../lua/insights/metrics/init.lua) |
| &nbsp;&nbsp;`scan` |  |  |  |
| &nbsp;&nbsp;`insights.symbols` | This module merges the function_index (ripgrep) and gather (Tree-sitter) sources. | 6 | [src](../../lua/insights/symbols/init.lua) |
| &nbsp;&nbsp;`insights.tree` | Async file tree writer, file counter, and clipboard copy. | 7 | [src](../../lua/insights/tree/init.lua) |
| &nbsp;&nbsp;`ui` |  |  |  |
| &nbsp;&nbsp;`insights.unimported` | Static per-buffer check for component-style tags that are used but never imported or defined. | 5 | [src](../../lua/insights/unimported/init.lua) |
| &nbsp;&nbsp;`util` |  |  |  |

## Drift

0 errors · 0 warnings · 17 info

No errors or warnings.


<details>
<summary>17 informational findings</summary>


| Check | Message |
|---|---|
| `dead-function` | engines.powershell is marked @internal and nothing in the tree calls it |
| `dead-function` | engines.tar is marked @internal and nothing in the tree calls it |
| `dead-function` | engines.zip is marked @internal and nothing in the tree calls it |
| `missing-readme` | lua/insights has no README.md |
| `missing-readme` | lua/insights/compress has no README.md |
| `missing-readme` | lua/insights/config has no README.md |
| `missing-readme` | lua/insights/conflicts has no README.md |
| `missing-readme` | lua/insights/devserver has no README.md |
| `missing-readme` | lua/insights/fileinfo has no README.md |
| `missing-readme` | lua/insights/imports has no README.md |
| `missing-readme` | lua/insights/imports/langs has no README.md |
| `missing-readme` | lua/insights/metrics has no README.md |
| `missing-readme` | lua/insights/symbols has no README.md |
| `missing-readme` | lua/insights/tree has no README.md |
| `missing-readme` | lua/insights/unimported has no README.md |
| `unreferenced-module` | insights is required by no other file in the tree |
| `unreferenced-module` | insights.health is required by no other file in the tree |

</details>
