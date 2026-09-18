-- TESTS/tree_windows_regex_spec.lua — the Windows branch of
-- insights.tree's exclude-glob-to-.NET-regex translation.
--
-- Regression, found in a 2026-09-18 bug/security review: the escaped-
-- metacharacter set covered `^$()%.[]+-?` but not `{`, `}`, `|`, or a
-- literal `\` itself. `{`/`}` are quantifiers to .NET (silently changing
-- what a pattern matches instead of erroring), and an unescaped `\`
-- followed by an ordinary letter -- exactly what a Windows-style exclude
-- glob written with native separators looks like, e.g. `*\legacy\*` --
-- makes `-match` throw "Unrecognized escape sequence" outright, failing
-- every file in the filter, not just the one bad pattern.
--
-- This only runs where it can be verified for real: `platform.is_windows()`
-- gates the code path itself, and `pwsh`/`powershell` has to actually be on
-- PATH to run the generated regex through .NET's own engine rather than
-- guessing at its behaviour.

return function(H)
  local tree = require("insights.tree")
  local platform = require("insights.util.platform")

  if not platform.is_windows() then
    print("      (skipped: insights.tree's regex escaping is Windows-only)")
    return
  end

  local pwsh = vim.fn.executable("pwsh") == 1 and "pwsh"
    or (vim.fn.executable("powershell") == 1 and "powershell")
  if not pwsh then
    print("      (skipped: neither pwsh nor powershell.exe on PATH)")
    return
  end

  ---Extract the single-quoted regex literals inside the `$rx=@(...)` array
  ---the real command builds, in order.
  ---@param cmd string
  ---@return string[]
  local function extract_regexes(cmd)
    local inner = cmd:match("%$rx=@%((.-)%)")
    H.ok(inner, "the command defines $rx when there are excludes -- got: " .. tostring(cmd))
    local out = {}
    for lit in inner:gmatch("'(.-)'") do
      out[#out + 1] = lit:gsub("''", "'") -- undo the command builder's own '' escaping
    end
    return out
  end

  ---Ask a real .NET regex engine whether `pattern` errors, and if not,
  ---whether it matches `subject`. Never raises: reports failure through the
  ---return value like `-match` itself would if it could.
  ---@param pattern string
  ---@param subject string
  ---@return boolean ok # false if the pattern itself was rejected
  ---@return boolean matched
  local function ps_match(pattern, subject)
    -- PowerShell single-quoted strings only need embedded `'` doubled.
    local script = string.format(
      [[
$ErrorActionPreference='Stop'
try {
  $m = '%s' -match '%s'
  if ($m) { Write-Output 'MATCH' } else { Write-Output 'NOMATCH' }
} catch {
  Write-Output 'ERROR'
}
]],
      subject:gsub("'", "''"),
      pattern:gsub("'", "''")
    )

    local out = vim.fn.system({ pwsh, "-NoProfile", "-NonInteractive", "-Command", script })
    local trimmed = out:gsub("%s+$", "")
    if trimmed == "ERROR" then
      return false, false
    end
    return true, trimmed == "MATCH"
  end

  local tree_internal = tree._internal
  H.ok(tree_internal and tree_internal.build_tree_cmd, "build_tree_cmd is exposed for testing")

  -- A backslash-spelled Windows exclude must not make the pattern itself
  -- invalid, and must still exclude the path it names.
  do
    local cmd = tree_internal.build_tree_cmd("C:\\proj", { "*\\legacy\\*" })
    local regexes = extract_regexes(cmd)
    H.eq(#regexes, 1, "one exclude glob produces one regex literal")

    local ok1, matched1 = ps_match(regexes[1], "C:\\proj\\legacy\\old.lua")
    H.ok(ok1, "a backslash-spelled exclude no longer makes -match throw")
    H.ok(matched1, "...and it still matches the path it was written to exclude")

    local ok2, matched2 = ps_match(regexes[1], "C:\\proj\\current\\new.lua")
    H.ok(ok2, "an unrelated path does not error either")
    H.ok(not matched2, "...and correctly does not match")
  end

  -- `{`/`}` must be treated as literal characters, not a .NET quantifier.
  do
    local cmd = tree_internal.build_tree_cmd("C:\\proj", { "*/cache{1,2}/*" })
    local regexes = extract_regexes(cmd)

    local ok_literal, matched_literal = ps_match(regexes[1], "C:/proj/cache{1,2}/x.lua")
    H.ok(ok_literal, "a glob containing { } does not error")
    H.ok(matched_literal, "...and matches the literal '{1,2}' text")

    -- If `{1,2}` were still a live quantifier on the preceding `e`, this
    -- unrelated path (no literal brace in it at all) would also match.
    local ok_not_quantifier, matched_not_quantifier = ps_match(regexes[1], "C:/proj/cacheee/x.lua")
    H.ok(ok_not_quantifier, "a plain path without braces does not error")
    H.ok(
      not matched_not_quantifier,
      "...and does not match -- { } is literal, not {1,2}-style repetition"
    )
  end

  -- `|` must be a literal pipe character, not regex alternation.
  do
    local cmd = tree_internal.build_tree_cmd("C:\\proj", { "*a|b*" })
    local regexes = extract_regexes(cmd)

    local ok_pipe, matched_pipe = ps_match(regexes[1], "xa|bx")
    H.ok(ok_pipe, "a glob containing | does not error")
    H.ok(matched_pipe, "...and matches the literal 'a|b' text")

    local ok_alt, matched_alt = ps_match(regexes[1], "xax")
    H.ok(ok_alt, "a path with only 'a' (no literal pipe) does not error either")
    H.ok(
      not matched_alt,
      "...and does not match -- | is literal, not alternation between 'a' and 'b'"
    )
  end
end
