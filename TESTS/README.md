# TESTS/

Headless spec suite. Every spec drives a module directly — no picker, no
window, no project scan of anything but its own fixtures.

```
nvim --headless -u NONE -c "set rtp+=." -l TESTS/run.lua
```

Exit 0 is a pass; the runner prints one line per spec and exits non-zero on the
first failure. CI runs exactly this command.

## lib.nvim

Several modules require lib.nvim at module load, so the suite cannot run
without it. `run.lua` resolves it in this order:

1. `$LIB_NVIM_PATH`
2. a sibling checkout, `../lib.nvim`
3. the lazy.nvim-managed copy under `stdpath("data")/lazy/lib.nvim`

A sibling wins over the plugin-manager copy on purpose: that one is often older
than the working checkout, and testing against a stale lib.nvim gives
misleading failures.

## The specs

| | |
| --- | --- |
| `import_util_spec.lua` | byte-offset to line-number mapping, and the depth-aware splitter the grouped-import forms need |
| `lua_imports_spec.lua` | which `require` calls the Lua scanner reports, internal vs external, and what a dynamic require currently does |
| `devserver_spec.lua` | the pattern match that decides whether a terminal job is a dev server, and the tracking ledger |
| `config_spec.lua` | the merge, and that `DEFAULTS` survives it unmutated |

Adding one: write `TESTS/<name>_spec.lua` returning `function(H) ... end`, then
list it in `run.lua`. `H` is the harness — `eq`, `ok`, `falsy`, `contains`,
`excludes`, `read` and `fixture`.

## What is deliberately not here

`devserver.kill_tree` spawns and kills a real process tree; the conflicts and
compress features shell out to `git` and an archiver. Those belong to a manual
pass, not to a suite that has to be fast and side-effect-free on every push.
