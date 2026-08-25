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

  local changed = (type(original) == "boolean") and not original
    or (type(original) == "number") and (original + 1)
    or (tostring(original) .. "-changed")
  config.setup({ [key] = changed })
  H.eq(config.get()[key], changed, "a user value wins")
  H.eq(DEFAULTS[key], original, "DEFAULTS itself was not mutated")

  config.setup({})
  H.eq(config.get()[key], original, "setup({}) restores the defaults")
end
