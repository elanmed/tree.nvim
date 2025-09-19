local M = {}

local ns_id = vim.api.nvim_create_namespace "Tree"

local TREE_INSTANCE = nil
local SETUP_CALLED = false
local TREE_CACHE = {}
local LOCKED = false

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

--- @class GetIconInfoOpts
--- @field icons_enabled boolean
--- @field abs_path string
--- @field icon_type "file" | "directory"
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

  local icon_char, icon_hl = mini_icons.get(opts.icon_type, opts.abs_path)
  return {
    icon_char = icon_char,
    icon_hl = icon_hl,
  }
end

--- @class IndentedLine
--- @field abs_path string
--- @field whitespace string
--- @field type "file"|"directory"

--- @class FormattedLine : IndentedLine
--- @field formatted string
--- @field icon_char string
--- @field icon_hl string

--- @param lines FormattedLine[]
local function get_curr_buf_line(lines, curr_buf_abs_path)
  for idx, line in ipairs(lines) do
    if line.abs_path == curr_buf_abs_path then return idx end
  end
  return nil
end

--- @class GetFormattedLinesOpts
--- @field str string
--- @field cwd string
--- @field icons_enabled boolean
--- @param opts GetFormattedLinesOpts
local function get_formatted_line(opts)
  local period_pos = opts.str:find "%."
  if not period_pos then return nil end

  local prefix_length = period_pos - 1
  local whitespace = string.rep(" ", prefix_length / 2)
  local filename = opts.str:sub(period_pos)

  local rel_path = vim.fs.normalize(filename)
  local abs_path = vim.fs.joinpath(opts.cwd, rel_path)

  local type = (function()
    local stat_res = vim.uv.fs_stat(abs_path)
    if not stat_res then
      return "file"
    end
    return stat_res.type
  end)()

  local basename = vim.fs.basename(abs_path)
  local icon_info = get_icon_info { abs_path = abs_path, icon_type = type, icons_enabled = opts.icons_enabled, }
  local formatted = ("%s%s %s"):format(whitespace, icon_info.icon_char, basename)

  --- @type FormattedLine
  local formatted_line = {
    whitespace = whitespace,
    abs_path = abs_path,
    type = type,
    formatted = formatted,
    icon_char = icon_info.icon_char,
    icon_hl = icon_info.icon_hl,

  }
  return formatted_line
end

--- @param mark_name string
local function is_buffer_mark_unset(mark_name)
  local mark = vim.api.nvim_buf_get_mark(0, mark_name)
  return mark[1] == 0 and mark[2] == 0
end

--- @class SetupOpts
--- @field cwd string
--- @field icons_enabled boolean
--- @param opts SetupOpts
local populate_tree_cache = function(opts)
  if LOCKED then return vim.notify "[tree.nvim] locked" end
  LOCKED = true
  TREE_CACHE = {}
  vim.notify "[tree.nvim] Populating the cache ..."
  vim.system({ "tree", "-f", "-a", "--gitignore", "--noreport", "--charset=ascii", }, {
    cwd = opts.cwd,
  }, function(obj)
    local process = coroutine.create(function()
      for _, str in ipairs(vim.split(obj.stdout, "\n")) do
        local formatted_line = get_formatted_line {
          cwd = opts.cwd,
          icons_enabled = opts.icons_enabled,
          str = str,
        }
        if formatted_line == nil then goto continue end

        table.insert(TREE_CACHE, formatted_line)
        coroutine.yield()
        ::continue::
      end
    end)

    local function continue_processing()
      coroutine.resume(process)

      if coroutine.status(process) == "suspended" then
        vim.schedule(continue_processing)
      end
    end
    vim.schedule(continue_processing)
    LOCKED = false
    vim.schedule(function() vim.notify "[tree.nvim] Cache populated" end)
  end)
end

--- @param opts SetupOpts
M.setup = function(opts)
  SETUP_CALLED = true
  opts = default(opts, {})
  opts.cwd = default(opts.cwd, vim.uv.cwd())
  opts.icons_enabled = default(opts.icons_enabled, true)
  populate_tree_cache(opts)
end

--- @class TreeOpts
--- @field icons_enabled boolean
--- @field keymaps TreeKeymaps
--- @field win_type "popup"|"split"
--- @field win_width number

--- @class TreeKeymaps
--- @field [string] "close-tree"|"select-focus-win"|"select-focus-tree"|"select-close-tree"|"refresh"

--- @param opts TreeOpts
M.tree = function(opts)
  if not SETUP_CALLED then
    error "[tree.nvim] `setup` must be called before `tree`"
  end

  if TREE_INSTANCE and vim.api.nvim_win_is_valid(TREE_INSTANCE) then
    vim.api.nvim_set_current_win(TREE_INSTANCE)
    local is_mark_set = not is_buffer_mark_unset "a"
    if is_mark_set then
      vim.cmd "normal! 'a"
    end
    return
  end

  opts = default(opts, {})
  opts.icons_enabled = default(opts.icons_enabled, true)
  opts.keymaps = default(opts.keymaps, {})
  opts.win_type = default(opts.win_type, "split")
  opts.win_width = default(opts.win_width, 50)

  local curr_winnr = vim.api.nvim_get_current_win()
  local curr_bufnr = vim.api.nvim_get_current_buf()
  local bufname_abs_path = vim.api.nvim_buf_get_name(curr_bufnr)
  local cwd = vim.uv.cwd()
  if cwd == nil then
    error "[tree.nvim] `cwd` is nil"
  end

  local tree_bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = tree_bufnr, })
  vim.api.nvim_set_option_value("buflisted", false, { buf = tree_bufnr, })

  local border_height = 2
  local tree_winnr = (function()
    if opts.win_type == "popup" then
      return vim.api.nvim_open_win(tree_bufnr, true, {
        relative = "editor",
        row = 1,
        col = 0,
        width = opts.win_width,
        height = vim.o.lines - 1 - border_height,
        border = "rounded",
        style = "minimal",
        title = "Tree",
      })
    end

    return vim.api.nvim_open_win(tree_bufnr, true, {
      split = "left",
      width = opts.win_width,
      style = "minimal",
    })
  end)()
  TREE_INSTANCE = tree_winnr

  vim.api.nvim_create_autocmd("WinEnter", {
    callback = function()
      if not vim.api.nvim_win_is_valid(tree_winnr) then return end
      if vim.api.nvim_get_current_win() ~= tree_winnr then return end
      if vim.api.nvim_get_current_buf() == tree_bufnr then return end
      vim.api.nvim_win_set_buf(tree_winnr, tree_bufnr)
    end,
  })

  vim.api.nvim_set_option_value("foldmethod", "indent", { win = tree_winnr, })
  vim.api.nvim_set_option_value("cursorline", true, { win = tree_winnr, })
  vim.api.nvim_win_set_buf(tree_winnr, tree_bufnr)

  local close_tree = function()
    if LOCKED then return vim.notify "[tree.nvim] locked" end
    vim.api.nvim_win_close(tree_winnr, true)
  end

  local select = function()
    if LOCKED then return vim.notify "[tree.nvim] locked" end

    local line_nr = vim.fn.line "."
    local line = TREE_CACHE[line_nr]
    if line.type ~= "file" then return end

    vim.api.nvim_set_current_win(curr_winnr)
    vim.cmd("edit " .. vim.trim(line.abs_path))
  end

  local refresh = function()
    if LOCKED then return vim.notify "[tree.nvim] locked" end

    LOCKED = true
    TREE_CACHE = {}
    vim.api.nvim_buf_set_lines(tree_bufnr, 0, -1, false, {})
    vim.notify "[tree.nvim] Refreshing ..."
    vim.system({ "tree", "-f", "-a", "--gitignore", "--noreport", "--charset=ascii", }, {
      cwd = cwd,
      stdout = function(err, data)
        if err then return end
        if not data then return end
        vim.schedule(function()
          --- @type FormattedLine[]
          local formatted_lines = {}

          local chunk = vim.split(data, "\n")
          for _, str in ipairs(chunk) do
            local formatted_line = get_formatted_line { cwd = cwd, icons_enabled = opts.icons_enabled, str = str, }
            if formatted_line then table.insert(formatted_lines, formatted_line) end
          end

          vim.api.nvim_buf_set_lines(
            tree_bufnr, #TREE_CACHE, -1, false,
            vim.tbl_map(function(formatted_line) return formatted_line.formatted end, formatted_lines)
          )
          vim.cmd "redraw"

          for idx, formatted_line in ipairs(formatted_lines) do
            local icon_hl_col_0_indexed = #formatted_line.whitespace
            local row_1_indexed = #TREE_CACHE + idx
            local row_0_indexed = row_1_indexed - 1

            vim.hl.range(
              tree_bufnr,
              ns_id,
              formatted_line.icon_hl,
              { row_0_indexed, icon_hl_col_0_indexed, },
              { row_0_indexed, icon_hl_col_0_indexed + 1, }
            )
          end

          TREE_CACHE = vim.list_extend(TREE_CACHE, formatted_lines)
        end)
      end,
    }, function()
      vim.schedule(function()
        local curr_bufnr_line = get_curr_buf_line(TREE_CACHE, bufname_abs_path)
        if curr_bufnr_line then
          vim.api.nvim_win_set_cursor(tree_winnr, { curr_bufnr_line, 0, })
          vim.api.nvim_buf_set_mark(0, "a", curr_bufnr_line, 0, {})
        end
        vim.cmd "normal! zz"
        LOCKED = false
        vim.notify "[tree.nvim] Done refreshing"
      end)
    end)
  end

  local keymap_fns = {
    refresh = refresh,
    ["close-tree"] = close_tree,
    ["select-close-tree"] = function()
      if LOCKED then return vim.notify "[tree.nvim] locked" end

      select()
      close_tree()
    end,
    ["select-focus-win"] = select,
    ["select-focus-tree"] = function()
      if LOCKED then return vim.notify "[tree.nvim] locked" end

      local line_nr = vim.fn.line "."
      local line = TREE_CACHE[line_nr]
      if line.type ~= "file" then return end

      vim.api.nvim_win_call(curr_winnr, function()
        vim.cmd("edit " .. vim.trim(line.abs_path))
      end)
    end,
  }

  for key, map in pairs(opts.keymaps) do
    vim.keymap.set("n", key, function()
      keymap_fns[map]()
    end, { buffer = tree_bufnr, })
  end

  local process = coroutine.create(function()
    for idx, formatted_line in ipairs(TREE_CACHE) do
      vim.api.nvim_buf_set_lines(tree_bufnr, #TREE_CACHE + idx - 1, -1, false, { formatted_line.formatted, })

      local icon_hl_col_0_indexed = #formatted_line.whitespace
      local row_1_indexed = #TREE_CACHE + idx
      local row_0_indexed = row_1_indexed - 1

      vim.hl.range(
        tree_bufnr,
        ns_id,
        formatted_line.icon_hl,
        { row_0_indexed, icon_hl_col_0_indexed, },
        { row_0_indexed, icon_hl_col_0_indexed + 1, }
      )
      vim.cmd "redraw"
      coroutine.yield()
    end
  end)

  local function continue_processing()
    coroutine.resume(process)
    if coroutine.status(process) == "suspended" then
      vim.schedule(continue_processing)
    end
  end
  vim.schedule(continue_processing)
end

-- M.tree {
--   keymaps = {
--     ["<cr>"] = "select-close-tree",
--     ["o"] = "select-focus-win",
--     ["t"] = "select-focus-tree",
--     ["q"] = "close-tree",
--   },
-- }

return M
