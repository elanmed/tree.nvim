# `tree.nvim`

A simple file tree built with the `vim.fs.*` utilities

![demo](https://elanmed.dev/nvim-plugins/tree.png)

## Features

- 1 source file (800 LOC), 1 test file
- Files are processed in batches with coroutines to prevent the UI from freezing when opening large directories
- Safe and robust file system actions:
  - Every action requires user confirmation
  - A file cannot be renamed to an existing path
  - A file cannot be copied or moved to a directory if another file with the same destination path already exists
  - A file cannot be deleted, copied, or moved when modified
    - Includes modified children of affected directories!
  - Intermediate directories are created when creating, renaming, copying, or moving files
  - Paths can start from the root of the file system or the `cwd`, and include relative specifiers like `../../` etc
- Multi-select for deleting, copying, and moving files
- Intelligent cursor placement
  - When creating, renaming, copying, or moving files, the cursor is placed at: the destination file, or it's ancestor in the open directory, or the previous cursor index
  - When moving to a parent directory, the cursor is placed at the previous parent
    - The previous cursor path is stored in a history stack for moving to a child directory
  - When moving to a child directory, the cursor is placed at: the top of the history stack, or the previous cursor index

## API

### `tree`

```lua
--- @class TreeOpts
--- @field tree_dir? string
--- @field tree_win_opts? vim.wo options to apply to the tree window
--- @field tree_win_config? table configuration passed to `nvim_open_win`
--- @field icons_enabled? boolean
--- ... and some other internal options passed to the recursive calls
--- @param opts? TreeOpts
M.tree = function(opts) end
```

## Example config

```lua
require "tree".tree({
  -- defaults to
  tree_dir = "[the directory of the current buffer]",
  icons_enabled = true,
  tree_win_opts = {},
  tree_win_config = {},
})

vim.api.nvim_create_autocmd("FileType", {
  pattern = "tree",
  callback = function(args)
    vim.keymap.set("n", "<cr>", "<Plug>TreeSelect", { buffer = args.buf, })
    vim.keymap.set("n", "q", "<Plug>TreeCloseTree", { buffer = args.buf, })
    vim.keymap.set("n", "h", "<Plug>TreeOutDir", { buffer = args.buf, })
    vim.keymap.set("n", "l", "<Plug>TreeInDir", { buffer = args.buf, })
    vim.keymap.set("n", "yr", "<Plug>TreeYankRelativePath", { buffer = args.buf, })
    vim.keymap.set("n", "ya", "<Plug>TreeYankAbsolutePath", { buffer = args.buf, })
    vim.keymap.set("n", "yd", "<Plug>TreeYankDirectory", { buffer = args.buf, })
    vim.keymap.set("n", "yb", "<Plug>TreeYankBasename", { buffer = args.buf, })
    vim.keymap.set("n", "o", "<Plug>TreeCreate", { buffer = args.buf, })
    vim.keymap.set("n", "e", "<Plug>TreeRefresh", { buffer = args.buf, })
    vim.keymap.set("n", "r", "<Plug>TreeRename", { buffer = args.buf, })
    vim.keymap.set("n", "dd", "<Plug>TreeDelete", { buffer = args.buf, })
    vim.keymap.set("n", "yy", "<Plug>TreeCopy", { buffer = args.buf, })
    vim.keymap.set("n", "m", "<Plug>TreeMove", { buffer = args.buf, })

    -- supports multiple items
    vim.keymap.set("v", "d", "<Plug>TreeDelete", { buffer = args.buf, })
    vim.keymap.set("v", "yy", "<Plug>TreeCopy", { buffer = args.buf, })
    vim.keymap.set("v", "m", "<Plug>TreeMove", { buffer = args.buf, })
  end,
})
```

## Plug remaps

#### `<Plug>TreeCloseTree`

Close the tree window

#### `<Plug>TreeSelect`

- If the cursor is on a directory, enter the directory (same as `InDir`)
- If the cursor is on a file, close the tree window and open the file in the original window

#### `<Plug>TreeOutDir`

- Navigate to the parent directory of the current tree root

#### `<Plug>TreeInDir`

- Enter the directory under the cursor

#### `<Plug>TreeYankRelativePath`

Copy the relative path (from the cwd) of the file/directory under the cursor to the `r` register

#### `<Plug>TreeYankAbsolutePath`

Copy the absolute path of the file/directory under the cursor to the `a` register

#### `<Plug>TreeYankDirectory`

Copy the directory name of the file under the cursor to the `d` register

- Can be used in conjuction with `<Plug>TreeCopy`

#### `<Plug>TreeYankBasename`

Copy the basename (minus the extension) of the file under the cursor to the `b` register

- Can be used in conjuction with `<Plug>TreeCreate`

#### `<Plug>TreeCreate`

Create a new file or directory:

- If the path ends with `/`, create a directory, otherwise a file
- Create parent directories as needed
- Trigger the `User TreeCreate` autocommand after creation
- Refresh the tree (`TreeRefresh`)

#### `<Plug>TreeDelete`

Delete the file or directory under the cursor or visual selection:

- Recursively delete directories and their contents
- Trigger the `User TreeDelete` autocommand after deletion
- Refresh the tree (`TreeRefresh`)

#### `<Plug>TreeRename`

Rename the file or directory under the cursor:

- Trigger the `User TreeRename` autocommand after renaming
- Refresh the tree (`TreeRefresh`)

#### `<Plug>TreeCopy`

Copy the file or directory under the cursor or visual selection to a destination:

- Trigger the `User TreeCopy` autocommand after copying
- Refresh the tree (`TreeRefresh`)

#### `<Plug>TreeMove`

Move the file or directory under the cursor or visual selection to a destination:

- Trigger the `User TreeMove` autocommand after copying
- Refresh the tree (`TreeRefresh`)
- Uses `<Plug>TreeCopy` under the hood, just deletes as well

#### `<Plug>TreeRefresh`

Refresh the tree to reflect any file system changes
