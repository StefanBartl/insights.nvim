-- TESTS/symbols_patterns_parser_spec.lua — the two halves of the rg-based
-- symbol index that do not need ripgrep: which patterns/extensions a language
-- selection produces, and how a `--vimgrep` line becomes a symbol entry.
--
-- The parser is the whole reason the indexer can be tested without running
-- anything: `rg` produces text, and everything after that is string work.

return function(H)
  local patterns = require("insights.symbols.patterns")
  local parser = require("insights.symbols.parser")

  -- ── get_patterns ─────────────────────────────────────────────────────────
  H.eq(#patterns.get_patterns({}), 0, "no language enabled selects no pattern")

  local lua_pats = patterns.get_patterns({ lua = true })
  H.eq(#lua_pats, 5, "Lua has five shapes of function definition")
  for _, p in ipairs(lua_pats) do
    H.eq(p.language, "lua", "and only Lua patterns come back")
    H.ok(type(p.pattern) == "string" and p.pattern ~= "", "each carries a PCRE2 pattern")
    H.ok(type(p.func_type) == "string", "and the kind of definition it finds")
    H.ok(type(p.name_capture) == "number", "and which capture group holds the name")
  end

  local pair = patterns.get_patterns({ lua = true, go = true })
  H.eq(#pair, #lua_pats + 2, "enabling a second language adds only its own patterns")

  -- A language that is listed as `false` is the same as absent.
  H.eq(#patterns.get_patterns({ lua = false }), 0, "an explicitly disabled language selects none")

  -- ── get_extensions ───────────────────────────────────────────────────────
  H.eq(table.concat(patterns.get_extensions({ lua = true }), ","), "lua", "Lua owns one extension")
  local cpp = patterns.get_extensions({ cpp = true })
  table.sort(cpp)
  H.eq(table.concat(cpp, ","), "cc,cpp,cxx,hh,hpp,hxx", "C++ owns six")
  H.eq(#patterns.get_extensions({}), 0, "no language, no extensions")

  -- C and C++ both claim `h`-family files in the extension map; the result is
  -- de-duplicated, or rg would be handed the same `--glob` twice.
  local both = patterns.get_extensions({ c = true, cpp = true })
  local seen = {}
  for _, ext in ipairs(both) do
    H.eq(seen[ext], nil, ("extension %q appears once"):format(ext))
    seen[ext] = true
  end

  -- ── detect_language ──────────────────────────────────────────────────────
  H.eq(patterns.detect_language("a/b/c.lua"), "lua", "by extension")
  H.eq(patterns.detect_language("mod.py"), "python", "python")
  H.eq(patterns.detect_language("app.tsx"), "typescript", "tsx is TypeScript, not JavaScript")
  H.eq(patterns.detect_language("app.jsx"), "javascript", "jsx is JavaScript")
  H.eq(patterns.detect_language("head.h"), "c", "a bare .h is C")
  H.eq(patterns.detect_language("MOD.LUA"), "lua", "the extension is matched case-insensitively")
  H.eq(patterns.detect_language("README"), nil, "a file with no extension has no language")
  H.eq(patterns.detect_language("notes.txt"), nil, "and neither does an unknown one")
  H.eq(patterns.detect_language("archive.tar.gz"), nil, "only the last extension is considered")

  -- ── infer_func_type ──────────────────────────────────────────────────────
  H.eq(patterns.infer_func_type("local function f()", "lua"), "local", "lua: local function")
  H.eq(patterns.infer_func_type("function M.f()", "lua"), "module", "lua: dotted function")
  H.eq(patterns.infer_func_type("function f()", "lua"), "global", "lua: bare function")
  H.eq(patterns.infer_func_type("M.f = function()", "lua"), "anonymous", "lua: assigned function")
  H.eq(patterns.infer_func_type("  def m(self):", "python"), "method", "python: indented def")
  H.eq(patterns.infer_func_type("async def f():", "python"), "global", "python: async def")
  H.eq(patterns.infer_func_type("export function f()", "javascript"), "exported", "js: exported")
  H.eq(patterns.infer_func_type("const f = () => {}", "javascript"), "anonymous", "js: arrow")
  H.eq(patterns.infer_func_type("export function f()", "typescript"), "exported", "ts too")
  H.eq(patterns.infer_func_type("fn main()", "rust"), "unknown", "a language with no rules")
  H.eq(patterns.infer_func_type("def f()", "python"), "unknown", "and an unindented plain def")

  -- ── parser.parse ─────────────────────────────────────────────────────────
  local entries, errors = parser.parse({
    "lua/mod.lua:12:1:local function helper(a, b)",
    "lua/mod.lua:20:1:function M.exported(opts)",
    "src/app.py:3:1:def greet(name):",
    "src/app.js:7:1:export function render(props) {",
    "pkg/main.go:9:1:func (s *Server) Handle(w, r) {",
    "src/lib.rs:4:1:pub fn build(cfg: Config) {",
  }, {
    lua = true,
    python = true,
    javascript = true,
    go = true,
    rust = true,
  })

  H.eq(#errors, 0, "well-formed vimgrep lines parse without errors")
  H.eq(#entries, 6, "one entry per line")

  local by_name = {}
  for _, e in ipairs(entries) do
    by_name[e.name] = e
  end

  H.eq(by_name.helper.language, "lua", "the language comes from the file extension")
  H.eq(by_name.helper.func_type, "local", "and the kind from the matched text")
  H.eq(by_name.helper.lnum, 12, "the line number is a number, not the string rg printed")
  H.eq(by_name.helper.col, 1, "and so is the column")
  H.eq(by_name.helper.signature, "helper(a, b)", "the signature keeps the parameter list")
  H.eq(by_name.helper.filename, "lua/mod.lua", "and the file it came from")

  H.eq(by_name["M.exported"].func_type, "module", "a dotted Lua name is a module function")
  H.eq(by_name.greet.language, "python", "python is detected")
  H.eq(by_name.render.func_type, "exported", "an exported JS function")
  H.eq(by_name.Handle.language, "go", "a Go method's receiver does not become its name")
  H.eq(by_name.build.language, "rust", "and rust is detected")

  -- A language that is not enabled is skipped silently: it is not an error
  -- that rg matched a file the user did not ask about.
  local skipped, skipped_errors = parser.parse(
    { "src/app.py:3:1:def greet(name):" },
    { lua = true }
  )
  H.eq(#skipped, 0, "a disabled language contributes no entries")
  H.eq(#skipped_errors, 0, "and is not reported as a failure")

  -- A file with no known extension is skipped for the same reason.
  H.eq(#parser.parse({ "README:1:1:function f()" }, { lua = true }), 0, "unknown extension skipped")

  -- Malformed input ---------------------------------------------------------
  local bad_entries, bad_errors = parser.parse({
    "",
    "no colons at all",
    "file.lua:notanumber:1:function f()",
    "file.lua:1:notanumber:function f()",
  }, { lua = true })
  H.eq(#bad_entries, 0, "nothing parseable, nothing returned")
  H.eq(#bad_errors, 4, "one error per unreadable line")
  H.contains(bad_errors[2], "parse failed", "naming what went wrong")
  H.contains(bad_errors[2], "no colons at all", "and quoting the line")

  -- A line that parses but holds no name is a different error.
  local _, no_name = parser.parse({ "file.lua:1:1:-- just a comment" }, { lua = true })
  H.eq(#no_name, 1, "a line with no extractable name is reported")
  H.contains(no_name[1], "no name extracted", "as its own error kind")

  H.eq(#parser.parse({}, { lua = true }), 0, "an empty line list parses to nothing")
  ---@diagnostic disable-next-line: param-type-mismatch
  local not_a_table, wrong_type_errors = parser.parse("not a table", { lua = true })
  H.eq(#not_a_table, 0, "a non-table input is refused")
  H.eq(wrong_type_errors[1], "expected table of strings", "with a type error")

  -- Signature extraction ----------------------------------------------------
  local sigs = parser.parse({
    "a.lua:1:1:local function nested(cb(x), y)",
    "a.lua:2:1:local function unclosed(a, b",
    "a.lua:3:1:local function wide(aaaaaaaaaa, bbbbbbbbbb, cccccccccc, dddddddddd, eeeeeeeeee)",
    "a.lua:4:1:local function none()",
  }, { lua = true })
  local sig_by_name = {}
  for _, e in ipairs(sigs) do
    sig_by_name[e.name] = e.signature
  end
  H.eq(
    sig_by_name.nested,
    "nested(cb(x), y)",
    "nested parentheses are balanced, not cut at the first )"
  )
  H.eq(sig_by_name.unclosed, "unclosed(...)", "an unclosed list is elided rather than guessed")
  H.eq(sig_by_name.none, "none()", "an empty parameter list stays empty")
  H.ok(#sig_by_name.wide <= #"wide(" + 40 + 1, "a long parameter list is truncated")
  H.contains(sig_by_name.wide, "...", "with an ellipsis")

  -- BUG (pinned, not fixed): an absolute Windows path never parses ----------
  -- `parse_vimgrep_line` splits on the first three colons, so the drive
  -- letter's own colon consumes the `filename` field and the line number lands
  -- where the path should be. `rg_index.build` passes `vim.fn.getcwd()` to rg
  -- as the search root, and on Windows that is `E:\repos\…` -- so rg prints
  -- `E:\repos\…\mod.lua:12:1:…` and **every single match is discarded as
  -- unparseable**. `:Insights symbols` finds nothing at all on Windows, and
  -- the failure is silent: the errors list is not shown, only counted.
  local win_entries, win_errors = parser.parse({
    "C:/proj/lua/mod.lua:12:1:local function helper(a, b)",
    [[E:\repos\proj\lua\mod.lua:12:1:local function helper(a, b)]],
  }, { lua = true })
  H.eq(win_entries and #win_entries, 0, "BUG: an absolute Windows path yields no symbol")
  H.eq(#win_errors, 2, "BUG: both drive-letter forms are counted as parse failures")
  H.contains(win_errors[1], "parse failed", "BUG: and reported as malformed input")
end
