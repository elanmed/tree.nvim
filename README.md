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

--- @class TreeKeymaps
--- @field [string] "close-win"|"select"|"select-close-win"

--- @param opts TreeOpts
M.tree = function(opts) end
```

## Example config
```lua
require "tree".tree({
  -- defaults to:
  icons_enabled = true,
  win_type = "split",
  -- no keymaps are set by default
  keymaps = {
    ["<cr>"] = "select-close-win",
    ["o"] = "select",
    ["q"] = "close-win"
  }
})
```
