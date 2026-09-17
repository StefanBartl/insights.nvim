-- TESTS/unimported_spec.lua — component tags used in a buffer without a
-- matching import or local definition.
--
-- The check is deliberately textual, and the interesting half is what it does
-- *not* flag: the frontier patterns exist so an import of `ButtonGroup` never
-- satisfies a reference to `Button`, and so a lowercase `<div>` is an HTML
-- element rather than a missing component.

return function(H)
  local unimported = require("insights.unimported")
  local config = require("insights.config")

  ---@param lines string[]
  ---@return integer
  local function buffer(lines)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    return buf
  end

  ---@param lines string[]
  ---@return table<string, boolean>
  local function missing_set(lines)
    local buf = buffer(lines)
    local out = {}
    for _, name in ipairs(unimported.check_buf(buf)) do
      out[name] = true
    end
    vim.api.nvim_buf_delete(buf, { force = true })
    return out
  end

  config.setup({})

  -- What counts as a reference ----------------------------------------------
  local found = missing_set({
    "<Missing />",
    "<div>plain html</div>",
    "<alsoLowercase />",
    "<Missing>again</Missing>",
  })
  H.ok(found.Missing, "an uppercase tag with no binding is reported")
  H.eq(found.div, nil, "a lowercase tag is an HTML element, not a component")
  H.eq(found.alsoLowercase, nil, "however long it is")

  -- The same tag twice is one finding: it is a list of names, not of uses.
  local twice = unimported.check_buf(buffer({ "<Dup />", "<Dup />" }))
  H.eq(#twice, 1, "a repeated tag is reported once")

  -- What counts as a binding -------------------------------------------------
  H.eq(missing_set({ 'import Button from "./b"', "<Button />" }).Button, nil, "a default import")
  H.eq(
    missing_set({ 'import { Button, Other } from "./b"', "<Button />" }).Button,
    nil,
    "a named import"
  )
  H.eq(
    missing_set({ 'import * as Button from "./b"', "<Button />" }).Button,
    nil,
    "a namespace one"
  )
  H.eq(missing_set({ "const Button = () => {}", "<Button />" }).Button, nil, "a const declaration")
  H.eq(missing_set({ "let Button = 1", "<Button />" }).Button, nil, "a let declaration")
  H.eq(missing_set({ "var Button = 1", "<Button />" }).Button, nil, "a var declaration")
  H.eq(
    missing_set({ "local Button = 1", "<Button />" }).Button,
    nil,
    "a Lua local, for Astro files"
  )
  H.eq(missing_set({ "function Button() {}", "<Button />" }).Button, nil, "a function declaration")
  H.eq(missing_set({ "class Button {}", "<Button />" }).Button, nil, "a class declaration")
  H.eq(missing_set({ "export const Button = 1", "<Button />" }).Button, nil, "an export assignment")
  H.eq(
    missing_set({ 'const Button = await require("./b")', "<Button />" }).Button,
    nil,
    "and a dynamic require"
  )

  -- The frontier rule: the whole point of matching on word boundaries.
  local prefix = missing_set({ 'import ButtonGroup from "./bg"', "<Button />", "<ButtonGroup />" })
  H.ok(prefix.Button, "an import of ButtonGroup does not satisfy a reference to Button")
  H.eq(prefix.ButtonGroup, nil, "while ButtonGroup itself is bound")

  local suffix = missing_set({ 'import Button from "./b"', "<SuperButton />" })
  H.ok(suffix.SuperButton, "and the rule holds from the other side too")

  -- A binding further down the file still counts: the check reads the whole
  -- buffer, not only what precedes the use.
  H.eq(missing_set({ "<Button />", "const Button = 1" }).Button, nil, "order does not matter")

  -- ignore -------------------------------------------------------------------
  config.setup({ unimported = { ignore = { "Fragment", "Slot" } } })
  local ignored = missing_set({ "<Fragment />", "<Slot />", "<Other />" })
  H.eq(ignored.Fragment, nil, "a configured global is never reported")
  H.eq(ignored.Slot, nil, "for each name in the list")
  H.ok(ignored.Other, "while everything else still is")
  config.setup({})

  -- handles_filetype ---------------------------------------------------------
  H.ok(unimported.handles_filetype("astro"), "astro is handled by default")
  H.ok(unimported.handles_filetype("typescriptreact"), "and tsx")
  H.ok(unimported.handles_filetype("vue"), "and vue")
  H.ok(unimported.handles_filetype("svelte"), "and svelte")
  H.falsy(unimported.handles_filetype("lua"), "lua is not")
  H.falsy(unimported.handles_filetype(""), "and neither is nothing")

  config.setup({ unimported = { filetypes = { "html" } } })
  H.ok(unimported.handles_filetype("html"), "the list is configurable")
  H.falsy(unimported.handles_filetype("astro"), "and replaces the default rather than adding to it")
  config.setup({})

  -- Guards -------------------------------------------------------------------
  H.eq(#unimported.check_buf(999999), 0, "a buffer that does not exist has nothing to check")
  local deleted = buffer({ "<Missing />" })
  vim.api.nvim_buf_delete(deleted, { force = true })
  H.eq(#unimported.check_buf(deleted), 0, "and neither does a deleted one")
  H.eq(#unimported.check_buf(buffer({})), 0, "an empty buffer reports nothing")

  -- check_buf defaults to the current buffer.
  vim.cmd("enew")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "<CurrentBufferComponent />" })
  local current = unimported.check_buf()
  H.eq(current[1], "CurrentBufferComponent", "with no argument, the current buffer is checked")

  -- run ----------------------------------------------------------------------
  -- `run` is `check_buf` plus a notification; the return value is the same
  -- list, and `silent` only suppresses the "all clear" case.
  local reported = unimported.run(nil, { silent = true })
  H.eq(reported[1], "CurrentBufferComponent", "run returns what check_buf found")

  local clean = buffer({ "const Bound = 1", "<Bound />" })
  H.eq(#unimported.run(clean, { silent = true }), 0, "a clean buffer reports nothing")
  H.eq(#unimported.run(clean), 0, "and says so out loud when not silenced")
  H.eq(#unimported.run(clean, {}), 0, "an empty options table is not silent")
  vim.api.nvim_buf_delete(clean, { force = true })

  vim.cmd("silent! %bwipeout!")
end
