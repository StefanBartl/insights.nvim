-- .testing.lua -- configuration of testing.nvim for this project.
-- Written by `testing migrate`; edit freely (it is never overwritten). Every key is optional; the
-- keys are documented in testing.nvim's docs/CONFIG.md. Loading this file executes it (same trust
-- as running the specs).
return {
  -- Lua module root of the project.
  plugin = "insights",
  -- How the spec files are run: "auto" = sniffed per file, "h" = on the project's own TESTS/harness.lua,
  -- "script" = a self-running script in its own process.
  dialect = "h",
  -- Dependencies (directory names) put on the runtimepath: $<NAME>_DIR, .deps/<name>, ../<name>,
  -- stdpath('data')/lazy/<name>.
  deps = { "lib.nvim" },
  -- One nvim per spec file: health_init_spec runs setup() end to end and leaves global state that
  -- breaks imports_definition_spec when it runs after it (the old fixed order hid that).
  isolated = "file",
  -- tree_windows_regex_spec returns early (no assertions) off Windows; the old runner passed that.
  assertions = "warn",
  -- Guards: every net runs in error mode; the suite passes them cleanly with the allowlist below.
  guards = {
    fs = "error",
    state = "error",
    scheduled_error = "error",
    prompt = "error",
    deprecation = "error",
    process_net = "error",
  },
  guard_allow = {
    -- The specs build and remove their fixtures in TESTS/.fixture-* inside the repository (scan
    -- cache dirs, compress/imports/metrics trees); the fixture names are generated per spec.
    fs = { "TESTS" },
    spawn = {
      -- devserver specs start a throwaway headless nvim as the dev server they track and kill.
      "nvim",
      -- tree_windows_regex_spec asks PowerShell for the real -match result of the Windows path regex.
      "pwsh",
      -- nvim's own Python provider probe (python3 -c "import neovim") runs when the symbols specs
      -- touch the provider machinery; it only exists on machines that have python3 on PATH (CI).
      -- The executable name is the interpreter of the runner image (exact match only).
      "python",
      "python3",
      "python3.12",
      "python3.13",
      "python3.14",
    },
  },
}
