# Analysis: insights.nvim ↔ documentation.nvim ↔ runtime-analysis.nvim

**The finding up front:** at present there are **zero cross-references** between insights.nvim and the other two — neither in the code nor in the documentation. documentation.nvim and runtime-analysis.nvim, by contrast, are already closely interlocked, with an architecture document of their own for it ([`documentation.nvim/docs/ROADMAP/FEATURES/ECOSYSTEM.md`](C:\repos\documentation.nvim\docs\ROADMAP\FEATURES\ECOSYSTEM.md)) and an ideas backlog just for the interface between the two ([`runtime-analysis.nvim/docs/IDEAS.md`](C:\repos\runtime-analysis.nvim\docs\IDEAS.md)). insights.nvim is not mentioned there with a single word. That is the starting point of this analysis.

## Table of content

  - [1. What the three plugins actually are](#1-what-the-three-plugins-actually-are)
  - [2. Real overlaps (duplication risk)](#2-real-overlaps-duplication-risk)
  - [3. Concrete synergy opportunities, ordered by effort/benefit](#3-concrete-synergy-opportunities-ordered-by-effortbenefit)
  - [4. What deliberately does **not** make sense](#4-what-deliberately-does-not-make-sense)
  - [In short](#in-short)

---

## 1. What the three plugins actually are

| Plugin | Core idea | Reach | Data basis |
|---|---|---|---|
| **documentation.nvim** | Static truth: what exists, what is documented, how it hangs together | **Lua only**, only `---@module`-annotated trees | Persisted, byte-deterministic IR (`module_map.json`), CI-checked |
| **runtime-analysis.nvim** | Runtime truth: what was actually executed | Lua/Neovim plugins (telemetry), plus an HTTP request runner | Live counters in the process, persisted in the cache |
| **insights.nvim** | Ad-hoc project analysis: symbols, metrics, imports/deps, tree, compression | **11 languages** (symbols), **6 languages** (imports) — expressly not just Lua/Neovim | ripgrep plus selective tree-sitter, no persisted IR, no CI gate |

The two established plugins organize themselves along a clear seam ("Seam A: static vs. runtime", [ECOSYSTEM.md](C:\repos\documentation.nvim\docs\ROADMAP\FEATURES\ECOSYSTEM.md):87-92). insights.nvim lies entirely on the static side — but on a **different axis**, one their documents do not name as such:

> **Deep and narrow vs. broad and shallow.** documentation.nvim is deep (persisted IR, call graphs, drift checks, CI-gated) but narrow (Lua only, annotated code only). insights.nvim is broad (6–11 languages) but shallow (text scan/regex, no history, no claim to determinism).

That is not a competition but a real division of labour — provided one makes it visible.

---

## 2. Real overlaps (duplication risk)

Two places where insights.nvim already **builds what documentation.nvim has set itself for later**:

- **`:Insights imports unused`** ([commands.md:249-259](C:\repos\insights.nvim\docs\commands.md)) — bound import names that are never referenced again. documentation.nvim lists exactly that as an open idea: *"Unused requires … cheap: the IR already has both the require edges and the symbol references"* ([documentation.nvim IDEAS.md §2.5](C:\repos\documentation.nvim\docs\ROADMAP\IDEAS\IDEAS.md):244-249). Were that built there, a second implementation of the same function would come into being — only narrower (Lua only) and without the other 5 languages insights.nvim already covers.
- **`:Insights symbols`** — a ripgrep-based symbol index over 11 languages with a Telescope/fzf picker. documentation.nvim deliberately discarded "Workspace symbols from the IR": *"Whether this is worth building depends entirely on whether it beats lua-language-server … Probably not"* ([IDEAS.md §6.5](C:\repos\documentation.nvim\docs\ROADMAP\IDEAS\IDEAS.md):445-451) — but precisely for Lua, where LSP is good anyway. For the other 10 languages in insights.nvim, where no or a worse LSP workspace symbol exists, insights.nvim fills a gap documentation.nvim will structurally never close (Lua only by design).

**Consequence:** before documentation.nvim tackles `IDEAS.md §2.5`, a look at insights.nvim is worth it — a pointer may well be enough instead of a rebuild.

---

## 3. Concrete synergy opportunities, ordered by effort/benefit

**a) Cross-link the READMEs (trivial, immediately worthwhile)**
insights.nvim currently pairs only with `buffer-ctx.nvim` ([README.md:11-13](C:\repos\insights.nvim\README.md)). An honest pointer in both directions — *"for documenting pure Lua/Neovim plugins with an IR and a CI gate: documentation.nvim; for quick ad-hoc analysis across several languages: insights.nvim"* — prevents exactly the duplication from point 2 and helps users choose their tool.

**b) Instrument insights.nvim itself with `runtime-analysis.telemetry`**
runtime-analysis.nvim offers a generic helper for exactly that: `telemetry.auto({ namespace, main, deep })` — "new+wrap+start in one call", a soft dependency, a no-op without the plugin ([telemetry/README.md:206-233](C:\repos\runtime-analysis.nvim\lua\runtime-analysis\telemetry\README.md)). documentation.nvim already does this with itself (`telemetry_self`, [ECOSYSTEM.md:704-724](C:\repos\documentation.nvim\docs\ROADMAP\FEATURES\ECOSYSTEM.md)) — exactly the same pattern as the `deps_popup` opt-out already present in [DEFAULTS.lua:192-198](C:\repos\insights.nvim\lua\insights\config\DEFAULTS.lua). An `opts.telemetry = true` default (a no-op without runtime-analysis.nvim) would answer: *which `:Insights` subcommands are actually used?* — relevant, for instance, to the question of whether `compress` or `devserver` are worth their weight in the plugin.

**c) Map insights.nvim with documentation.nvim, dev-only**
Both documentation.nvim and runtime-analysis.nvim generate their own `docs/map/` and publish it (READMEs, each saying "This repository maps itself with the same tool"). insights.nvim, by contrast, maintains [`docs/architecture.md`](C:\repos\insights.nvim\docs\architecture.md) **by hand** — exactly the kind of document documentation.nvim is meant to replace (detect drift between documentation and code automatically instead of keeping them in sync manually). Costs only a `dev-dependency` plus `scripts/gen_map.lua`, with no runtime impact.

**d) Optionally extend the metrics report with documentation.nvim figures**
`:Insights metrics` already writes to a file or PDF ([commands.md:59-99](C:\repos\insights.nvim\docs\commands.md); PDF export was only just added, see the last commit). If a `docs/map/module_map.json` exists in the project (read-only, `pcall`, no hard dependency), the report could take over an additional section with documentation.nvim's structural figures (cyclomatic complexity, fan-in/out, duplicates, doc coverage) — instead of recomputing them. insights.nvim then delivers text/word statistics and documentation.nvim delivers structure — a joint report without duplicated code.

**e) The polyglot imports graph as a documented fallback**
`:Insights imports graph` already draws dependency graphs for Python/Go/Rust/C/C++ ([commands.md:273-301](C:\repos\insights.nvim\docs\commands.md)) — languages that documentation.nvim's backend, per its own [`docs/ROADMAP/MULTILANG.md`](C:\repos\documentation.nvim\docs\ROADMAP), has not reached at all yet. A pointer there to insights.nvim would keep somebody from building that language support in documentation.nvim from scratch, even though it already exists — leaner, but it exists.

---

## 4. What deliberately does **not** make sense

In the same convention of honesty the other two repos apply to themselves ("Deliberately not", [IDEAS.md §7](C:\repos\runtime-analysis.nvim\docs\IDEAS.md):415-424):

- **No merge, no adoption of modules.** documentation.nvim's value lies precisely in narrowness plus determinism (the CI byte comparison); insights.nvim's value lies in breadth plus interactivity. Merging them would dilute both.
- **insights.nvim should not depend hard on the other two** — the same rule documentation.nvim imposes on itself regarding runtime-analysis.nvim (never a hard dependency of a static/ad-hoc analysis tool on an optional runtime plugin).
- **`tree`, `fileinfo`, `compress`, `conflicts`, `unimported`, `devserver`** have no meaningful contact with the other two — pure editor-workflow automation, orthogonal to the documentation/runtime theme. Looking for a connection here artificially would be effort in the wrong direction.

---

## In short

insights.nvim is not a missing puzzle piece of the documented documentation.nvim/runtime-analysis.nvim ecosystem, but a **third, orthogonal tool** with a real distinguishing feature (polyglot, ad hoc, no IR/CI claim). The greatest immediate benefit lies not in deep code integration but in making that explicit: cross-link the READMEs (a) and note the two concrete redundancy candidates (`imports unused`, workspace symbols, point 2) in the other backlog, before something gets built twice there. After that, (b) telemetry self-instrumentation is the most worthwhile — cheap, uses existing infrastructure, and delivers real usage data for insights.nvim's own roadmap decisions.

---
