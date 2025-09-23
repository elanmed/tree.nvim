# `tree.nvim`

A barebones, read-only file tree using the `tree` cli

## API

### `tree`
```lua
--- @class TreeKeymaps
--- @field [string] "close-tree"|"select"|"out-dir"|"in-dir"|"inc-limit"|"dec-limit"|"yank-rel-path"|"yank-abs-path"|"create"|"refresh"|"delete"|"rename"

--- @class TreeOpts
--- @field tree_dir? string
--- @field limit? number
--- @field tree_win_opts? vim.wo
--- @field keymaps TreeKeymaps
--- @field icons_enabled boolean
--- ... and some other internal options passed to the recursive calls
--- @param opts? TreeOpts
M.tree = function(opts) end
```

## Example config
```lua
require "tree".tree({
  -- defaults to
  tree_dir = "[the directory of the current buffer]",
  limit = 1,
  icons_enabled = true,
  tree_win_opts = {},
  -- no keymaps are set by default
  keymaps = {
    ["<cr>"] = "select",
    ["<"] = "dec-limit",
    [">"] = "inc-limit",
    q = "close-tree",
    h = "out-dir",
    l = "in-dir",
    yr = "yank-rel-path",
    ya = "yank-abs-path",
    o = "create",
    e = "refresh",
    dd = "delete",
    r = "rename",
  },
})
```
