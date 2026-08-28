-- TESTS/smells_spec.lua — insights.smells: magic numbers + hardcoded
-- (unconfigured) constants.

return function(H)
  local eq, ok = H.eq, H.ok
  local smells = require("insights.smells")

  local dir, cleanup = H.fixture("smells")

  ---@param rel string
  ---@param content string
  local function write(rel, content)
    local path = dir .. "/" .. rel
    vim.fn.mkdir(vim.fs.dirname(path), "p")
    vim.fn.writefile(vim.split(content, "\n", { plain = true }), path)
  end

  write(
    "lua/proj/config/init.lua",
    table.concat({
      "local M = {}",
      "M.defaults = {",
      "  retry_limit = 3,",
      "}",
      "return M",
    }, "\n")
  )
  write(
    "lua/proj/feature/thing.lua",
    table.concat({
      "local M = {}",
      "",
      "-- a comment mentioning vim.defer_fn(x, 9999) is not code",
      "local MAX_RETRIES = 5",
      "local retry_limit = 7",
      "local timeout_ms = 200",
      'local greeting = "hello"',
      "",
      "function M.setup()",
      "  vim.defer_fn(function() end, 3000)",
      "  vim.defer_fn(function() end, 10)",
      "  vim.wait(500)",
      "  local w = vim.o.columns * 0.8",
      "end",
      "",
      "return M",
    }, "\n")
  )

  -- ------------------------------------------------------ magic_numbers

  local magic = smells.magic_numbers(dir)
  eq(#magic, 3, "one hit each for defer(3000)/wait(500)/frac_cols(0.8)")

  local kinds = {}
  for _, h in ipairs(magic) do
    kinds[h.kind] = h.value
  end
  eq(kinds.defer, "3000", "defer(3000) is flagged")
  eq(kinds.wait, "500", "wait(500) is flagged")
  eq(kinds.frac_cols, "0.8", "columns * 0.8 is flagged")
  ok(not kinds.timer, "no timer:start() call in the fixture")

  for _, h in ipairs(magic) do
    ok(h.value ~= "10", "defer(10) is under TICK_MAX and never flagged")
    ok(h.value ~= "9999", "the number inside a comment is never flagged")
  end

  -- --------------------------------------------------- hardcoded_constants

  local const = smells.hardcoded_constants(dir)
  eq(#const, 2, "MAX_RETRIES and timeout_ms, not retry_limit (already configurable)")

  local names = {}
  for _, h in ipairs(const) do
    names[h.name] = h.value
  end
  eq(names.MAX_RETRIES, "5", "SCREAMING_CASE constant, not reachable from config -> flagged")
  eq(names.timeout_ms, "200", "lowercase behaviour-named constant -> flagged")
  ok(not names.retry_limit, "retry_limit already appears in config/init.lua -> not flagged")
  ok(not names.greeting, "a string with no behaviour-word in its name is never flagged")

  -- ------------------------------------------------------------- run()

  -- run() must not error with either scan disabled, or with no config
  -- surface present at all (empty config_blob -> hardcoded_constants
  -- returns {} rather than flagging everything).
  local lone_dir, lone_cleanup = H.fixture("smells-no-config")
  local lone_path = lone_dir .. "/lua/solo/init.lua"
  vim.fn.mkdir(vim.fs.dirname(lone_path), "p")
  vim.fn.writefile({ "local MAX_THINGS = 9", "return {}" }, lone_path)
  eq(#smells.hardcoded_constants(lone_dir), 0, "no config surface at all -> nothing flagged")
  lone_cleanup()

  cleanup()
end
