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

  local icon_type = (function()
    if vim.fn.isdirectory(opts.abs_path) == vimscript_true then
      return "directory"
    end
    return "file"
  end)()
  local icon_char, icon_hl = mini_icons.get(icon_type, opts.abs_path)

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

--- @class TreeKeymaps
--- @field [string] "close-tree"|"select"|"out-dir"|"in-dir"|"inc-limit"|"dec-limit"|"yank-abs-path"|"yank-rel-path"

--- @class TreeOpts
--- @field tree_dir? string
--- @field limit? number
--- @field tree_win_opts? vim.wo
--- @field keymaps TreeKeymaps
--- @field icons_enabled boolean
--- @field _tree_bufnr? number
--- @field _tree_winnr? number
--- @field _minimal_tree_win_opts? table
--- @field _curr_winnr? number
--- @field _curr_bufnr? number
--- @field _prev_cursor_abs_path? string
--- @param opts? TreeOpts
M.tree = function(opts)
  opts = default(opts, {})
  opts = vim.deepcopy(opts)

  opts.limit = default(opts.limit, 1)
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

  local obj = vim.system(
    { "tree", "-f", "-a", "--noreport", "--charset=ascii", "-L", tostring(opts.limit), },
    { cwd = opts.tree_dir, }
  ):wait()

  if obj.code ~= 0 then
    error "[tree.nvim] `tree` exit code was not `0`"
  end

  if not obj.stdout then
    error "[tree.nvim] no stdout from `tree`"
  end

  --- @type Line[]
  local lines = {}
  --- @type string[]
  local formatted_lines = {}
  local max_line_width = 0
  local _prev_cursor_abs_path_line = nil
  local curr_bufname_abs_path_line = nil

  for idx, str in ipairs(vim.split(obj.stdout, "\n")) do
    if str == "" then
      goto continue
    end

    local period_pos = str:find "%."
    if not period_pos then
      error "[tree.nvim] malformed stdout, expected each line to start with a `.`"
    end

    local prefix_length = period_pos - 1
    local whitespace = string.rep(" ", prefix_length / 2)
    local filename = str:sub(period_pos)

    local rel_path = vim.fs.normalize(filename)
    local abs_path = vim.fs.joinpath(opts.tree_dir, rel_path)
    if abs_path == opts._prev_cursor_abs_path then
      _prev_cursor_abs_path_line = idx
    end
    if abs_path == curr_bufname_abs_path then
      curr_bufname_abs_path_line = idx
    end
    local basename = vim.fs.basename(abs_path)
    local icon_info = get_icon_info { abs_path = abs_path, icons_enabled = opts.icons_enabled, }
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

    ::continue::
  end

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
    local title = ("tree %s/ -L %s"):format(vim.fs.basename(opts.tree_dir), opts.limit)
    local border_height = 2
    local width = math.max(#title, max_line_width + width_padding)
    local editor_height = vim.o.lines - 1
    local height = math.max(
      1,
      math.min(math.max(1, #lines), editor_height - border_height)
    )

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

  if curr_bufname_abs_path_line then
    vim.api.nvim_buf_set_mark(opts._tree_bufnr, "a", curr_bufname_abs_path_line, 0, {})
  end

  if _prev_cursor_abs_path_line then
    vim.cmd "normal! gg"
    vim.api.nvim_win_set_cursor(opts._tree_winnr, { _prev_cursor_abs_path_line, 0, })
  elseif curr_bufname_abs_path_line then
    vim.cmd "normal! gg'a"
  end

  local function get_cursor_abs_path()
    local line_nr = vim.fn.line "."
    local line = lines[line_nr]
    return line.abs_path
  end

  --- @class RecurseOpts
  --- @field limit? number
  --- @field tree_dir? string
  --- @param ropts? RecurseOpts
  local function recurse(ropts)
    ropts = default(ropts, {})
    ropts = vim.deepcopy(ropts)
    ropts.limit = default(ropts.limit, opts.limit)
    ropts.tree_dir = default(ropts.tree_dir, opts.tree_dir)
    M.tree {
      limit = ropts.limit,
      _tree_bufnr = opts._tree_bufnr,
      tree_dir = ropts.tree_dir,
      _tree_winnr = opts._tree_winnr,
      keymaps = opts.keymaps,
      _prev_cursor_abs_path = get_cursor_abs_path(),
      icons_enabled = opts.icons_enabled,
      _curr_bufnr = opts._curr_bufnr,
      _curr_winnr = opts._curr_winnr,
      _minimal_tree_win_opts = opts._minimal_tree_win_opts,
      tree_win_opts = opts.tree_win_opts,
    }
    lines = nil
  end

  local function inc_limit()
    recurse {
      limit = opts.limit + 1,
    }
  end

  local function dec_limit()
    if opts.limit == 1 then
      vim.notify("[tree.nvim] limit must be greater than 0", vim.log.levels.INFO)
      return
    end
    recurse {
      limit = opts.limit - 1,
    }
  end

  local function out_dir()
    recurse {
      tree_dir = vim.fs.dirname(opts.tree_dir),
    }
  end

  local function in_dir()
    local line = lines[vim.fn.line "."]
    if vim.fn.isdirectory(line.abs_path) == vimscript_true then
      recurse {
        tree_dir = line.abs_path,
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
    vim.notify("[tree.nvim] absolute path yanked", vim.log.levels.INFO)
  end

  local yank_rel_path = function()
    local line = lines[vim.fn.line "."]
    local cwd = vim.fn.getcwd()
    vim.fn.setreg("", vim.fs.relpath(cwd, line.abs_path))
    vim.fn.setreg("+", vim.fs.relpath(cwd, line.abs_path))
    vim.notify("[tree.nvim] relative path yanked", vim.log.levels.INFO)
  end

  local refresh = function()
    recurse()
  end

  local create = function()
    local line = lines[vim.fn.line "."]
    local dirname = (function()
      local rel_path = vim.fs.relpath(vim.fn.getcwd(), line.abs_path)
      if vim.fn.isdirectory(line.abs_path) == vimscript_true then
        return rel_path
      end
      return vim.fs.dirname(rel_path)
    end)()

    local create_path = vim.fn.input("Create a file or dir: ", dirname .. "/")
    if create_path == "" then return end

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
    if writefile_success == vimscript_false then
      vim.notify("[tree.nvim] vim.fn.writefile returned 0", vim.log.levels.ERROR)
      return
    end

    vim.schedule(refresh)
  end

  local delete = function()
    local line = lines[vim.fn.line "."]
    local option = vim.fn.confirm(("Delete %s?"):format(line.abs_path), "&Yes\n&No", 2)
    if option == 2 then
      vim.notify("[tree.nvim] Aborting delete", vim.log.levels.INFO)
      return
    end

    local success = vim.fn.delete(line.abs_path, "rf")
    if success == vimscript_false then
      vim.notify("[tree.nvim] vim.fn.delete returned 0", vim.log.levels.ERROR)
      return
    end

    vim.schedule(refresh)
  end

  local rename = function()
    local line = lines[vim.fn.line "."]
    local rename_path = vim.fn.input("Rename: ", line.abs_path)
    if rename_path == "" then return end

    if fs_exists(rename_path) then
      vim.notify(
        ("[tree.nvim] Rename path already exists: %s"):format(rename_path),
        vim.log.levels.ERROR
      )
      return
    end

    local success = vim.fn.rename(line.abs_path, rename_path)
    if success == vimscript_false then
      vim.notify("[tree.nvim] vim.fn.rename returned 0", vim.log.levels.ERROR)
      return
    end
    vim.schedule(refresh)
  end

  local keymap_fns = {
    ["close-tree"] = close_tree,
    select = select,
    ["inc-limit"] = inc_limit,
    ["dec-limit"] = dec_limit,
    ["out-dir"] = out_dir,
    ["in-dir"] = in_dir,
    ["yank-rel-path"] = yank_rel_path,
    ["yank-abs-path"] = yank_abs_path,
    create = create,
    refresh = refresh,
    delete = delete,
    rename = rename,
  }

  for key, map in pairs(opts.keymaps) do
    vim.keymap.set("n", key, function()
      keymap_fns[map]()
    end, { buffer = opts._tree_bufnr, })
  end
end

return M
