local M = {}

local vimscript_true = 1
local vimscript_false = 0

local ns_id = vim.api.nvim_create_namespace "Tree"

--- @generic T
--- @param val T | nil
--- @param default_val T
--- @return T
local default = function(val, default_val)
  if val == nil then
    return default_val
  end
  return val
end

--- @param path string
local fs_exists = function(path)
  return vim.uv.fs_stat(path)
end

--- @class GetIconInfoOpts
--- @field icons_enabled boolean
--- @field abs_path string
--- @field type "file"|"directory"
--- @param opts GetIconInfoOpts
local get_icon_info = function(opts)
  if not opts.icons_enabled then
    return {
      icon_char = "",
      icon_hl = nil,
    }
  end
  local mini_icons_ok, mini_icons = pcall(require, "mini.icons")
  if not mini_icons_ok then
    error "[tree.nvim] `mini.icons` is required when `icons_enabled` is `true`"
  end

  local icon_char, icon_hl = mini_icons.get(opts.type, opts.abs_path)

  return {
    icon_char = icon_char,
    icon_hl = icon_hl,
  }
end

--- @param winnr number
local get_minimal_opts = function(winnr)
  -- :help nvim_open_win
  local minimal_opts_to_get = {
    "number", "relativenumber", "cursorline", "cursorcolumn",
    "foldcolumn", "spell", "list", "signcolumn", "colorcolumn",
    "statuscolumn", "fillchars", "winhighlight",
  }

  local saved_minimal_opts = {}
  for _, opt in ipairs(minimal_opts_to_get) do
    saved_minimal_opts[opt] = vim.api.nvim_get_option_value(opt, { win = winnr, })
  end

  return saved_minimal_opts
end

--- @param winnr number
--- @param opts vim.wo
local set_opts = function(winnr, opts)
  for opt, value in pairs(opts) do
    vim.api.nvim_set_option_value(opt, value, { win = winnr, })
  end
end

--- @class Line
--- @field whitespace string
--- @field abs_path string
--- @field formatted string
--- @field icon_char string
--- @field icon_hl string

--- @class TreeJson
--- @field type "file"|"directory"
--- @field name string
--- @field contents TreeJson[]
--- @field target string

--- @class TreeKeymaps
--- @field [string] "close-tree"|"select"|"out-dir"|"in-dir"|"inc-level"|"dec-level"|"yank-abs-path"|"yank-rel-path"

--- @class TreeOpts
--- @field tree_dir? string
--- @field level? number
--- @field tree_win_opts? vim.wo
--- @field keymaps TreeKeymaps
--- @field icons_enabled boolean
--- @field _tree_bufnr? number
--- @field _tree_winnr? number
--- @field _minimal_tree_win_opts? table
--- @field _curr_winnr? number
--- @field _curr_bufnr? number
--- @field _prev_cursor_file? string
--- @field _prev_dir? string
--- @param opts? TreeOpts
M.tree = function(opts)
  opts = default(opts, {})
  opts = vim.deepcopy(opts)

  opts.level = default(opts.level, 1)
  opts.keymaps = default(opts.keymaps, {})
  opts.icons_enabled = default(opts.icons_enabled, true)
  opts.tree_win_opts = default(opts.tree_win_opts, {})

  opts._curr_winnr = (function()
    if opts._curr_winnr then
      return opts._curr_winnr
    end
    return vim.api.nvim_get_current_win()
  end)()

  opts._curr_bufnr = (function()
    if opts._curr_bufnr then
      return opts._curr_bufnr
    end
    return vim.api.nvim_get_current_buf()
  end)()

  local curr_bufname_abs_path = vim.api.nvim_buf_get_name(opts._curr_bufnr)
  local curr_dir = (function()
    -- vim opened with no arguments
    if curr_bufname_abs_path == "" then
      return vim.fn.getcwd()
    end

    if vim.fn.isdirectory(curr_bufname_abs_path) == vimscript_true then
      return curr_bufname_abs_path
    end

    return vim.fs.dirname(curr_bufname_abs_path)
  end)()
  opts.tree_dir = default(opts.tree_dir, curr_dir)

  opts._tree_bufnr = (function()
    if opts._tree_bufnr then
      return opts._tree_bufnr
    end

    local tree_bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_option_value("buftype", "nofile", { buf = tree_bufnr, })
    vim.api.nvim_set_option_value("buflisted", false, { buf = tree_bufnr, })
    vim.api.nvim_set_option_value("filetype", "tree", { buf = tree_bufnr, })

    return tree_bufnr
  end)()

  -- -f Prints the full path prefix for each file.
  -- -a All files are printed.  By default tree does not print hidden files (those beginning with a dot `.').
  -- --no-report Omits printing of the file and directory report at the end of the tree listing.
  -- -J Turn on JSON output. Outputs the directory tree as a JSON formatted array.
  -- -L Max display depth of the directory tree.
  local obj = vim.system(
    { "tree", "-f", "-a", "--noreport", "-J", "-L", tostring(opts.level), },
    { cwd = opts.tree_dir, }
  ):wait()

  if obj.code ~= 0 then
    error "[tree.nvim] `tree` exit code was not `0`"
  end

  if not obj.stdout then
    error "[tree.nvim] no stdout from `tree`"
  end

  --- @type TreeJson[]
  local json = vim.json.decode(obj.stdout)
  if not json[1] then
    error "[tree.nvim] empty json from `tree`"
  end

  if json[1].type ~= "directory" then
    error "[tree.nvim] top-level json object from `tree` is not a directory"
  end

  --- @type Line[]
  local lines = {}
  --- @type string[]
  local formatted_lines = {}

  local max_line_width = 0
  local prev_cursor_file_line = nil
  local prev_dir_line = nil
  local curr_bufname_line = nil

  --- @param json_arg TreeJson[]
  --- @param indent number
  local function populate_lines(json_arg, indent)
    for _, entry in ipairs(json_arg) do
      local name = entry.type == "directory" and entry.name .. "/" or entry.name

      local rel_path = vim.fs.normalize(name)
      local abs_path = vim.fs.joinpath(opts.tree_dir, rel_path)
      local basename = vim.fs.basename(abs_path)

      local icon_type = entry.type == "directory" and "directory" or "file"
      local icon_info = get_icon_info { abs_path = abs_path, icons_enabled = opts.icons_enabled, type = icon_type, }
      local whitespace = ("  "):rep(indent)
      local formatted = ("%s%s %s"):format(whitespace, icon_info.icon_char, basename)
      max_line_width = math.max(max_line_width, #formatted)

      --- @type Line
      local line = {
        abs_path = abs_path,
        whitespace = whitespace,
        formatted = formatted,
        icon_char = icon_info.icon_char,
        icon_hl = icon_info.icon_hl,
      }
      table.insert(lines, line)
      table.insert(formatted_lines, formatted)

      if abs_path == opts._prev_cursor_file then
        prev_cursor_file_line = #lines
      end

      if abs_path == opts._prev_dir then
        prev_dir_line = #lines
      end

      if abs_path == curr_bufname_abs_path then
        curr_bufname_line = #lines
      end

      if entry.contents then
        populate_lines(entry.contents, indent + 1)
      end
    end
  end

  populate_lines(json[1].contents, 0)

  vim.api.nvim_set_option_value("modifiable", true, { buf = opts._tree_bufnr, })
  vim.api.nvim_buf_set_lines(opts._tree_bufnr, 0, -1, false, formatted_lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = opts._tree_bufnr, })

  vim.schedule(function()
    for idx, line in ipairs(lines) do
      local icon_hl_col_0_indexed = #line.whitespace
      local row_1_indexed = idx
      local row_0_indexed = row_1_indexed - 1
      vim.hl.range(
        opts._tree_bufnr,
        ns_id,
        line.icon_hl,
        { row_0_indexed, icon_hl_col_0_indexed, },
        { row_0_indexed, icon_hl_col_0_indexed + 1, }
      )
    end
  end)

  local width_padding = 10

  opts._tree_winnr = (function()
    local title = ("tree %s/ -L %s"):format(vim.fs.basename(opts.tree_dir), opts.level)
    local border_height = 2
    local width = math.max(#title, max_line_width + width_padding)
    local editor_height = vim.api.nvim_win_get_height(opts._curr_winnr)
    local height = math.min(#lines, editor_height - border_height)
    if height < 1 then height = 1 end

    if opts._tree_winnr and vim.api.nvim_win_is_valid(opts._tree_winnr) then
      vim.api.nvim_win_set_config(opts._tree_winnr, {
        title = title,
        width = width,
        height = height,
      })
      return opts._tree_winnr
    end

    local tree_winnr = vim.api.nvim_open_win(opts._tree_bufnr, true, {
      relative = "editor",
      row = 1,
      col = 0,
      width = width,
      height = height,
      border = "rounded",
      style = "minimal",
      title = title,
    })
    vim.api.nvim_set_option_value("foldmethod", "indent", { win = tree_winnr, })
    vim.api.nvim_set_option_value("cursorline", true, { win = tree_winnr, })
    set_opts(tree_winnr, opts.tree_win_opts)
    opts._minimal_tree_win_opts = get_minimal_opts(tree_winnr)

    vim.api.nvim_create_autocmd("BufWinEnter", {
      callback = function()
        if not vim.api.nvim_win_is_valid(tree_winnr) then return end
        if vim.api.nvim_get_current_win() ~= tree_winnr then return end
        if vim.api.nvim_get_current_buf() ~= opts._tree_bufnr then
          vim.api.nvim_win_set_buf(tree_winnr, opts._tree_bufnr)
        end
        set_opts(tree_winnr, opts._minimal_tree_win_opts)
        set_opts(tree_winnr, opts.tree_win_opts)
      end,
    })

    return tree_winnr
  end)()
  vim.api.nvim_win_set_buf(opts._tree_winnr, opts._tree_bufnr)

  if curr_bufname_line then
    vim.api.nvim_buf_set_mark(opts._tree_bufnr, "a", curr_bufname_line, 0, {})
  end

  if prev_cursor_file_line then
    vim.cmd "normal! gg"
    vim.api.nvim_win_set_cursor(opts._tree_winnr, { prev_cursor_file_line, 0, })
  elseif prev_dir_line then
    vim.cmd "normal! gg"
    vim.api.nvim_win_set_cursor(opts._tree_winnr, { prev_dir_line, 0, })
  elseif curr_bufname_line then
    vim.cmd "normal! gg'a"
  end

  --- @class RecurseOpts
  --- @field level? number
  --- @field tree_dir? string
  --- @param r_opts? RecurseOpts
  local recurse = function(r_opts)
    r_opts = default(r_opts, {})
    r_opts = vim.deepcopy(r_opts)
    r_opts.level = default(r_opts.level, opts.level)
    r_opts.tree_dir = default(r_opts.tree_dir, opts.tree_dir)

    M.tree {
      level = r_opts.level,
      _tree_bufnr = opts._tree_bufnr,
      tree_dir = r_opts.tree_dir,
      _tree_winnr = opts._tree_winnr,
      keymaps = opts.keymaps,
      _prev_cursor_file = lines[vim.fn.line "."].abs_path,
      _prev_dir = opts.tree_dir,
      icons_enabled = opts.icons_enabled,
      _curr_bufnr = opts._curr_bufnr,
      _curr_winnr = opts._curr_winnr,
      _minimal_tree_win_opts = opts._minimal_tree_win_opts,
      tree_win_opts = opts.tree_win_opts,
    }
  end

  local inc_level = function()
    recurse {
      level = opts.level + 1,
    }
  end

  local dec_level = function()
    if opts.level == 1 then
      vim.notify("[tree.nvim] level must be greater than 0", vim.log.levels.INFO)
      return
    end
    recurse {
      level = opts.level - 1,
    }
  end

  local out_dir = function()
    recurse {
      tree_dir = vim.fs.dirname(opts.tree_dir),
      level = 1,
    }
  end

  local in_dir = function()
    local line = lines[vim.fn.line "."]
    if vim.fn.isdirectory(line.abs_path) == vimscript_true then
      recurse {
        tree_dir = line.abs_path,
        level = 1,
      }
    end
  end

  local close_tree = function()
    vim.api.nvim_win_close(opts._tree_winnr, true)
  end

  local select = function()
    local line = lines[vim.fn.line "."]

    if vim.fn.isdirectory(line.abs_path) == vimscript_true then
      in_dir()
      return
    end

    close_tree()
    vim.api.nvim_set_current_win(opts._curr_winnr)
    vim.cmd("edit " .. line.abs_path)
  end

  local yank_abs_path = function()
    local line = lines[vim.fn.line "."]
    vim.fn.setreg("", line.abs_path)
    vim.fn.setreg("+", line.abs_path)
    vim.notify(("[tree.nvim] absolute path yanked: %s"):format(line.abs_path), vim.log.levels.INFO)
  end

  local yank_rel_path = function()
    local line = lines[vim.fn.line "."]
    local cwd = vim.fn.getcwd()
    local rel_path = vim.fs.relpath(cwd, line.abs_path)
    vim.fn.setreg("", rel_path)
    vim.fn.setreg("+", rel_path)
    vim.notify(("[tree.nvim] relative path yanked: %s"):format(rel_path), vim.log.levels.INFO)
  end

  local refresh = function()
    recurse()
  end

  local create = function()
    local line = lines[vim.fn.line "."]
    local dirname = vim.fs.dirname(vim.fs.relpath(vim.fn.getcwd(), line.abs_path))
    local create_path = vim.fn.input("Create a file or directory: ", dirname .. "/")
    if create_path == "" then
      vim.notify("[tree.nvim] Aborting create", vim.log.levels.INFO)
      return
    end

    local option = vim.fn.confirm(("Create %s?"):format(create_path), "&Yes\n&No", 2)
    if option == 2 then
      vim.notify("[tree.nvim] Aborting create", vim.log.levels.INFO)
      return
    end

    if vim.endswith(create_path, "/") then
      if fs_exists(create_path) then
        vim.notify(
          ("[tree.nvim] Cannot create a directory that already exists: %s"):format(create_path),
          vim.log.levels.ERROR
        )
        return
      end

      local mkdir_success = vim.fn.mkdir(create_path, "p")
      if mkdir_success == vimscript_false then
        vim.notify("[tree.nvim] vim.fn.mkdir returned 0", vim.log.levels.ERROR)
        return
      end

      vim.schedule(refresh)
      return
    end

    if fs_exists(create_path) then
      vim.notify(
        ("[tree.nvim] Cannot create a file that already exists: %s"):format(create_path),
        vim.log.levels.ERROR
      )
      return
    end

    local mkdir_success = vim.fn.mkdir(vim.fs.dirname(create_path), "p")
    if mkdir_success == vimscript_false then
      vim.notify("[tree.nvim] vim.fn.mkdir returned 0", vim.log.levels.ERROR)
      return
    end

    local writefile_success = vim.fn.writefile({}, create_path)
    if writefile_success == -1 then
      vim.notify("[tree.nvim] vim.fn.writefile returned -1", vim.log.levels.ERROR)
      return
    end

    vim.schedule(refresh)
    vim.cmd "doautocmd User TreeCreate"
  end

  local delete = function()
    local line = lines[vim.fn.line "."]
    local option = vim.fn.confirm(("Delete? %s"):format(line.abs_path), "&Yes\n&No", 2)
    if option == 2 then
      vim.notify("[tree.nvim] Aborting delete", vim.log.levels.INFO)
      return
    end

    local success = vim.fn.delete(line.abs_path, "rf")
    if success == -1 then
      vim.notify("[tree.nvim] vim.fn.delete returned -1", vim.log.levels.ERROR)
      return
    end

    vim.schedule(refresh)
    vim.cmd "doautocmd User TreeDelete"
  end

  local rename = function()
    local line = lines[vim.fn.line "."]
    local rename_path = vim.fn.input("Rename to: ", line.abs_path)
    if rename_path == "" then
      vim.notify("[tree.nvim] Aborting rename", vim.log.levels.INFO)
      return
    end

    local option = vim.fn.confirm(("Rename %s -> %s"):format(line.abs_path, rename_path), "&Yes\n&No", 2)
    if option == 2 then
      vim.notify("[tree.nvim] Aborting rename", vim.log.levels.INFO)
      return
    end

    if fs_exists(rename_path) then
      vim.notify(
        ("[tree.nvim] Rename path already exists: %s"):format(rename_path),
        vim.log.levels.ERROR
      )
      return
    end

    local success = vim.fn.rename(line.abs_path, rename_path)
    if success ~= 0 then
      vim.notify("[tree.nvim] vim.fn.rename returned a non-zero value: " .. success, vim.log.levels.ERROR)
      return
    end
    vim.schedule(refresh)
    vim.cmd "doautocmd User TreeRename"
  end

  local keymap_fns = {
    CloseTree = close_tree,
    Select = select,
    IncreaseLevel = inc_level,
    DecreaseLevel = dec_level,
    OutDir = out_dir,
    InDir = in_dir,
    YankRelativePath = yank_rel_path,
    YankAbsolutePath = yank_abs_path,
    Create = create,
    Refresh = refresh,
    Delete = delete,
    Rename = rename,
  }

  for action, fn in pairs(keymap_fns) do
    vim.keymap.set("n", "<Plug>Tree" .. action, fn, {
      buffer = opts._tree_bufnr,
      desc = "Tree: " .. action,
    })
  end
end

return M
