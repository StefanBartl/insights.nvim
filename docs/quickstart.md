# Quickstart

Open any file in the project and ask the question you would otherwise have
grepped for:

```vim
:Insights symbols
```

Then the rest:

```vim
:Insights imports                    " import/require usage, multi-language
:Insights imports reverse foo.bar    " every file that imports this module
:Insights imports unused             " bound names never referenced again
:Insights metrics                    " Lua code metrics
:Insights smells                     " magic numbers and unconfigured constants
:Insights tree                       " write the project file tree to a file
```

Verify your setup any time with:

```vim
:checkhealth insights
```

See [Commands](commands.md) for the full subcommand reference, and
[What you get with the defaults](what-you-get.md) for the rest of the
surface at a glance.
