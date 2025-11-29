local M = {}

local vimscript_true = 1
local vimscript_false = 0

local ns_id = vim.api.nvim_create_namespace "Tree"
vim.g.tree_winnr = -1

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

--- @alias TreePrevAction "open"|"out-dir"|"in-dir"|"refresh"|"create"|"update-level"

--- @class TreeOpts
--- @field tree_dir? string
--- @field level? number
--- @field tree_win_opts? vim.wo
--- @field icons_enabled? boolean
--- @field tree_win_config? table
--- @field _tree_bufnr? number
--- @field _curr_winnr? number
--- @field _curr_bufnr? number
--- @field _prev_path? string
--- @field _prev_idx? number
--- @field _created_path? string
--- @field _prev_action? TreePrevAction
--- @field _history? string[]

--- @param opts? TreeOpts
M.tree = function(opts)
  opts = default(opts, {})
  opts = vim.deepcopy(opts)

  opts.level = default(opts.level, 1)
  opts.icons_enabled = default(opts.icons_enabled, true)
  opts.tree_win_opts = default(opts.tree_win_opts, {})
  opts.tree_win_config = default(opts.tree_win_config, {})
  opts._history = default(opts._history, {})
  opts._prev_action = default(opts._prev_action, "open")

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

    local dir = curr_bufname_abs_path
    while vim.fn.isdirectory(dir) == vimscript_false do
      dir = vim.fs.dirname(dir)
    end
    return dir
  end)()
  opts.tree_dir = default(opts.tree_dir, curr_dir)
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

  --- @type number
  local prev_path_idx = nil

  --- @type number
  local prev_dir_idx = nil

  --- @type number
  local curr_bufname_idx = nil

  --- @type number
  local created_path_idx = nil

  --- @type number
  local history_line = nil
  local top_history = opts._history[#opts._history]

  --- @param json_arg TreeJson[]
  --- @param indent number
  local function populate_lines(json_arg, indent)
    for _, entry in ipairs(json_arg) do
      local name = entry.type == "directory" and entry.name .. "/" or entry.name

      local rel_path = vim.fs.normalize(name)
      local abs_path = vim.fs.normalize(vim.fs.joinpath(opts.tree_dir, rel_path))
      local basename = vim.fs.basename(abs_path)

      local icon_type = entry.type == "directory" and "directory" or "file"
      local icon_info = get_icon_info { abs_path = abs_path, icons_enabled = opts.icons_enabled, type = icon_type, }
      local whitespace = ("  "):rep(indent)
      local formatted = " " .. whitespace .. icon_info.icon_char .. basename
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

      if abs_path == top_history then
        history_line = #lines
      end

      if abs_path == curr_bufname_abs_path then
        curr_bufname_idx = #lines
      end

      if abs_path == opts._prev_path then
        prev_path_idx = #lines
      end

      if abs_path == vim.fs.dirname(opts._prev_path) then
        prev_dir_idx = #lines
      end

      if abs_path == opts._created_path then
        created_path_idx = #lines
      end

      if entry.contents then
        populate_lines(entry.contents, indent + 1)
      end
    end
  end

  populate_lines(json[1].contents or {}, 0)

  vim.api.nvim_set_option_value("modifiable", true, { buf = opts._tree_bufnr, })
  vim.api.nvim_buf_set_lines(opts._tree_bufnr, 0, -1, false, formatted_lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = opts._tree_bufnr, })

  vim.schedule(function()
    for idx, line in ipairs(lines) do
      local leading_space = 1
      local icon_hl_col_0_indexed = #line.whitespace + leading_space
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

  vim.g.tree_winnr = (function()
    local dirname = vim.fs.joinpath(vim.fs.basename(opts.tree_dir), "/")
    local title = ("tree %s -L %s"):format(dirname, opts.level)
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

  if opts._prev_action == "open" then
    if curr_bufname_idx then
      vim.api.nvim_win_set_cursor(vim.g.tree_winnr, { curr_bufname_idx, 0, })
    end
  elseif opts._prev_action == "in-dir" then
    if history_line then
      vim.api.nvim_win_set_cursor(vim.g.tree_winnr, { history_line, 0, })
      table.remove(opts._history)
    else
      opts._history = {}
    end
  elseif opts._prev_action == "out-dir" then
    if prev_dir_idx then
      vim.api.nvim_win_set_cursor(vim.g.tree_winnr, { prev_dir_idx, 0, })
    else
      vim.notify("[tree.nvim] Expected to find the prev dir when setting the cursor", vim.log.levels.ERROR)
    end
  elseif opts._prev_action == "update-level" then
    if prev_path_idx then
      vim.api.nvim_win_set_cursor(vim.g.tree_winnr, { prev_path_idx, 0, })
    else
      vim.notify("[tree.nvim] Expected to find the prev path when setting the cursor", vim.log.levels.ERROR)
    end
  elseif opts._prev_action == "refresh" then
    local row = (function()
      if opts._prev_idx == nil then return 1 end

      local prev_line_idx = opts._prev_idx
      while prev_line_idx > #lines do
        prev_line_idx = prev_line_idx - 1
      end

      if prev_line_idx == 0 then
        prev_line_idx = 1
      end

      return prev_line_idx
    end)()

    vim.api.nvim_win_set_cursor(vim.g.tree_winnr, { row, 0, })
  elseif opts._prev_action == "create" then
    if created_path_idx then
      vim.api.nvim_win_set_cursor(vim.g.tree_winnr, { created_path_idx, 0, })
    end
  end

  --- @class RecurseOpts
  --- @field level? number
  --- @field tree_dir? string
  --- @field created_path? string
  --- @field prev_path? string
  --- @field prev_action TreePrevAction

  --- @param r_opts RecurseOpts
  local recurse = function(r_opts)
    r_opts = vim.deepcopy(r_opts)
    r_opts.level = default(r_opts.level, opts.level)
    r_opts.tree_dir = default(r_opts.tree_dir, opts.tree_dir)

    M.tree {
      tree_dir = r_opts.tree_dir,
      level = r_opts.level,
      _prev_action = r_opts.prev_action,
      _created_path = r_opts.created_path,
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

  local inc_level = function()
    recurse {
      level = opts.level + 1,
      prev_action = "update-level",
    }
  end

  local dec_level = function()
    if opts.level == 1 then
      vim.notify("[tree.nvim] level must be greater than 0", vim.log.levels.INFO)
      return
    end
    recurse {
      level = opts.level - 1,
      prev_action = "update-level",
    }
  end

  local out_dir = function()
    local line = lines[vim.fn.line "."]
    if line then table.insert(opts._history, line.abs_path) end

    recurse {
      tree_dir = vim.fs.dirname(opts.tree_dir),
      level = 1,
      prev_action = "out-dir",
    }
  end

  local in_dir = function()
    local line = lines[vim.fn.line "."]
    if not line then return end
    if vim.fn.isdirectory(line.abs_path) == vimscript_true then
      recurse {
        tree_dir = line.abs_path,
        level = 1,
        prev_action = "in-dir",
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
    vim.fn.setreg("", line.abs_path)
    vim.fn.setreg("+", line.abs_path)
    vim.notify(("[tree.nvim] absolute path yanked: %s"):format(line.abs_path), vim.log.levels.INFO)
  end

  local yank_rel_path = function()
    local line = lines[vim.fn.line "."]
    if not line then return end
    local cwd = vim.fn.getcwd()
    local rel_path = vim.fs.relpath(cwd, line.abs_path)
    vim.fn.setreg("", rel_path)
    vim.fn.setreg("+", rel_path)
    vim.notify(("[tree.nvim] relative path yanked: %s"):format(rel_path), vim.log.levels.INFO)
  end

  local refresh = function()
    recurse { prev_action = "refresh", }
  end

  local create = function()
    local abs_path = (function()
      local line = lines[vim.fn.line "."]
      if line then return vim.fs.dirname(line.abs_path) end
      return opts.tree_dir
    end)()
    local rel_path = vim.fs.relpath(vim.fn.getcwd(), abs_path)
    local dirname = vim.fs.joinpath(rel_path, "/")

    local create_path = vim.fn.input("Create a file or directory: ", dirname)
    if create_path == "" then
      vim.notify("[tree.nvim] Aborting create", vim.log.levels.INFO)
      return
    end

    local option = vim.fn.confirm(("Create %s?"):format(create_path), "&Yes\n&No", 2)
    if option ~= 1 then
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

      vim.schedule(function()
        recurse {
          prev_action = "create",
          created_path = vim.fs.normalize(vim.fs.joinpath(vim.fn.getcwd(), create_path)),
        }
      end)
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

    vim.schedule(function()
      recurse {
        prev_action = "create",
        created_path = vim.fs.normalize(vim.fs.joinpath(vim.fn.getcwd(), create_path)),
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

      local option = vim.fn.confirm(("Delete? \n%s"):format(abs_path_str), "&Yes\n&No", 2)
      if option ~= 1 then
        vim.notify("[tree.nvim] Aborting delete", vim.log.levels.INFO)
        return
      end

      for _, line in ipairs(lines_arg) do
        local success = vim.fn.delete(line.abs_path, "rf")
        if success == -1 then
          vim.notify(
            ("[tree.nvim] vim.fn.delete %s returned -1"):format(line.abs_path),
            vim.log.levels.ERROR
          )
        end
      end

      vim.schedule(function() recurse { prev_action = "refresh", } end)
      vim.cmd "doautocmd User TreeDelete"
    end

    --- @type string
    local curr_mode = vim.fn.mode()
    if curr_mode == "v" or curr_mode == "V" then
      local start_line = vim.fn.line "."
      local end_line = vim.fn.line "v"
      if start_line > end_line then
        start_line = vim.fn.line "v"
        end_line = vim.fn.line "."
      end

      if not lines[start_line] or not lines[end_line] then return end
      delete_lines(vim.list_slice(lines, start_line, end_line))
    else
      local line = lines[vim.fn.line "."]
      if not line then return end
      delete_lines { line, }
    end
  end

  local rename = function()
    local line = lines[vim.fn.line "."]
    if not line then return end
    local rename_path = vim.fn.input("Rename to: ", line.abs_path)
    if rename_path == "" then
      vim.notify("[tree.nvim] Aborting rename", vim.log.levels.INFO)
      return
    end

    local option = vim.fn.confirm(("Rename %s -> %s"):format(line.abs_path, rename_path), "&Yes\n&No", 2)
    if option ~= 1 then
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
    vim.schedule(function() recurse { prev_action = "refresh", } end)
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

  for fn_name, fn in pairs(keymap_fns) do
    vim.keymap.set("n", "<Plug>Tree" .. fn_name, fn, {
      buffer = opts._tree_bufnr,
      desc = "Tree: " .. fn_name,
    })
  end

  vim.keymap.set("v", "<Plug>TreeDelete", keymap_fns["Delete"], {
    buffer = opts._tree_bufnr,
    desc = "Tree: Delete",
  })
end

return M
