# Workflow — using insights.nvim day to day

Every feature here is documented on its own in `docs/FEATURES/`. This is
the different question: how symbols, metrics, imports, and the automatic
checks actually combine once you're using this against a real project
instead of reading one subcommand at a time.

## Symbols vs. imports — different questions, don't reach for the wrong one

`:Insights symbols` answers "where is X defined" (a picker over
functions/tables/strings). `:Insights imports` answers "what does this
file/project depend on" (a report over `require`/`import` statements,
optionally reversed to "who depends on X"). They share no code path and
answering the wrong question with the right-sounding command wastes a
trip: looking for callers of a function is neither of these — it's outside
this plugin's scope entirely (a call-hierarchy or grep task).

## Rebuild the symbol cache after a big restructure, not after every save

`:Insights symbols` is cache-backed (TTL + mtime-aware) precisely so it
doesn't re-run ripgrep on every invocation — normal edits stay covered by
mtime invalidation. The one case that needs an explicit
`:Insights symbols rebuild` (or `:Insights cache build`) is a bulk
operation the cache's mtime tracking won't necessarily catch cleanly, like
a mass file rename/move outside Neovim (a `git mv` from a shell, an
external refactor tool) — the picker may keep resolving to now-stale
paths until you force it.

## Metrics: pick flags for the question, not just `--ratios` out of habit

The report has a lot of surface area, and reaching for the full default
report every time buries the one number you actually wanted. A concrete
combination worth having as a habit: `--ratios --deviations` to find
folders whose comment/annotation ratio has drifted from the project
average (the actual "does this folder need doc attention" signal) rather
than reading the full file-by-file table looking for it. `--current`
scopes to just the open buffer — reach for that mid-edit instead of
re-running a whole-project report to check one file's own numbers.

## Imports `graph` needs `dot` on PATH and images.nvim — it degrades, doesn't fail loud

`:Insights imports graph` renders via Graphviz (`dot`) and displays
through the optional images.nvim dependency. Missing `dot` is caught by
`:checkhealth insights` (via `lib.nvim.deps`) ahead of time; missing
images.nvim specifically falls back to reporting the PNG's path instead of
showing it inline — worth knowing before assuming the command silently did
nothing. Reach for `graph` when you want the shape of a module's
dependencies at a glance; reach for the plain text report (with
`reverse`/`unused`) when you want exact `path:line` occurrences to act on.

## The three automatic checks are independent — enabling one doesn't imply the others

`conflicts` (on `VimEnter`), `unimported` (on `BufWritePost`), and
`devserver` (on terminal open/exit) each have their own `enable` key and
default `true` independently. If you only want `devserver`'s exit-cleanup
behavior without a conflict scan firing on every `VimEnter` in every repo
(including ones with no relation to your workflow), turn `conflicts.enable
= false` explicitly rather than assuming a shared "automation" toggle
exists — there isn't one.

## Dev-server tracking only ever sees terminals *this* Neovim started

The trap worth internalizing before relying on this: a dev server started
in a separate terminal application, a tmux pane outside Neovim, or a
`:terminal` in a *different* Neovim instance is invisible to
`devserver.enable` and will never be offered for kill-on-exit — by design,
so the feature never risks killing an unrelated process it can't actually
account for. If you regularly start dev servers outside Neovim, this
feature simply won't track them; that's not a bug to work around, it's the
deliberate boundary of what "this plugin owns" means here.

## The `symbols_*` keymaps can ask for more than functions in the cwd

Both keys used to bind exactly one question — cwd plus functions — with tables,
strings and buffer scope reachable only by typing `:Insights symbols`. They now
take either a plain lhs string, as before, or a table carrying a named `lhs`:

```lua
keymaps = {
  symbols_telescope = { lhs = "<leader>ps", scope = "buffer", type = "tables" },
  symbols_fzf       = { lhs = "<leader>pS", rebuild = true },
}
```

A table without an `lhs` string is reported rather than silently ignored.

There is deliberately **no `ui` field**: the UI is which of the two keys this
is, which is what their names already mean. An unknown scope or type is
reported and the default used, rather than passed down to a scanner that would
answer with a confusing "nothing found".

Worth setting once per config rather than per invocation: the point is to make
the question you ask most often a keypress, and leave the command for the rest.

## `:checkhealth insights` before debugging "why didn't rg find X"

Most silent-failure reports for the symbol/imports/metrics commands trace
back to a missing `rg` (ripgrep) or an unset `nvim-treesitter` Lua parser,
both of which `:checkhealth insights` reports directly (folded in with
`lib.nvim.deps`' own optional-tool audit from `docs/install.json`) — check
that before assuming a config mistake in `opts.symbols.languages` or
similar.
