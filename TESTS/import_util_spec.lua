-- TESTS/import_util_spec.lua — insights.imports.langs.util: the byte-offset to
-- line-number mapping every language scanner reports through, and the splitter
-- the grouped-import forms are parsed with.

return function(H)
  local util = require("insights.imports.langs.util")

  -- line_starts ---------------------------------------------------------------
  H.eq(#util.line_starts("one"), 1, "a source with no newline is one line")
  H.eq(#util.line_starts("a\nb\nc"), 3, "one entry per line")
  H.eq(util.line_starts("a\nb")[2], 3, "the second line starts after the newline")
  H.eq(#util.line_starts(""), 1, "an empty source still has a first line")

  -- A trailing newline does not open a further line of content, but it does
  -- create a start offset -- pinned so the off-by-one is a decision, not drift.
  H.eq(#util.line_starts("a\n"), 2, "a trailing newline yields a start for the empty last line")

  -- lnum_at -------------------------------------------------------------------
  local starts = util.line_starts("aaa\nbbb\nccc")
  H.eq(util.lnum_at(starts, 1), 1, "the very first byte is on line 1")
  H.eq(util.lnum_at(starts, 3), 1, "as is the last byte of line 1")
  H.eq(util.lnum_at(starts, 5), 2, "a byte past the newline is on line 2")
  H.eq(util.lnum_at(starts, 9), 3, "and so on")
  H.eq(util.lnum_at(starts, 999), 3, "an offset past the end clamps to the last line")

  -- split_top_level -----------------------------------------------------------
  local flat = util.split_top_level("a, b, c", ",")
  H.eq(#flat, 3, "a flat list splits on every separator")
  H.eq(flat[1], "a", "and the tokens are trimmed")

  -- The nesting awareness is the whole reason this is not a plain gsub: Rust's
  -- `use a::{b, c}, d` must be two tokens, not three.
  local nested = util.split_top_level("a::{b, c}, d", ",")
  H.eq(#nested, 2, "a separator inside braces does not split")
  H.eq(nested[1], "a::{b, c}", "the group stays whole")
  H.eq(nested[2], "d", "and the top-level separator still splits")

  H.eq(#util.split_top_level("", ","), 0, "an empty string yields nothing")
  H.eq(#util.split_top_level("  ,  ,  ", ","), 0, "and so does a string of only separators")

  -- split_commas --------------------------------------------------------------
  local named = util.split_commas("a, b as c, d")
  H.eq(#named, 3, "named imports split on commas")
  H.eq(named[2], "b as c", "an alias stays with its name")
end
