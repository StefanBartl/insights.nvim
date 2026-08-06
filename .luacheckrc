-- LuaJIT (Neovim's runtime) exposes 5.2 additions such as package.searchpath.
std = "lua51+lua52"
globals = { "vim" }

-- Formatting (line width) is stylua's job (column_width = 100); regex
-- patterns and doc-comment annotations legitimately exceed that and are
-- not reflowed by stylua. Long lines are a style nit, not a bug.
max_line_length = false

exclude_files = {
  ".luarocks/",
}
