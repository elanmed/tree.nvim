# `tree.nvim`

A barebones, read-only file tree using the `tree` cli

## Status

Works fine, API may change

## API

### `tree`
```lua
--- @class TreeOpts
--- @field icons_enabled boolean
--- @field keymaps TreeKeymaps
--- @field win_type "popup"|"split"
--- @field win_width number

--- @class TreeKeymaps
--- @field [string] "close-tree"|"select-focus-win"|"select-close-tree"|"select-focus-tree"

--- @param opts TreeOpts
M.tree = function(opts) end
```

## Example config
```lua
require "tree".tree({
  -- defaults to:
  icons_enabled = true,
  win_type = "split",
  win_width = 50,
  -- no keymaps are set by default
  keymaps = {
    ["<cr>"] = "select-close-tree",
    ["t"] = "select-focus-tree",
    ["o"] = "select-focus-win",
    ["q"] = "close-tree"
  }
})
```
