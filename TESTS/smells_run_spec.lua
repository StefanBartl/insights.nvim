-- TESTS/smells_run_spec.lua — the report `:Insights smells` opens.
--
-- The two scans themselves are covered in `smells_spec.lua`; what is left is
-- the part the command drives: which scans run for which flags, and what the
-- report looks like when one of them is switched off. The scratch buffer is
-- replaced so the lines can be read instead of rendered.

return function(H)
  local smells = require("insights.smells")

  local dir, cleanup = H.fixture("smells-run")
  local real_scratch = package.loaded["insights.ui.scratch"]

  ---@param rel string
  ---@param lines string[]
  local function write(rel, lines)
    local path = dir .. "/" .. rel
    vim.fn.mkdir(vim.fs.dirname(path), "p")
    vim.fn.writefile(lines, path)
  end

  write("lua/proj/config/init.lua", { "local M = {}", "M.defaults = { known = 1 }", "return M" })
  write("lua/proj/feature.lua", {
    "local MAX_RETRIES = 5",
    "local function go()",
    "  vim.defer_fn(function() end, 3000)",
    "end",
    "return go",
  })

  local shown
  package.loaded["insights.ui.scratch"] = {
    open = function(lines, title)
      shown = { lines = lines, title = title }
      return 1
    end,
  }

  local ok_body, err_body = pcall(function()
    -- Both scans, which is the default.
    shown = nil
    smells.run({ root = dir })
    H.ok(shown, "run opens a report")
    H.contains(shown.title or "", "Smells", "titled for the feature")
    H.contains(shown.lines[1], "=== Code Smells ===", "with the report header")
    H.contains(shown.lines[2], "Root: ", "naming the root it scanned")

    local text = table.concat(shown.lines, "\n")
    H.contains(text, "-- Magic numbers: 1", "the magic-number scan ran")
    H.contains(text, "defer", "and names the kind it found")
    H.contains(text, "3000", "and the value")
    H.contains(text, "-- Hardcoded constants: 1", "the constant scan ran too")
    H.contains(text, "MAX_RETRIES", "and names the constant")
    H.contains(text, "feature.lua:1", "with a path:line reference")

    -- `--magic-numbers-only`
    shown = nil
    smells.run({ root = dir, hardcoded_constants = false })
    local magic_only = table.concat(shown.lines, "\n")
    H.contains(magic_only, "-- Magic numbers:", "magic-numbers-only keeps that section")
    H.excludes(magic_only, "Hardcoded constants", "and drops the other one entirely")

    -- `--constants-only`
    shown = nil
    smells.run({ root = dir, magic_numbers = false })
    local const_only = table.concat(shown.lines, "\n")
    H.contains(const_only, "-- Hardcoded constants:", "constants-only keeps that section")
    H.excludes(const_only, "Magic numbers", "and drops the other one")

    -- Both off: a report with a header and nothing else, rather than an error.
    shown = nil
    smells.run({ root = dir, magic_numbers = false, hardcoded_constants = false })
    H.ok(shown, "with both scans off there is still a report")
    H.eq(#shown.lines, 3, "holding only its header")

    -- No root given means the working directory, and the suite runs from this
    -- repository -- so this is also the one run over real source.
    shown = nil
    smells.run()
    H.ok(shown, "run() with no options scans the working directory")
    H.contains(shown.lines[2], vim.fs.normalize(vim.fn.getcwd()), "naming it as the root")

    -- A root that is not a directory is refused before either scan starts.
    shown = nil
    smells.run({ root = dir .. "/lua/proj/feature.lua" })
    H.eq(shown, nil, "a file is not a root, and nothing is opened")

    shown = nil
    smells.run({ root = dir .. "/does-not-exist" })
    H.eq(shown, nil, "and neither is a directory that is not there")

    -- An empty root string falls back to the working directory rather than
    -- scanning "".
    shown = nil
    smells.run({ root = "" })
    H.ok(shown, "an empty root falls back to the working directory")
  end)

  package.loaded["insights.ui.scratch"] = real_scratch
  cleanup()

  if not ok_body then
    error(err_body, 0)
  end
end
