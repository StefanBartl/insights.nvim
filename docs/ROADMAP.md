# Roadmap

Planned and proposed work for insights.nvim. Items are not ordered by
priority.

Nothing currently open. The multi-language import scan (Python, JS/TS, Go,
Rust, C/C++) and the imports backlog (picker output, reverse view, unused-
import detection) shipped — see [commands.md](commands.md#imports) and
[architecture.md](architecture.md).

`:Insights imports graph` also shipped: the dependency data `imports`
already collects, rendered as a Graphviz PNG and shown via images.nvim
(from images.nvim's own `docs/ROADMAP/CROSS-PLUGIN.md` — see
[commands.md](commands.md#graph-view)). Deliberately scoped to that one
graph-shaped dataset; call-tree/symbol-distribution graphs would need new
analysis this plugin doesn't have yet, not just a new view over existing
data.

## `docs/ROADMAP/` — design notes, audits, concepts

Everything below lives in [`docs/ROADMAP/`](ROADMAP/) and is **not** open work
unless it says so. Indexed here because a folder next to a file is easy to
miss, and these are the documents that explain *why* the plugin is shaped the
way it is.

| Document | What it is |
| --- | --- |
| [`NEOTREE_FEATURES.md`](ROADMAP/NEOTREE_FEATURES.md) | Which of this plugin's features are worth porting into filetree.nvim. |
| [`SYNERGIE_DocMap_RTTelemetry.md`](ROADMAP/SYNERGIE_DocMap_RTTelemetry.md) | Where insights.nvim, documentation.nvim and runtime-analysis.nvim overlap, and who should own what. |

The audits share a convention: **✅ good · 🟡 partial · ❌ gap**.
Findings that were acted on are removed rather than ticked, so what is left
standing is either an open gap or a deliberate deviation with its reasoning.
