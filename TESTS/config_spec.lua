-- TESTS/config_spec.lua — insights.config: the merge, and that DEFAULTS is not
-- mutated by it.

return function(H)
  local config = require("insights.config")
  local DEFAULTS = require("insights.config.DEFAULTS")

  local key, original
  for k, v in pairs(DEFAULTS) do
    if type(v) == "string" or type(v) == "number" or type(v) == "boolean" then
      key, original = k, v
      break
    end
  end
  H.ok(key, "DEFAULTS has at least one scalar option to test against")

  local fresh = config.get()
  H.eq(fresh[key], original, "get() before setup() returns the defaults")
  H.ok(fresh ~= DEFAULTS, "as a copy, not the DEFAULTS table itself")

  -- An explicit if/elseif here, not `a and b or c`: for a boolean `original`
  -- of `true`, `not original` is `false` -- itself falsy -- which would make
  -- that chained form fall through to the string branch instead (ERR-60).
  local changed
  if type(original) == "boolean" then
    changed = not original
  elseif type(original) == "number" then
    changed = original + 1
  else
    changed = original .. "-changed"
  end
  config.setup({ [key] = changed })
  H.eq(config.get()[key], changed, "a same-type user value wins")
  H.eq(DEFAULTS[key], original, "DEFAULTS itself was not mutated")

  config.setup({})
  H.eq(config.get()[key], original, "setup({}) restores the defaults")

  -- A top-level value of the wrong type must degrade to its default instead
  -- of letting the merge replace a required sub-table with it -- every later
  -- consumer indexing into that sub-table would otherwise crash plugin
  -- initialisation entirely (ERR-22).
  ---@diagnostic disable-next-line: assign-type-mismatch
  config.setup({ compress = false })
  H.eq(
    config.get().compress.enable,
    DEFAULTS.compress.enable,
    "a mistyped table field falls back to its default instead of crashing"
  )
  H.ok(#config.issues() > 0, "and the mismatch is recorded")
  H.contains(config.issues()[1], "compress", "naming the offending key")

  config.setup({})
  H.eq(#config.issues(), 0, "a clean setup() reports no issues")

  -- An unknown nested key must not vanish silently into the default
  -- (ERR-50): it is warned about, with a "did you mean" hint against its
  -- sibling keys when a close one exists.
  config.setup({ symbols = { langauges = { lua = true } } })
  H.ok(#config.issues() > 0, "an unknown nested key is recorded")
  H.contains(config.issues()[1], "symbols.langauges", "with its full dotted path")
  H.contains(config.issues()[1], "did you mean `languages`?", "and a suggestion")

  config.setup({})

  -- `vim.tbl_deep_extend("force", defaults, opts)` shares references for any
  -- sub-table `opts` never mentions -- a nested subtree of `current` that
  -- setup() (via expand_paths) or any later caller writes into would then
  -- silently mutate DEFAULTS itself. Cover this with a top-level table that
  -- `setup({ symbols = ... })` never touches, and mutate a leaf directly the
  -- way expand_paths does.
  config.setup({ symbols = { enable = not DEFAULTS.symbols.enable } })
  local metrics_before = DEFAULTS.metrics.output_file
  H.ok(
    config.get().metrics ~= DEFAULTS.metrics,
    "an untouched sub-table is a copy, not a reference into DEFAULTS"
  )
  config.get().metrics.output_file = "LEAK-CHECK"
  H.eq(
    DEFAULTS.metrics.output_file,
    metrics_before,
    "mutating current's copy left DEFAULTS untouched"
  )

  config.setup({})

  -- expand_paths ---------------------------------------------------------------
  -- Five path fields are run through lib.nvim's `expand_path` on every
  -- setup(). The defaults come from `stdpath()` and are already absolute, so
  -- the call is a no-op on them -- which means this branch is only ever
  -- exercised by a user value, and only ever here.
  local home = vim.fn.expand("~")
  config.setup({
    symbols = { cache = { dir = "~/insights-cache" } },
    metrics = { output_file = "~/insights-metrics.md" },
    tree = { outdir = "~/insights-tree" },
    imports = { output_file = "~/insights-imports.md" },
  })
  local expanded = config.get()
  H.contains(expanded.symbols.cache.dir, home, "the cache directory is expanded")
  H.excludes(expanded.symbols.cache.dir, "~", "with no tilde left in it")
  H.contains(expanded.metrics.output_file, home, "and the metrics output file")
  H.contains(expanded.tree.outdir, home, "and the tree output directory")
  H.contains(expanded.imports.output_file, home, "and the imports output file")

  -- `compress.outdir` is the one that is only expanded when it is set: its
  -- default is the empty string, which means "next to the source directory"
  -- and must not become the expansion of "".
  H.eq(config.get().compress.outdir, "", "an empty compress outdir stays empty")
  config.setup({ compress = { outdir = "~/insights-archives" } })
  H.contains(config.get().compress.outdir, home, "a set one is expanded like the rest")

  config.setup({})
end
