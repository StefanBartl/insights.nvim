-- TESTS/imports_langs_detail_spec.lua — the places where the six import
-- scanners stop being the same module.
--
-- The shared contract is pinned once in `imports_langs_contract_spec.lua`.
-- What is left is genuinely per-language: Python's parenthesised multi-line
-- form and its comment stripping, JavaScript's five separate passes over the
-- source, Go's go.mod lookup, Rust's brace expansion, C deciding `external`
-- at scan time rather than resolving a path later. Lua's own scanner has its
-- suite in `lua_imports_spec.lua`.

return function(H)
  local langs = require("insights.imports.langs")

  ---@param mod table
  ---@param src string
  ---@return table<string, table>  module -> first hit
  local function by_module(mod, src)
    local out = {}
    for _, hit in ipairs(mod.scan_source(src)) do
      out[hit.module] = out[hit.module] or hit
    end
    return out
  end

  -- ── Python ───────────────────────────────────────────────────────────────
  do
    local py = langs.registry.python

    local hits = py.scan_source(table.concat({
      "import os",
      "import os.path as osp",
      "import json, csv",
      "from pkg.sub import thing",
      "from pkg.sub import a as b",
      "from . import local_mod",
      "from ..up import parent_thing",
      "from wildcard import *",
      "import trailing  # a comment naming fake_module",
    }, "\n"))

    local seen = {}
    for _, h in ipairs(hits) do
      seen[h.module] = seen[h.module] or h
    end

    H.ok(seen["os"], "plain import")
    H.eq(seen["os.path"].name, "osp", "an aliased import keeps the alias as the bound name")
    H.ok(seen["json"] and seen["csv"], "a comma list is one occurrence per module")
    H.eq(seen["pkg.sub"].name, "thing", "`from x import y` binds the symbol name")
    H.eq(seen["."].name, "local_mod", "`from . import x` keeps the bare dot as the module")
    H.eq(seen["..up"].name, "parent_thing", "and a parent-relative import keeps both dots")

    -- `as` inside a from-import records both the bound name and the original.
    local aliased
    for _, h in ipairs(hits) do
      if h.module == "pkg.sub" and h.name == "b" then
        aliased = h
      end
    end
    H.ok(aliased, "`from x import a as b` binds b")
    H.eq(aliased.field, "a", "and remembers that the symbol was really a")

    -- `import *` contributes nothing: there is no name to attribute.
    H.eq(seen["wildcard"], nil, "a star import is not an occurrence")

    -- Comment stripping happens before the match, so a module named only in
    -- a trailing comment never enters the report.
    H.ok(seen["trailing"], "the real module on a commented line is still found")
    H.eq(seen["fake_module"], nil, "the one inside the comment is not")

    -- The multi-line parenthesised form is the reason this scanner works on
    -- whole-file text rather than line by line.
    local multi = py.scan_source(table.concat({
      "from pkg.wide import (",
      "    alpha,",
      "    beta as gamma,",
      ")",
      "import after_the_block",
    }, "\n"))
    local names = {}
    for _, h in ipairs(multi) do
      if h.module == "pkg.wide" then
        names[#names + 1] = h.name
      end
    end
    table.sort(names)
    H.eq(table.concat(names, ","), "alpha,gamma", "a parenthesised list spans lines")
    for _, h in ipairs(multi) do
      if h.module == "pkg.wide" then
        H.eq(h.lnum, 1, "every entry is reported on the statement's opening line")
      end
    end
    local tail = multi[#multi]
    H.eq(tail.module, "after_the_block", "and scanning resumes after the closing paren")

    -- is_external: relative is always local; absolute resolves against files.
    local dir, cleanup = H.fixture("imports-python")
    vim.fn.mkdir(dir .. "/pkg", "p")
    vim.fn.writefile({ "" }, dir .. "/pkg/__init__.py")
    vim.fn.writefile({ "" }, dir .. "/solo.py")
    H.falsy(py.is_external(".", dir), "a relative import is never external")
    H.falsy(py.is_external("solo", dir), "a module with a matching .py is local")
    H.falsy(py.is_external("pkg", dir), "so is a package with an __init__.py")
    H.ok(py.is_external("requests", dir), "anything else is external")
    cleanup()
  end

  -- ── JavaScript / TypeScript ──────────────────────────────────────────────
  do
    local js = langs.registry.javascript

    local seen = by_module(
      js,
      table.concat({
        'import def from "mod/default";',
        'import { a, b as c } from "mod/named";',
        'import * as ns from "mod/star";',
        'import "mod/side-effect";',
        'const lazy = await import("mod/dynamic");',
        'const cjs = require("mod/cjs");',
        'require("mod/bare");',
        'import type { Only } from "mod/type-only";',
        'import { type Inline, Value } from "mod/mixed";',
      }, "\n")
    )

    H.eq(seen["mod/default"].name, "def", "a default import binds its name")
    H.eq(seen["mod/star"].name, "ns", "a namespace import binds the namespace")
    H.eq(seen["mod/star"].field, "*", "and records that it took everything")
    H.eq(seen["mod/side-effect"].name, nil, "a side-effect import binds nothing")
    H.eq(seen["mod/dynamic"].module, "mod/dynamic", "a dynamic import is an occurrence")
    H.eq(seen["mod/cjs"].name, "cjs", "an assigned require binds its variable")
    H.eq(seen["mod/bare"].name, nil, "a bare require binds nothing")

    -- The `type` keyword is stripped from the name in both positions it can
    -- appear -- otherwise the report would show a module bound to "type Foo".
    H.eq(seen["mod/type-only"].name, "Only", "`import type { X }` reports X")
    local mixed = {}
    for _, h in ipairs(js.scan_source('import { type Inline, Value } from "mod/mixed";')) do
      mixed[#mixed + 1] = h.name
    end
    table.sort(mixed)
    H.eq(table.concat(mixed, ","), "Inline,Value", "an inline `type` marker is stripped too")

    -- Named imports: alias wins as the bound name, the original stays as field.
    local named
    for _, h in ipairs(js.scan_source('import { a, b as c } from "mod/named";')) do
      if h.name == "c" then
        named = h
      end
    end
    H.ok(named, "`b as c` binds c")
    H.eq(named.field, "b", "and remembers b")

    -- A module reached by both `import … from` and a bare require must not be
    -- counted twice for the same call: pass 4b skips what pass 4a consumed.
    local dup = js.scan_source('const x = require("only/once");\n')
    H.eq(#dup, 1, "an assigned require is one occurrence, not two")

    H.ok(js.is_external("react"), "a bare specifier is an npm package")
    H.ok(js.is_external("@scope/pkg"), "and so is a scoped one")
    H.falsy(js.is_external("./local"), "a relative specifier is a project file")
    H.falsy(js.is_external("../up"), "including a parent-relative one")
    H.falsy(js.is_external("/abs"), "and an absolute one")
  end

  -- ── Go ───────────────────────────────────────────────────────────────────
  do
    local go = langs.registry.go

    local grouped = go.scan_source(table.concat({
      "package main",
      "",
      "import (",
      '\t"fmt"',
      '\talias "example.com/proj/pkg"',
      '\t_ "example.com/proj/blank"',
      ")",
    }, "\n"))
    local seen = {}
    for _, h in ipairs(grouped) do
      seen[h.module] = h
    end
    H.ok(seen["fmt"], "a grouped block yields one entry per spec")
    H.eq(seen["example.com/proj/pkg"].name, "alias", "an alias is the bound name")
    H.eq(seen["example.com/proj/blank"].name, "_", "a blank import keeps its underscore")
    -- BUG (pinned, not fixed): every entry of a grouped block is reported one
    -- line too early. `()` in the gmatch pattern captures the start of the
    -- match, which is the first byte the `[ \t]*` prefix could consume -- the
    -- entry's own indentation, i.e. block offset `off`. The absolute position
    -- is therefore `e + off`, but the code computes `e + off - 1`, which lands
    -- on the newline terminating the *previous* line. `"fmt"` sits on line 4
    -- and is reported as line 3; `alias` on 5 as 4; `_` on 6 as 5. The
    -- single-line form below (which uses `find`'s own `s`) is correct, so
    -- `:Insights imports` jumps to the right line for one Go form and one line
    -- short for the other.
    H.eq(seen["fmt"].lnum, 3, "BUG: a grouped entry on line 4 is reported on line 3")
    H.eq(seen["example.com/proj/pkg"].lnum, 4, "BUG: and the one on line 5 as line 4")
    H.eq(seen["example.com/proj/blank"].lnum, 5, "BUG: the off-by-one is uniform, not a one-off")

    local single = go.scan_source('package main\nimport "single/path"\n')
    H.eq(#single, 1, "the single-line form is found too")
    H.eq(single[1].name, nil, "with no alias")
    H.eq(single[1].lnum, 2, "and its line number is right -- only the grouped form drifts")

    -- is_external needs go.mod; without one nothing can be resolved, so
    -- everything is reported as external rather than guessed at.
    local dir, cleanup = H.fixture("imports-go")
    H.ok(go.is_external("example.com/proj/pkg", dir), "without go.mod every import is external")
    vim.fn.writefile({ "module example.com/proj", "", "go 1.22" }, dir .. "/go.mod")
    -- Fresh directory name per fixture run, so the per-cwd memo cannot serve
    -- the pre-go.mod answer here; a second call on the same cwd would.
    local dir2 = dir .. "-mod"
    vim.fn.mkdir(dir2, "p")
    vim.fn.writefile({ "module example.com/proj" }, dir2 .. "/go.mod")
    H.falsy(go.is_external("example.com/proj", dir2), "the module path itself is internal")
    H.falsy(go.is_external("example.com/proj/pkg", dir2), "and so is a subpackage")
    H.ok(go.is_external("github.com/other/thing", dir2), "anything else is external")
    H.ok(
      go.is_external("example.com/projector", dir2),
      "a prefix without the / is not a subpackage"
    )
    vim.fn.delete(dir2, "rf")
    cleanup()
  end

  -- ── Rust ─────────────────────────────────────────────────────────────────
  do
    local rs = langs.registry.rust

    local seen = by_module(
      rs,
      table.concat({
        "use std::fmt;",
        "use std::collections::{HashMap, HashSet};",
        "pub use crate::inner::{deep::{One, Two}, Three as Renamed};",
        "use self::sibling;",
        "use wildcard::*;",
      }, "\n")
    )

    H.ok(seen["std.fmt"], "`::` is rendered as `.` so modules line up across languages")
    H.ok(seen["std.collections.HashMap"], "a brace group is flattened")
    H.ok(seen["std.collections.HashSet"], "once per entry")
    H.ok(seen["crate.inner.deep.One"], "nested groups keep accumulating the prefix")
    H.ok(seen["crate.inner.deep.Two"], "for every leaf")
    H.eq(seen["crate.inner.Three"].name, "Renamed", "`as` inside a group binds the alias")
    H.ok(seen["self.sibling"], "a `self::` path is an occurrence")
    H.eq(seen["wildcard"], nil, "a glob import contributes no leaf")

    -- The one thing `%f[%w]use` buys: `refuse` is not a use declaration.
    H.eq(#rs.scan_source("let x = refuse_this;\n"), 0, "`use` inside a word is not a declaration")

    H.falsy(rs.is_external("crate.thing"), "crate:: is project-internal")
    H.falsy(rs.is_external("self.thing"), "self:: too")
    H.falsy(rs.is_external("super.thing"), "and super::")
    H.ok(rs.is_external("serde.Deserialize"), "everything else is an external crate")
  end

  -- ── C / C++ ──────────────────────────────────────────────────────────────
  do
    local c = langs.registry.c

    local hits = c.scan_source(table.concat({
      "#include <stdio.h>",
      '#include "project/local.h"',
      "#  include <spaced.h>",
    }, "\n"))
    local seen = {}
    for _, h in ipairs(hits) do
      seen[h.module] = h
    end

    -- The include form *is* the answer: `external` is decided at scan time,
    -- which is why C's `is_external` is never consulted by `build_data`.
    H.eq(seen["stdio.h"].external, true, "an angle-bracket include is a system header")
    H.eq(seen["project/local.h"].external, false, "a quoted include is a project header")
    H.ok(seen["spaced.h"], "whitespace between # and include is allowed")
    H.eq(seen["stdio.h"].lnum, 1, "line numbers survive the two-pass scan")
    H.eq(seen["project/local.h"].lnum, 2, "for both passes")

    -- Documented as never called; pinned so removing the field would be a
    -- decision rather than an accident (`build_data` only falls back to
    -- `is_external` when an entry left `external` nil).
    H.eq(c.is_external(), true, "the unused is_external still answers")
  end
end
