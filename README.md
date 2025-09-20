# `tree.nvim`

A barebones, read-only file tree using the `tree` cli

## Status

In progress, API will change

## API

### `tree`
```lua
--- @class TreeKeymaps
--- @field [string] "close-tree"|"select"|"out-cwd"|"in-cwd"|"inc-limit"|"dec-limit"

--- @class TreeOpts
--- @field tree_dir? string
--- @field limit? number
--- @field tree_bufnr? number
--- @field tree_winnr? number
--- @field keymaps TreeKeymaps
--- @param opts? TreeOpts
M.tree = function(opts) end
```

## Example config
```lua
require "tree".tree({
  -- no keymaps are set by default
  keymaps = {
    ["<cr>"] = "select",
    ["q"] = "close-tree"
    ["<esc>"] = "close-tree"
    ["<"] = "dec-limit",
    [">"] = "inc-limit",
  }
})
```
