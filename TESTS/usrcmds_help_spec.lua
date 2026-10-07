-- TESTS/usrcmds_help_spec.lua -- every flag of `:Insights` has a line in the option float.
--
-- lib.nvim's help float (the option cheatsheet on the command line) shows one
-- line per `--flag` / `key=`, taken from the `desc` of its spec. This pins that
-- no flag of the verb ships without one, and that the lines stay what the float
-- expects: one short line, no trailing full stop.

return function(H)
  local composer = require("lib.nvim.bindings.usercmd.composer")
  local entries = require("lib.nvim.bindings.usercmd.composer.help.entries")

  require("insights.config").setup({})
  require("insights.bindings.usrcmds").setup()

  local missing = composer.help.undocumented("Insights")
  local names = {}
  for _, m in ipairs(missing) do
    names[#names + 1] = ("%s %s %s"):format(m.route, m.kind, m.name)
  end
  H.eq(
    #missing,
    0,
    "every :Insights flag has a description (missing: " .. table.concat(names, ", ") .. ")"
  )

  local handle = composer.registry().Insights
  H.ok(handle, ":Insights is registered")

  local seen = 0
  for _, route in ipairs(handle:spec().routes or {}) do
    for _, flag in ipairs(route.flags or {}) do
      seen = seen + 1
      local text = entries.flag_desc(route, flag)
      H.ok(text and text ~= "", "--" .. flag.name .. " shows a text")
      H.ok(not text:find("\n", 1, true), "--" .. flag.name .. " is one line")
      H.ok(#text <= 80, "--" .. flag.name .. " stays short (" .. #text .. " chars)")
      H.ok(not text:find("%.$"), "--" .. flag.name .. " has no trailing full stop")
    end
  end
  H.ok(seen > 0, "the routes' flags were actually walked")

  -- A negation without a text of its own reads "Off: <text of the positive>".
  for _, route in ipairs(handle:spec().routes or {}) do
    if route.path[1] == "metrics" then
      for _, flag in ipairs(route.flags) do
        if flag.name == "no-ratios" then
          H.eq(
            entries.flag_desc(route, flag),
            "Off: Per-folder comment, doc and code ratios",
            "--no-ratios derives its text from --ratios"
          )
        end
      end
    end
  end
end
