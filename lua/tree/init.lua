local M = {}

local ns_id = vim.api.nvim_create_namespace "Tree"

local TREE_INSTANCE = nil

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

--- @class IndentLinesOpts
--- @field chunk string[]
--- @field cwd string
--- @param opts IndentLinesOpts
local function indent_lines(opts)
  --- @type IndentedLine[]
  local lines = {}
  for _, str in ipairs(opts.chunk) do
    local period_pos = str:find "%."
    if not period_pos then goto continue end

    local prefix_length = period_pos - 1
    local whitespace = string.rep(" ", prefix_length / 2)
    local filename = str:sub(period_pos)

    local rel_path = vim.fs.normalize(filename)
    local abs_path = vim.fs.joinpath(opts.cwd, rel_path)

    local type = (function()
      local stat_res = vim.uv.fs_stat(abs_path)
      if not stat_res then
        return "file"
      end
      return stat_res.type
    end)()

    --- @type IndentedLine
    local line = {
      whitespace = whitespace,
      abs_path = abs_path,
      type = type,
    }
    table.insert(lines, line)

    ::continue::
  end
  return lines
end

--- @param lines FormattedLine[]
local function get_max_line_width(lines)
  local max_line_width = 0
  for _, line in ipairs(lines) do
    max_line_width = math.max(max_line_width, #line.formatted)
  end
  return max_line_width
end

--- @param lines FormattedLine[]
local function get_curr_buf_line(lines, curr_buf_abs_path)
  for idx, line in ipairs(lines) do
    if line.abs_path == curr_buf_abs_path then return idx end
  end
  return nil
end

--- @class FormatLinesOpts
--- @field lines IndentedLine[]
--- @field icons_enabled boolean
--- @param opts FormatLinesOpts
local function format_lines(opts)
  local formatted_lines = {}
  for _, indented_line in ipairs(opts.lines) do
    local basename = vim.fs.basename(indented_line.abs_path)
    local icon_info = get_icon_info { abs_path = indented_line.abs_path, icon_type = indented_line.type, icons_enabled = opts.icons_enabled, }
    local formatted = ("%s%s %s"):format(indented_line.whitespace, icon_info.icon_char, basename)

    --- @type FormattedLine
    local formatted_line = {
      abs_path = indented_line.abs_path,
      whitespace = indented_line.whitespace,
      type = indented_line.type,
      formatted = formatted,
      icon_char = icon_info.icon_char,
      icon_hl = icon_info.icon_hl,
    }
    table.insert(formatted_lines, formatted_line)
  end

  return formatted_lines
end

--- @param mark_name string
local function is_buffer_mark_unset(mark_name)
  local mark = vim.api.nvim_buf_get_mark(0, mark_name)
  return mark[1] == 0 and mark[2] == 0
end

--- @class TreeOpts
--- @field icons_enabled boolean
--- @field keymaps TreeKeymaps
--- @field win_type "popup"|"split"

--- @class TreeKeymaps
--- @field [string] "close-tree"|"select-focus-win"|"select-focus-tree"|"select-close-tree"

--- @param opts TreeOpts
M.tree = function(opts)
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
    local default_width = 50

    if opts.win_type == "popup" then
      return vim.api.nvim_open_win(tree_bufnr, true, {
        relative = "editor",
        row = 1,
        col = 0,
        width = default_width,
        height = vim.o.lines - 1 - border_height,
        border = "rounded",
        style = "minimal",
        title = "Tree",
      })
    end

    return vim.api.nvim_open_win(tree_bufnr, true, {
      split = "left",
      width = default_width,
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
  vim.api.nvim_buf_set_lines(tree_bufnr, 0, -1, false, { "Loading...", })

  --- @type FormattedLine[]
  local lines = {}

  vim.system({ "tree", "-f", "-a", "--gitignore", "--noreport", "--charset=ascii", }, {
    cwd = cwd,
    stdout = function(err, data)
      if err then return end
      if not data then return end
      local chunk = vim.split(data, "\n")
      local indented_lines = indent_lines { chunk = chunk, cwd = cwd, }
      vim.schedule(function()
        local formatted_lines = format_lines { icons_enabled = opts.icons_enabled, lines = indented_lines, }
        vim.api.nvim_buf_set_lines(tree_bufnr, #lines, -1, false,
          vim.tbl_map(function(line) return line.formatted end, formatted_lines))

        for index, line in ipairs(formatted_lines) do
          local icon_hl_col_0_indexed = #line.whitespace
          local row_1_indexed = #lines + index
          local row_0_indexed = row_1_indexed - 1

          vim.hl.range(
            tree_bufnr,
            ns_id,
            line.icon_hl,
            { row_0_indexed, icon_hl_col_0_indexed, },
            { row_0_indexed, icon_hl_col_0_indexed + 1, }
          )
        end

        lines = vim.list_extend(lines, formatted_lines)
      end)
    end,
  }, function()
    vim.schedule(function()
      vim.api.nvim_set_option_value("modifiable", false, { buf = tree_bufnr, })

      local max_line_width = get_max_line_width(lines)
      vim.api.nvim_win_set_width(tree_winnr, math.min(vim.o.columns, max_line_width))

      local curr_bufnr_line = get_curr_buf_line(lines, bufname_abs_path)
      if curr_bufnr_line then
        vim.api.nvim_win_set_cursor(tree_winnr, { curr_bufnr_line, 0, })
        vim.api.nvim_buf_set_mark(0, "a", curr_bufnr_line, 0, {})
      end
      vim.cmd "normal! zz"

      local close_tree = function()
        vim.api.nvim_win_close(tree_winnr, true)
      end

      local select = function()
        local line_nr = vim.fn.line "."
        local line = lines[line_nr]
        if line.type ~= "file" then return end

        vim.api.nvim_set_current_win(curr_winnr)
        vim.cmd("edit " .. vim.trim(line.abs_path))
      end

      local keymap_fns = {
        ["close-tree"] = close_tree,
        ["select-close-tree"] = function()
          select()
          close_tree()
        end,
        ["select-focus-win"] = select,
        ["select-focus-tree"] = function()
          local line_nr = vim.fn.line "."
          local line = lines[line_nr]
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
    end)
  end)
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
