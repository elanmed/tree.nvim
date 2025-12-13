local M = {}

local vimscript_true = 1
local vimscript_false = 0

local ns_id = vim.api.nvim_create_namespace "Tree"
vim.g.tree_winnr = -1

local esc_to_normal = function()
  local curr_mode = vim.fn.mode()
  if curr_mode == "v" or curr_mode == "V" then
    vim.api.nvim_feedkeys(
      vim.api.nvim_replace_termcodes("<Esc>", true, false, true),
      "n",
      false
    )
  end
end

local clear_cmdline = function()
  vim.cmd "normal! :<Esc>"
end

local Batch = {}
Batch.__index = Batch

--- @generic State, Var, Ret1, Ret2
--- @param iter fun(): ((fun(State, Var): (Ret1, Ret2)), State?, Var?)
function Batch:new(iter)
  local state = {
    _iter = iter,
  }

  return setmetatable(state, Batch)
end

--- @param cb fun(val1: any, val2: any):nil
--- @param on_complete fun():nil
function Batch:each(cb, on_complete)
  local batch_co = coroutine.create(function()
    local idx = 1
    for val1, val2 in self._iter() do
      cb(val1, val2)
      if idx % 50 == 0 then
        coroutine.yield()
      end
      idx = idx + 1
    end
  end)

  local step
  step = function()
    coroutine.resume(batch_co)
    if coroutine.status(batch_co) == "suspended" then
      vim.schedule(step)
    elseif coroutine.status(batch_co) == "dead" then
      on_complete()
    end
  end
  step()
end

--- @param promise fun(resolve: fun():nil):nil
local await = function(promise)
  local thread = coroutine.running()
  assert(thread ~= nil, "`await` can only be called in a coroutine")
  local resolved = false
  -- TODO: A simpler alternative would be wrap `promise` in a `vim.schedule` to ensure
  -- that `yield` is always called before the callback in `promise` runs, but this
  -- has been tricky for tests
  promise(function()
    resolved = true
    if coroutine.status(thread) == "suspended" then coroutine.resume(thread) end
  end)
  if not resolved then
    coroutine.yield()
  end
end

--- @param fn fun():nil
local async = function(fn)
  return function(...)
    local ok, err = coroutine.resume(coroutine.create(fn), ...)
    if not ok then error(err) end
  end
end

--- @param level vim.log.levels
--- @param msg string
--- @param ... any
local notify = function(level, msg, ...)
  msg = "[tree.nvim]: " .. msg
  vim.notify(msg:format(...), level)
end

--- @generic T, U
--- @param val T|nil
--- @param fallback U
--- @return T|U
local if_nil = function(val, fallback)
  if val == nil then
    return fallback
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
    icon_char = icon_char .. " ",
    icon_hl = icon_hl,
  }
end

--- @param winnr number
--- @param opts vim.wo
local set_opts = function(winnr, opts)
  for opt, value in pairs(opts) do
    vim.api.nvim_set_option_value(opt, value, { win = winnr, })
  end
end

--- @param lines Line['']
--- @return Line[]
local get_visual_or_current_lines = function(lines)
  --- @type string
  local curr_mode = vim.fn.mode()
  if curr_mode == "v" or curr_mode == "V" then
    local start_line = vim.fn.line "."
    local end_line = vim.fn.line "v"
    if start_line > end_line then
      start_line = vim.fn.line "v"
      end_line = vim.fn.line "."
    end

    if not lines[start_line] or not lines[end_line] then return {} end
    return vim.list_slice(lines, start_line, end_line)
  else
    local line = lines[vim.fn.line "."]
    if not line then return {} end
    return { line, }
  end
end

--- @class GetDestPathOpts
--- @field path string
--- @field tree_dir string
--- @param opts GetDestPathOpts
local normalize_dest_path = function(opts)
  local dest_path = opts.path
  while vim.fs.dirname(dest_path) ~= opts.tree_dir and vim.startswith(dest_path, opts.tree_dir) do
    dest_path = vim.fs.dirname(dest_path)
  end
  return dest_path
end

--- @class NormalizePrevIdxOpts
--- @field _prev_idx number
--- @field lines Line[]
--- @param opts NormalizePrevIdxOpts
local normalize_prev_idx = function(opts)
  if opts._prev_idx == nil then return 1 end

  local prev_line_idx = opts._prev_idx
  while prev_line_idx > #opts.lines do
    prev_line_idx = prev_line_idx - 1
  end

  if prev_line_idx == 0 then
    prev_line_idx = 1
  end

  return prev_line_idx
end

--- @class Line
--- @field abs_path string
--- @field rel_path string
--- @field formatted string
--- @field icon_char string
--- @field icon_hl string

--- @alias TreeCursorPosType "curr-bufname"|"prev-idx"|"history-stack"|"prev-dir-idx"|"dest-path"

--- @class TreeOpts
--- @field tree_dir? string
--- @field tree_win_opts? vim.wo
--- @field icons_enabled? boolean
--- @field tree_win_config? table
--- @field _tree_bufnr? number
--- @field _curr_winnr? number
--- @field _curr_bufnr? number
--- @field _prev_path? string
--- @field _prev_idx? number
--- @field _dest_path? string
--- @field _cursor_pos_type? TreeCursorPosType
--- @field _history? string[]

local open
--- @param opts? TreeOpts
open = function(opts)
  opts = if_nil(opts, {})
  opts = vim.deepcopy(opts)

  opts.icons_enabled = if_nil(opts.icons_enabled, true)
  opts.tree_win_opts = if_nil(opts.tree_win_opts, {})
  opts.tree_win_config = if_nil(opts.tree_win_config, {})
  opts._history = if_nil(opts._history, {})
  opts._cursor_pos_type = if_nil(opts._cursor_pos_type, "curr-bufname")

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
      return vim.fs.abspath(vim.fn.getcwd())
    end

    local dir = curr_bufname_abs_path
    while vim.fn.isdirectory(dir) == vimscript_false do
      dir = vim.fs.dirname(dir)
    end
    return dir
  end)()
  opts.tree_dir = if_nil(opts.tree_dir, curr_dir)
  opts.tree_dir = vim.fs.normalize(vim.fs.abspath(opts.tree_dir))

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

  --- @type Line[]
  local lines = {}

  --- @type string[]
  local formatted_lines = {}

  local max_line_width = 0

  --- @type number
  local prev_dir_idx = nil

  --- @type number
  local curr_bufname_idx = nil

  --- @type number
  local dest_path_idx = nil

  --- @type number
  local history_line = nil
  local top_history = opts._history[#opts._history]

  local populate_lines = function(name, type)
    name = type == "directory" and name .. "/" or name

    local rel_path = vim.fs.normalize(name)
    local abs_path = vim.fs.normalize(vim.fs.joinpath(opts.tree_dir, rel_path))
    local basename = vim.fs.basename(abs_path)

    local icon_type = type == "directory" and "directory" or "file"
    local icon_info = get_icon_info { abs_path = abs_path, icons_enabled = opts.icons_enabled, type = icon_type, }
    local formatted = " " .. icon_info.icon_char .. basename
    max_line_width = math.max(max_line_width, #formatted)

    --- @type Line
    local line = {
      abs_path = abs_path,
      rel_path = vim.fs.relpath(vim.fn.getcwd(), abs_path),
      formatted = formatted,
      icon_char = icon_info.icon_char,
      icon_hl = icon_info.icon_hl,
    }
    table.insert(lines, line)
    table.insert(formatted_lines, formatted)

    if abs_path == top_history then
      history_line = #lines
    end

    if abs_path == curr_bufname_abs_path then
      curr_bufname_idx = #lines
    end

    if abs_path == vim.fs.dirname(opts._prev_path) then
      prev_dir_idx = #lines
    end

    if abs_path == opts._dest_path then
      dest_path_idx = #lines
    end
  end

  await(function(resolve)
    Batch:new(function() return vim.fs.dir(opts.tree_dir) end):each(populate_lines, resolve)
  end)

  vim.api.nvim_set_option_value("modifiable", true, { buf = opts._tree_bufnr, })
  vim.api.nvim_buf_set_lines(opts._tree_bufnr, 0, -1, false, formatted_lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = opts._tree_bufnr, })

  local highlight_lines = function(idx, line)
    local leading_space = 1
    local icon_hl_col_0_indexed = leading_space
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

  await(function(resolve)
    Batch:new(function() return ipairs(lines) end):each(highlight_lines, resolve)
  end)

  local width_padding = 10

  vim.g.tree_winnr = (function()
    local dirname = vim.fs.joinpath(vim.fs.basename(opts.tree_dir), "/")
    local title = ("%s (%d lines)"):format(dirname, #lines)
    local border_height = 2
    local width = math.max(#title, max_line_width + width_padding)
    local editor_height = vim.api.nvim_win_get_height(opts._curr_winnr)
    local height = math.min(#lines, editor_height - border_height)
    if height < 1 then height = 1 end

    if vim.api.nvim_win_is_valid(vim.g.tree_winnr) then
      vim.api.nvim_set_current_win(vim.g.tree_winnr)
      vim.api.nvim_win_set_config(vim.g.tree_winnr, {
        title = title,
        width = width,
        height = height,
      })
      return vim.g.tree_winnr
    end

    local win_config = vim.tbl_deep_extend("force", {
      relative = "editor",
      row = 1,
      col = 0,
      width = width,
      height = height,
      border = "rounded",
      style = "minimal",
      title = title,
    }, opts.tree_win_config)
    local tree_winnr = vim.api.nvim_open_win(opts._tree_bufnr, true, win_config)
    vim.api.nvim_set_option_value("foldmethod", "indent", { win = tree_winnr, })
    vim.api.nvim_set_option_value("cursorline", true, { win = tree_winnr, })
    set_opts(tree_winnr, opts.tree_win_opts)

    return tree_winnr
  end)()
  vim.api.nvim_win_set_buf(vim.g.tree_winnr, opts._tree_bufnr)

  if opts._cursor_pos_type == "curr-bufname" then
    vim.api.nvim_win_set_cursor(vim.g.tree_winnr, { curr_bufname_idx or 1, 0, })
  elseif opts._cursor_pos_type == "history-stack" then
    if history_line then
      vim.api.nvim_win_set_cursor(vim.g.tree_winnr, { history_line, 0, })
      table.remove(opts._history)
    else
      vim.api.nvim_win_set_cursor(vim.g.tree_winnr, { 1, 0, })
      opts._history = {}
    end
  elseif opts._cursor_pos_type == "prev-dir-idx" then
    if prev_dir_idx then
      vim.api.nvim_win_set_cursor(vim.g.tree_winnr, { prev_dir_idx, 0, })
    else
      notify(vim.log.levels.ERROR, "Expected to find the prev dir when setting the cursor")
    end
  elseif opts._cursor_pos_type == "prev-idx" then
    vim.api.nvim_win_set_cursor(vim.g.tree_winnr, {
      normalize_prev_idx { lines = lines, _prev_idx = opts._prev_idx, },
      0,
    })
  elseif opts._cursor_pos_type == "dest-path" then
    if dest_path_idx then
      vim.api.nvim_win_set_cursor(vim.g.tree_winnr, { dest_path_idx, 0, })
    else
      vim.api.nvim_win_set_cursor(vim.g.tree_winnr, {
        normalize_prev_idx { lines = lines, _prev_idx = opts._prev_idx, },
        0,
      })
    end
  else
    vim.api.nvim_win_set_cursor(vim.g.tree_winnr, { 1, 0, })
  end

  --- @class RecurseOpts
  --- @field tree_dir? string
  --- @field _dest_path? string
  --- @field _cursor_pos_type TreeCursorPosType

  --- @param r_opts RecurseOpts
  local recurse = function(r_opts)
    r_opts = vim.deepcopy(r_opts)
    r_opts.tree_dir = if_nil(r_opts.tree_dir, opts.tree_dir)

    async(open) {
      tree_dir = r_opts.tree_dir,
      _cursor_pos_type = r_opts._cursor_pos_type,
      _dest_path = r_opts._dest_path,
      _prev_path = (function()
        local line = lines[vim.fn.line "."]
        if line then return line.abs_path end
      end)(),

      tree_win_opts = opts.tree_win_opts,
      icons_enabled = opts.icons_enabled,
      tree_win_config = opts.tree_win_config,

      _tree_bufnr = opts._tree_bufnr,
      _curr_winnr = opts._curr_winnr,
      _curr_bufnr = opts._curr_bufnr,
      _history = opts._history,
      _prev_idx = vim.fn.line ".",
    }
  end

  local out_dir = function()
    local line = lines[vim.fn.line "."]
    if line then table.insert(opts._history, line.abs_path) end

    recurse {
      tree_dir = vim.fs.dirname(opts.tree_dir),
      _cursor_pos_type = "prev-dir-idx",
    }
  end

  local in_dir = function()
    local line = lines[vim.fn.line "."]
    if not line then return end
    if vim.fn.isdirectory(line.abs_path) == vimscript_true then
      recurse {
        tree_dir = line.abs_path,
        _cursor_pos_type = "history-stack",
      }
    end
  end

  local close_tree = function()
    if vim.api.nvim_win_is_valid(vim.g.tree_winnr) then
      vim.api.nvim_win_close(vim.g.tree_winnr, true)
    end
  end

  local select = function()
    local line = lines[vim.fn.line "."]
    if not line then return end

    if vim.fn.isdirectory(line.abs_path) == vimscript_true then
      in_dir()
      return
    end

    close_tree()
    vim.api.nvim_set_current_win(opts._curr_winnr)
    vim.cmd.edit(line.abs_path)
  end

  local yank_abs_path = function()
    local line = lines[vim.fn.line "."]
    if not line then return end
    vim.fn.setreg("a", line.abs_path)
    notify(vim.log.levels.INFO, "absolute path yanked: %s", line.abs_path)
  end

  local yank_rel_path = function()
    local line = lines[vim.fn.line "."]
    if not line then return end
    vim.fn.setreg("r", line.rel_path)
    notify(vim.log.levels.INFO, "relative path yanked: %s", line.rel_path)
  end

  local yank_dir = function()
    local line = lines[vim.fn.line "."]
    if not line then return end
    local dirname = vim.fs.dirname(line.abs_path)
    vim.fn.setreg("d", dirname)
    notify(vim.log.levels.INFO, "dirname yanked: %s", dirname)
  end

  local yank_basename = function()
    local line = lines[vim.fn.line "."]
    if not line then return end
    local basename = (function()
      local basename_with_ext = vim.fs.basename(line.abs_path)
      local ext_idx = basename_with_ext:find "%."
      if ext_idx == nil then return basename_with_ext end
      return basename_with_ext:sub(1, ext_idx - 1)
    end)()

    vim.fn.setreg("b", basename)
    notify(vim.log.levels.INFO, "basename yanked: %s", basename)
  end

  local refresh = function()
    recurse { _cursor_pos_type = "prev-idx", }
  end

  local create = function()
    local abs_path = (function()
      local line = lines[vim.fn.line "."]
      if line then return vim.fs.dirname(line.abs_path) end
      return opts.tree_dir
    end)()
    local rel_path = vim.fs.relpath(vim.fn.getcwd(), abs_path)
    local dirname = vim.fs.joinpath(rel_path, "/")

    local raw_create_path = vim.fn.input("Create: ", dirname)
    if raw_create_path == "" then
      clear_cmdline()
      return
    end
    local create_path = vim.fs.normalize(vim.fs.abspath(raw_create_path))

    local option = vim.fn.confirm(("Create? %s"):format(create_path), "&Yes\n&No", 2)
    if option ~= 1 then
      return
    end

    if vim.endswith(raw_create_path, "/") then
      if fs_exists(create_path) then
        notify(vim.log.levels.ERROR, "Cannot create a directory that already exists: %s", create_path)
        return
      end

      local mkdir_success = vim.fn.mkdir(create_path, "p")
      if mkdir_success == vimscript_false then
        notify(vim.log.levels.ERROR, "vim.fn.mkdir(%s, p) returned 0", create_path)
        return
      end

      vim.schedule(function()
        recurse {
          _cursor_pos_type = "dest-path",
          _dest_path = normalize_dest_path { path = create_path, tree_dir = opts.tree_dir, },
        }
      end)
      return
    end

    if fs_exists(create_path) then
      notify(vim.log.levels.ERROR, "Cannot create a file that already exists: %s", create_path)
      return
    end

    local mkdir_success = vim.fn.mkdir(vim.fs.dirname(create_path), "p")
    if mkdir_success == vimscript_false then
      notify(vim.log.levels.ERROR, "vim.fn.mkdir(%s) returned 0", vim.fs.dirname(create_path))
      return
    end

    local writefile_success = vim.fn.writefile({}, create_path)
    if writefile_success == -1 then
      notify(vim.log.levels.ERROR "vim.fn.writefile({}, %s) returned -1", create_path)
      return
    end

    vim.schedule(function()
      recurse {
        _cursor_pos_type = "dest-path",
        _dest_path = normalize_dest_path { path = create_path, tree_dir = opts.tree_dir, },
      }
    end)
    vim.cmd "doautocmd User TreeCreate"

    vim.api.nvim_win_call(opts._curr_winnr, function()
      vim.cmd.edit(create_path)
    end)
  end

  local delete = function()
    --- @param lines_arg Line[]
    local delete_lines = function(lines_arg)
      local abs_path_tbl = {}
      for _, line in ipairs(lines_arg) do
        table.insert(abs_path_tbl, line.abs_path)
      end
      local abs_path_str = table.concat(abs_path_tbl, "\n")

      local option = vim.fn.confirm(("Delete?\n%s"):format(abs_path_str), "&Yes\n&No", 2)
      if option ~= 1 then
        esc_to_normal()
        return
      end

      for _, line in ipairs(lines_arg) do
        local success = vim.fn.delete(line.abs_path, "rf")
        if success == -1 then
          notify(vim.log.levels.ERROR, "vim.fn.delete(%s, rf) returned -1", line.abs_path)
        end
      end

      vim.cmd "doautocmd User TreeDelete"
      esc_to_normal()
      vim.schedule(function() recurse { _cursor_pos_type = "prev-idx", } end)
    end

    local visual_or_current_lines = get_visual_or_current_lines(lines)
    delete_lines(visual_or_current_lines)
  end

  local rename = function()
    local line = lines[vim.fn.line "."]
    if not line then return end
    local raw_rename_path = vim.fn.input("Rename to: ", line.rel_path)
    if raw_rename_path == "" then
      clear_cmdline()
      return
    end
    local rename_path = vim.fs.normalize(vim.fs.abspath(raw_rename_path))

    local option = vim.fn.confirm(("Rename\nFrom: %s\nTo:   %s"):format(line.abs_path, rename_path), "&Yes\n&No", 2)
    if option ~= 1 then
      return
    end

    if fs_exists(rename_path) then
      notify(vim.log.levels.ERROR, "Rename path already exists: %s", rename_path)
      return
    end

    local success = vim.fn.rename(line.abs_path, rename_path)
    if success ~= 0 then
      notify(vim.log.levels.ERROR, "vim.fn.rename(%s, %s) returned %d", line.abs_path, rename_path, success)
      return
    end
    vim.schedule(function()
      recurse {
        _cursor_pos_type = "dest-path",
        _dest_path = rename_path,
      }
    end)
    vim.cmd "doautocmd User TreeRename"
  end

  --- @param should_delete boolean
  local copy_and_maybe_delete = function(should_delete)
    local display_name = should_delete and "Move" or "Copy"
    local raw_copy_path = vim.fn.input(("%s to a directory: "):format(display_name))

    if raw_copy_path == "" then
      clear_cmdline()
      esc_to_normal()
      return
    end
    local copy_path = vim.fs.normalize(vim.fs.abspath(raw_copy_path))

    --- @param lines_arg Line[]
    local copy_lines = function(lines_arg)
      local abs_path_tbl = {}
      for _, line in ipairs(lines_arg) do
        table.insert(abs_path_tbl, line.abs_path)
      end
      local abs_path_str = table.concat(abs_path_tbl, "\n")

      local option = vim.fn.confirm(
        ("%s files:\n%s\nTo:\n%s"):format(display_name, abs_path_str, copy_path),
        "&Yes\n&No",
        2
      )
      if option ~= 1 then
        esc_to_normal()
        return
      end

      local mkdir_success = vim.fn.mkdir(copy_path, "p")
      if mkdir_success == vimscript_false then
        notify(vim.log.levels.ERROR, "vim.fn.mkdir(%s, p) returned 0", copy_path)
        esc_to_normal()
        return
      end

      for _, line in ipairs(lines_arg) do
        local copy_file_path = vim.fs.normalize(
          vim.fs.joinpath(
            copy_path,
            vim.fs.relpath(opts.tree_dir, line.abs_path)
          )
        )

        if fs_exists(copy_file_path) then
          notify(
            vim.log.levels.ERROR,
            "A file %s already exists at path %s, skipping",
            vim.fs.basename(line.abs_path),
            copy_path
          )
          goto continue
        end

        local obj_cp = vim.system { "cp", "-r", line.abs_path, copy_path, }:wait()
        if obj_cp.code ~= 0 then
          notify(vim.log.levels.ERROR, "`cp -r` exit code was %d", obj_cp.code)
          goto continue
        end

        if should_delete then
          vim.fn.delete(line.abs_path, "rf")
        end

        ::continue::
      end

      if should_delete then
        vim.cmd "doautocmd User TreeMove"
      else
        vim.cmd "doautocmd User TreeCopy"
      end
      esc_to_normal()
      vim.schedule(function()
        recurse {
          _cursor_pos_type = "dest-path",
          _dest_path = copy_path,
        }
      end)
    end

    local visual_or_current_lines = get_visual_or_current_lines(lines)
    copy_lines(visual_or_current_lines)
  end

  local normal_keymap_fns = {
    CloseTree = close_tree,
    Select = select,
    OutDir = out_dir,
    InDir = in_dir,
    YankRelativePath = yank_rel_path,
    YankAbsolutePath = yank_abs_path,
    YankDirectory = yank_dir,
    YankBasename = yank_basename,
    Create = create,
    Refresh = refresh,
    Delete = delete,
    Rename = rename,
    Copy = function() copy_and_maybe_delete(false) end,
    Move = function() copy_and_maybe_delete(true) end,
  }

  local visual_keymap_fns = {
    Delete = delete,
    Copy = function() copy_and_maybe_delete(false) end,
    Move = function() copy_and_maybe_delete(true) end,
  }

  for fn_name, fn in pairs(normal_keymap_fns) do
    vim.keymap.set("n", "<Plug>Tree" .. fn_name, fn, {
      buffer = opts._tree_bufnr,
      desc = "Tree: " .. fn_name,
    })
  end

  for fn_name, fn in pairs(visual_keymap_fns) do
    vim.keymap.set("v", "<Plug>Tree" .. fn_name, fn, {
      buffer = opts._tree_bufnr,
      desc = "Tree: " .. fn_name,
    })
  end
end

--- @param opts? TreeOpts
M.tree = function(opts)
  async(open)(opts)
end

return M
