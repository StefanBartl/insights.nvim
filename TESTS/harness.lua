-- TESTS/harness.lua — tiny assertion helper shared by the spec files.
-- Returned to each spec by TESTS/run.lua.

local H = {}

--- Assert equality; raises a descriptive error on mismatch (caught by the runner).
---@param a any # actual
---@param b any # expected
---@param msg string|nil
function H.eq(a, b, msg)
  if a ~= b then
    error(("FAIL %s: expected %q, got %q"):format(msg or "", tostring(b), tostring(a)), 2)
  end
end

--- Assert a truthy value.
---@param v any
---@param msg string|nil
function H.ok(v, msg)
  if not v then
    error(("FAIL %s: expected truthy, got %q"):format(msg or "", tostring(v)), 2)
  end
end

--- Assert a falsy value.
---@param v any
---@param msg string|nil
function H.falsy(v, msg)
  if v then
    error(("FAIL %s: expected falsy, got %q"):format(msg or "", tostring(v)), 2)
  end
end

--- Assert that `haystack` contains `needle` as a literal substring.
---@param haystack string
---@param needle string
---@param msg string|nil
function H.contains(haystack, needle, msg)
  if type(haystack) ~= "string" or not haystack:find(needle, 1, true) then
    error(("FAIL %s: %q does not contain %q"):format(msg or "", tostring(haystack), needle), 2)
  end
end

--- Assert that `haystack` does NOT contain `needle`.
---@param haystack string
---@param needle string
---@param msg string|nil
function H.excludes(haystack, needle, msg)
  if type(haystack) == "string" and haystack:find(needle, 1, true) then
    error(("FAIL %s: %q still contains %q"):format(msg or "", tostring(haystack), needle), 2)
  end
end

--- A scratch directory inside the repository, removed by `cleanup()`.
---
--- Inside the repo rather than in `vim.fn.tempname()` on purpose: on Windows
--- the temp path carries an 8.3 short component (`STEFAN~1`), which several
--- Vim path builtins do not see through -- a fixture there would pass on Linux
--- and quietly assert nothing locally.
---@param name string
---@return string dir, fun() cleanup
function H.fixture(name)
  local dir = vim.fs.normalize(vim.fn.getcwd()) .. "/TESTS/.fixture-" .. name
  vim.fn.delete(dir, "rf")
  vim.fn.mkdir(dir, "p")
  return dir, function()
    vim.fn.delete(dir, "rf")
  end
end

--- Read a file back as one string.
---@param path string
---@return string
function H.read(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or type(lines) ~= "table" then
    return ""
  end
  return table.concat(lines, "\n")
end

return H
