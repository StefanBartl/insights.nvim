# Who imports this — in hover.nvim's float

Rest the cursor on a dotted module name and the float says which files import
it, out of the scan `:Insights imports` already ran.

```
┌ insights.imports ─────────────────────┐
│ 7 file(s) import this, 18 occurrence(s)│
│                                        │
│   TESTS/registry_spec.lua              │
│   lua/hover/init.lua                   │
│   scripts/onrequest_probe.lua          │
└────────────────────────────────────────┘
```

Registered with [hover.nvim](https://github.com/StefanBartl/hover.nvim) as a
**position** preview: the answer is about the *place* the cursor is in rather
than about a target it points at, so nothing is opened and nothing is
classified. `hover = false` in `setup()` turns it off; without hover.nvim
installed nothing is registered and nothing is missing.

## It never starts a scan

This is the property everything else follows from. A full import scan walks the
working directory, reads every source file and parses it. Measured 2026-09-03:

| Tree | Full scan | Lookup afterwards |
| --- | --- | --- |
| hover.nvim | 631 ms | **28 µs** |
| insights.nvim | 715 ms | — |
| documentation.nvim | 1.9 s | — |

A hover that could set off the left-hand column from a cursor movement is
exactly what hover.nvim's opt-in model exists to prevent — and the failure
would be invisible, because the float would simply feel slow.

So the preview reads `insights.imports.reverse_lookup`, which answers out of
the remembered scan **or answers nothing**. Until `:Insights imports` (or any
other full scan) has run once in this session, this preview is silent.

`:checkhealth insights` says so, under **Hover contribution** — from outside a
float that never opens, "quiet" and "broken" look identical.

## A module nobody imports is silence, not a zero

Every dotted name looks like a module: `a.b.c` in a comment, `read.write.exec`
in prose. Answering "0 files import this" for each of them would be the noise
the position kind was built to avoid.

So the importer count *is* the gate. Something imports it, or there is nothing
here worth interrupting a reader for.

## A stale index says so

A write marks the index stale, and the flag comes back with the answer:

```
! a file was written since this was scanned
```

The list is not thrown away for it. An import list from before your last save
is usually still right, and hiding that it might not be is the one thing worse
than saying nothing — the same stance documentation.nvim's map preview takes,
for the same reason.

`:Insights imports reverse` is stricter, and deliberately: it re-scans when the
index is stale. An explicit report is the one place where waiting is the honest
choice.

## Sharing the float with documentation.nvim

Both plugins answer for a dotted name and both are right: documentation.nvim
says *what the module is*, this one says *who uses it*.

hover.nvim steps between them — `<M-n>`, or `:Hover next` — so the second
answer is a page rather than a casualty. Before that existed, the first plugin
to register won and the other was invisible, which plugin load order decided.

## Soft in every direction

- **Without hover.nvim** — `setup()` looks for `hover.registry`, does not find
  it, and returns.
- **With an older hover.nvim** that has a registry but no position kind, the
  integration declines rather than registering something that would be
  silently ignored.
- **With a cold index** — nothing is said, and nothing is started.
- **With `hover = false`** — nothing is registered at all.
