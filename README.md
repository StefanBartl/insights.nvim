> **Beta stage — active development.** This repository is past its first shape and in
> active use, but the surface is not frozen: breaking changes are still possible. Pin a
> commit or tag if you depend on it.

# insights.nvim

```
 _         _      _   _
(_)_ _  __(_)__ _| |_| |_ ___
| | ' \(_-< / _` | ' \  _(_-<
|_|_||_/__/_\__, |_||_\__/__/
            |___/
      .nvim
```

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Neovim](https://img.shields.io/badge/Neovim-0.9%2B-57A143?logo=neovim&logoColor=white)](https://neovim.io)
[![Lua](https://img.shields.io/badge/Lua-5.1%2FLuaJIT-2C2D72?logo=lua&logoColor=white)](https://www.lua.org)
![Status](https://img.shields.io/badge/status-beta-orange)
![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20Windows-lightgrey)

Static analysis of the project you are in, from inside Neovim.

One `:Insights` command over symbol indexing, multi-language import analysis,
Lua code metrics, file-tree utilities, and automatic checks for git conflicts,
unused imports and stray dev servers.

---

## Table of contents

- [Documentation](#documentation)
- [What it does](#what-it-does)
- [Around it](#around-it)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quickstart](#quickstart)
- [What you get with the defaults](#what-you-get-with-the-defaults)
- [Health check](#health-check)
- [Contributing](#contributing)
- [Feedback](#feedback)
- [License](#license)

---

## Documentation

Start at [docs/README.md](docs/README.md), which says what is where and which
question each page answers.

- [Features](docs/FEATURES/README.md) — every module and what it does.
- [Installation](docs/installation.md) — requirements, every package manager, health check.
- [Commands](docs/commands.md) — the full `:Insights` subcommand reference, flags, and symbol types.
- [Automatic triggers](docs/automatic-triggers.md) — the `conflicts`, `unimported` and `devserver` autocmds, and how dev-server tracking works.
- [Configuration](docs/configuration.md) — every `setup()` option and its default.
- [Architecture](docs/architecture.md) — source tree layout and module responsibilities.
- [Bindings reference](docs/BINDINGS.md) — every keymap, user command and autocmd the plugin registers.
- [Hover](docs/hover.md) — the hover.nvim contribution: why a cold index says nothing, and why a module nobody imports is silence rather than a zero.
- [Workflow](docs/WORKFLOW.md) — which feature answers which everyday question about a codebase, rather than what each one does.
- [Health](docs/health.md) — the thirteen `:checkhealth insights` sections, and which findings are actually problems.
- [Contributing](docs/CONTRIBUTING.md) — ground rules, project layout, and how to add an analysis.

`:help insights` is the same reference inside the editor.

---

## What it does

Every question here is one you can answer by reading the source — which is
exactly why nobody does. "Who imports this?", "is this import still used?",
"which numbers in this file are magic?" are cheap to ask and expensive to
answer by hand, and they go unasked until something breaks.

`:Insights` is the one command that asks them:

| Area | Answers |
| --- | --- |
| **Symbols** | A ripgrep/Tree-sitter index of functions, Lua tables and string literals, behind a picker |
| **Imports** | Usage across Lua, Python, JS/TS, Go, Rust and C/C++ — a report, a reverse lookup, unused-import detection, and a rendered dependency graph |
| **Code** | Lua metrics, and smells: magic numbers and behaviour constants that should have been configuration |
| **Project** | The file tree written, counted or copied; per-buffer `fs.stat`; directory compression with the engine auto-detected |
| **Automatic** | Git conflicts to the quickfix list on `VimEnter`, used-but-unimported components in the current buffer, and dev servers started from Neovim that are still running |

The symbol index is cached, and the cache is explicit rather than magic:
`:Insights cache build`, `info`, `clear`. That matters for the hover
contribution — a cold index says nothing rather than starting a scan behind
your back, and a module nobody imports produces silence rather than a
misleading zero. The reasoning is [docs/hover.md](docs/hover.md).

It reads the source text. What was *actually called* at runtime is a different
question, and a parser cannot answer it — see
[runtime-analysis.nvim](https://github.com/StefanBartl/runtime-analysis.nvim)
below.

---

## Around it

> **[runtime-analysis.nvim](https://github.com/StefanBartl/runtime-analysis.nvim)** —
> the counter-check. insights reads the source for what looks unused; that one
> measures whether it was ever really called. A parser cannot see a callback, and
> a counter cannot see dead text.
>
> **[buffer-ctx.nvim](https://github.com/StefanBartl/buffer-ctx.nvim)** — inserts
> or copies the current buffer's path and module name, the same resolution
> `:Insights imports` uses.
>
> **[hover.nvim](https://github.com/StefanBartl/hover.nvim)** — shows who imports
> the module under the cursor, out of a scan that already ran.
>
> **[images.nvim](https://github.com/StefanBartl/images.nvim)** — renders the
> dependency graph in the editor rather than writing a PNG you then have to open.
>
> All of the above are soft: without them everything else works unchanged.
> [lib.nvim](https://github.com/StefanBartl/lib.nvim) and `rg` are the real
> dependencies — see [Requirements](#requirements).

---

## Requirements

| | |
| --- | --- |
| Neovim | **0.9+** |
| [lib.nvim](https://github.com/StefanBartl/lib.nvim) | required — the `:Insights` command tree and the shared helpers |
| `rg` (ripgrep) | required — the scan every analysis is built on |

Optional, each detected at runtime and degrading to nothing when absent:

| | |
| --- | --- |
| `dot` (graphviz) | Layout for `:Insights imports graph` |
| [images.nvim](https://github.com/StefanBartl/images.nvim) | The rendered graph shown in the editor |
| Tree-sitter parsers | Sharper symbol indexing than the ripgrep fallback |
| telescope.nvim / fzf-lua | The symbol picker front ends |
| [hover.nvim](https://github.com/StefanBartl/hover.nvim) | Reverse-import info in a float |

`rg` and `dot` are declared in [docs/install.json](docs/install.json) and read by
lib.nvim's
[deps module](https://github.com/StefanBartl/lib.nvim/blob/main/lua/lib/nvim/deps/README.md).
A popup explains what is missing the first time `setup()` runs after installing;
`:Lib deps show insights.nvim` repeats it any time, and it is folded into
`:checkhealth insights`. Turn the popup off in this plugin's own spec with
`deps_popup = false`, or globally with
`vim.g.lib_nvim_deps_disable_first_run = true`.

---

## Installation

```lua
-- lazy.nvim
{
  "StefanBartl/insights.nvim",
  dependencies = { "StefanBartl/lib.nvim" },
  cmd = "Insights",
  keys = {
    { "<leader>ps", desc = "Project symbols (telescope)" },
    { "<leader>pS", desc = "Project symbols (fzf)" },
  },
  opts = {},
}
```

`cmd` plus `keys`: the command trigger covers the analyses you ask for, and the
key trigger covers the picker you reach for without thinking about which plugin
provides it. Other package managers are in
[docs/installation.md](docs/installation.md).

Note that the automatic checks (git conflicts on `VimEnter`, dev-server tracking)
only run once the plugin has loaded — see
[docs/automatic-triggers.md](docs/automatic-triggers.md) if you want them from
the first second of a session.

---

## Quickstart

Open any file in the project and ask the question you would otherwise have
grepped for:

```vim
:Insights symbols
```

Then the rest:

```vim
:Insights imports                    " import/require usage, multi-language
:Insights imports reverse foo.bar    " every file that imports this module
:Insights imports unused             " bound names never referenced again
:Insights metrics                    " Lua code metrics
:Insights smells                     " magic numbers and unconfigured constants
:Insights tree                       " write the project file tree to a file
```

Verify your setup any time with:

```vim
:checkhealth insights
```

---

## What you get with the defaults

| Command | Does |
| --- | --- |
| `:Insights symbols` | ripgrep/Tree-sitter symbol index and picker: functions, Lua tables, string literals |
| `:Insights metrics` | Lua code metrics report |
| `:Insights smells` | Magic numbers and unconfigured behaviour constants |
| `:Insights imports` | Import/require usage across Lua, Python, JS/TS, Go, Rust, C/C++ |
| `:Insights imports reverse <module>` | Every file that imports a given module |
| `:Insights imports unused` | Bound import names never referenced again in their file |
| `:Insights imports graph` | The dependency graph, rendered as a PNG |
| `:Insights tree` / `count` / `clipboard` | Write, count, or copy the project file tree |
| `:Insights fileinfo` | Toggle an `fs.stat` float for the current buffer |
| `:Insights cache build` / `info` / `clear` | Rebuild, inspect or clear the symbol cache |
| `:Insights compress [path] [outdir]` | Archive a directory — tar, zip or PowerShell, engine auto-detected |
| `:Insights conflicts` | Unresolved git conflicts to the quickfix list; also runs on `VimEnter` |
| `:Insights unimported` | Used-but-unimported components in the current buffer |
| `:Insights devserver list` / `kill` | Dev servers started from Neovim |

Plus one thing with no command at all: who imports the module under the cursor,
in [hover.nvim](https://github.com/StefanBartl/hover.nvim)'s float — out of a
scan that already ran, never starting one. The full surface, with flags and
symbol types, is [docs/commands.md](docs/commands.md).

---

## Health check

```vim
:checkhealth insights
```

Thirteen sections: whether `rg` and `dot` are reachable, which Tree-sitter
parsers are installed, which picker backend resolved, the state and age of the
symbol cache, and which automatic triggers are armed.
[docs/health.md](docs/health.md) says which findings are actually problems —
several of them are informational and routinely misread as failures.

---

## Contributing

Clone the repository and either symlink it or add it to your runtime path.
[docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) has the ground rules and the project
layout; [docs/architecture.md](docs/architecture.md) says which module owns what,
and where a new analysis plugs in.

Pull requests very welcome.

---

## Feedback

Your feedback is very welcome. Use the
[issue tracker](https://github.com/StefanBartl/insights.nvim/issues) to report
bugs, suggest features or ask usage questions; anything more open-ended fits a
[discussion](https://github.com/StefanBartl/insights.nvim/discussions).

If you find this plugin useful, a ⭐ on GitHub supports its development.

---

## License

MIT — see [LICENSE](LICENSE).
