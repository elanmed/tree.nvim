# `tree.nvim`

A simple file tree built with the `tree` cli

## API

### `tree`
```lua
--- @class TreeOpts
--- @field tree_dir? string
--- @field level? number
--- @field tree_win_opts? vim.wo
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
  level = 1,
  icons_enabled = true,
  tree_win_opts = {},
})

vim.api.nvim_create_autocmd("FileType", {
  pattern = "tree",
  callback = function(args)
    vim.keymap.set("n", "<cr>", "<Plug>TreeSelect", { buffer = args.buf, })
    vim.keymap.set("n", "q", "<Plug>TreeCloseTree", { buffer = args.buf, })
    vim.keymap.set("n", "<", "<Plug>TreeDecreaseLevel", { buffer = args.buf, })
    vim.keymap.set("n", ">", "<Plug>TreeIncreaseLevel", { buffer = args.buf, })
    vim.keymap.set("n", "h", "<Plug>TreeOutDir", { buffer = args.buf, })
    vim.keymap.set("n", "l", "<Plug>TreeInDir", { buffer = args.buf, })
    vim.keymap.set("n", "yr", "<Plug>TreeYankRelativePath", { buffer = args.buf, })
    vim.keymap.set("n", "ya", "<Plug>TreeYankAbsolutePath", { buffer = args.buf, })
    vim.keymap.set("n", "o", "<Plug>TreeCreate", { buffer = args.buf, })
    vim.keymap.set("n", "e", "<Plug>TreeRefresh", { buffer = args.buf, })
    vim.keymap.set("n", "dd", "<Plug>TreeDelete", { buffer = args.buf, })
    vim.keymap.set("n", "r", "<Plug>TreeRename", { buffer = args.buf, })
  end,
})
```

## Plug remaps

#### `<Plug>TreeCloseTree`
Close the tree window

#### `<Plug>TreeSelect`
- If the cursor is on a directory, enter the directory (same as `InDir`)
- If the cursor is on a file, close the tree window and open the file in the original window

#### `<Plug>TreeIncreaseLevel`
Increase the tree depth level by 1

#### `<Plug>TreeDecreaseLevel`
Decrease the tree depth level by 1

#### `<Plug>TreeOutDir`
- Navigate to the parent directory of the current tree root

#### `<Plug>TreeInDir`
- Enter the directory under the cursor

#### `<Plug>TreeYankRelativePath`
Copy the relative path (from the cwd) of the file/directory under the cursor to the unnamed register and system clipboard

#### `<Plug>TreeYankAbsolutePath`
Copy the absolute path of the file/directory under the cursor to the unnamed register and system clipboard

#### `<Plug>TreeCreate`
Create a new file or directory:
- If the path ends with `/`, create a directory, otherwise a file
- Create parent directories as needed
- Trigger the `User TreeCreate` autocommand after creation
- Refresh the tree (`TreeRefresh`)

#### `<Plug>TreeDelete`
Delete the file or directory under the cursor:
- Recursively delete directories and their contents
- Trigger the `User TreeDelete` autocommand after deletion
- Refresh the tree (`TreeRefresh`)

#### `<Plug>TreeRename`
Rename the file or directory under the cursor:
- Trigger the `User TreeRename` autocommand after rename
- Refresh the tree (`TreeRefresh`)

#### `<Plug>TreeRefresh`
Refresh the tree to reflect any file system changes
