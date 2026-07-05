# Roadmap

Planned and proposed work for project-insight.nvim. Items are not ordered by
priority.

## Imports / dependency analysis

The `:ProjectInsight imports` command scans **Lua** `require(...)` calls. It is
Tree-sitter-accurate by default (only genuine calls in the AST are counted),
with a ripgrep line scan as fallback. Extend it to other languages, each with
its own import syntax and "module path" notion:

- [ ] **Python** — `import x`, `import x.y as z`, `from x.y import a, b`
- [ ] **JavaScript / TypeScript** — `import … from "x"`, `import("x")`,
      `require("x")` (CommonJS)
- [ ] **Go** — `import "path"` and grouped `import ( … )` blocks
- [ ] **Rust** — `use a::b::c;`, grouped `use a::{b, c};`
- [ ] **C / C++** — `#include <...>` vs `#include "..."` (system vs local)

Design notes for the multi-language version:

- Per-language extractor, mirroring the Lua implementation: a Tree-sitter
  query over the language's import nodes is the accurate baseline (see
  `imports/ts_requires.lua` for the Lua model — query + AST walk for the bound
  name and accessed members), with an optional ripgrep line fallback for when
  the parser is unavailable.
- Reuse the existing report shape: a Count table (module → occurrences, with
  an `(extern)` tag for modules without a local source file) and an
  Occurrence list (`path:line  module  imported-name`).
- `classify_external` needs per-language resolution rules (e.g. relative vs
  package imports in JS/TS, system vs local includes in C/C++).
- The filter/group mechanism (prefix match + named groups) and the backend
  dispatch (`imports.engine = auto|treesitter|ripgrep`) are language-agnostic
  and can be kept as-is.

## Ideas / backlog

- [ ] Optional picker output (telescope / fzf-lua) for the imports occurrence
      list, in addition to the scratch buffer.
- [ ] "Reverse" view: given a module, list every file that imports it.
- [ ] Detect unused requires (imported but the bound name is never referenced).
