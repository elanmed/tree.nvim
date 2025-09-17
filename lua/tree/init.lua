local M = {}

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

--- @class TreeOpts
--- @field icons_enabled boolean
--- @field keymaps TreeKeymaps
--- @field win_type "popup"|"split"

--- @class TreeKeymaps
--- @field [string] "close-tree"|"select-focus-win"|"select-focus-tree"|"select-close-tree"

--- @param opts TreeOpts
M.tree = function(opts)
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

  local obj = vim.system({ "tree", "-J", "-f", "-a", "--gitignore", }, { cwd = cwd, }):wait()
  if not obj.stdout then
    error "[tree.nvim] `tree` command failed to produce a stdout"
  end
  local tree_json = vim.json.decode(obj.stdout)

  local curr_bufnr_line = nil

  --- @class Line
  --- @field formatted string
  --- @field abs_path string
  --- @field icon_char string
  --- @field icon_hl string
  --- @field indent number
  --- @field type "file"|"directory"

  --- @type Line[]
  local lines = {}
  local max_line_width = 0

  local function indent_lines(json, indent)
    local indent_chars = (" "):rep(indent)
    local rel_path = vim.fs.normalize(json.name)
    local abs_path = vim.fs.joinpath(cwd, rel_path)
    local basename = vim.fs.basename(rel_path)


    if json.type == "file" then
      local icon_info = get_icon_info { abs_path = abs_path, icon_type = "file", icons_enabled = opts.icons_enabled }
      local formatted = ("%s%s %s"):format(indent_chars, icon_info.icon_char, basename)

      --- @type Line
      local line = {
        abs_path = abs_path,
        formatted = formatted,
        icon_hl = icon_info.icon_hl,
        icon_char = icon_info.icon_char,
        indent = indent,
        type = "file"
      }
      table.insert(lines, line)
      max_line_width = math.max(max_line_width, #line.formatted)
      if abs_path == bufname_abs_path then
        curr_bufnr_line = #lines
      end
    elseif json.type == "directory" then
      local icon_info = get_icon_info { abs_path = abs_path, icon_type = "directory", icons_enabled = opts.icons_enabled }
      local formatted = ("%s%s %s/"):format(indent_chars, icon_info.icon_char, basename)
      --- @type Line
      local line = {
        abs_path = abs_path,
        formatted = formatted,
        icon_char = icon_info.icon_char,
        icon_hl = icon_info.icon_hl,
        indent = indent,
        type = "directory"
      }
      table.insert(lines, line)
      max_line_width = math.max(max_line_width, #line.formatted)

      if not json.contents then return end
      for _, file_json in ipairs(json.contents) do
        indent_lines(file_json, indent + 2)
      end
    end
  end

  indent_lines(tree_json[1], 1)

  local tree_bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = tree_bufnr, })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = tree_bufnr, })
  vim.api.nvim_set_option_value("buflisted", false, { buf = tree_bufnr, })

  local border_height = 2
  local tree_winnr = (function()
    local width = math.min(vim.o.columns, max_line_width + 2)

    if opts.win_type == "popup" then
      return vim.api.nvim_open_win(tree_bufnr, true, {
        relative = "editor",
        row = 1,
        col = 0,
        width = width,
        height = math.min(vim.o.lines - 1 - border_height, #lines),
        border = "rounded",
        style = "minimal",
        title = "Tree",
      })
    end

    return vim.api.nvim_open_win(tree_bufnr, true, {
      split = "left",
      width = width,
      style = "minimal",
    })
  end)()

  vim.api.nvim_set_option_value("foldmethod", "indent", { win = tree_winnr, })
  vim.api.nvim_set_option_value("cursorline", true, { win = tree_winnr, })

  vim.api.nvim_win_set_buf(tree_winnr, tree_bufnr)
  local formatted_lines = vim.tbl_map(function(line) return line.formatted end, lines)
  vim.api.nvim_buf_set_lines(tree_bufnr, 0, -1, false, formatted_lines)
  if curr_bufnr_line then
    vim.api.nvim_win_set_cursor(tree_winnr, { curr_bufnr_line, 0, })
  end
  vim.cmd "normal! ^h"
  vim.cmd "normal! zz"

  vim.schedule(function()
    for index, line in ipairs(lines) do
      local icon_hl_col_0_indexed = line.indent
      local row_1_indexed = index
      local row_0_indexed = row_1_indexed - 1

      vim.hl.range(
        tree_bufnr,
        ns_id,
        line.icon_hl,
        { row_0_indexed, icon_hl_col_0_indexed },
        { row_0_indexed, icon_hl_col_0_indexed + 1 }
      )
    end
  end)

  local close_win = function()
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
    ["close-tree"] = close_win,
    ["select-close-tree"] = function()
      select()
      close_win()
    end,
    ["select-focus-win"] = select,
    ["select-focus-tree"] = function()
      local line_nr = vim.fn.line "."
      local line = lines[line_nr]
      if line.type ~= "file" then return end

      vim.api.nvim_win_call(curr_winnr, function()
        vim.cmd("edit " .. vim.trim(line.abs_path))
      end)
    end
  }

  for key, map in pairs(opts.keymaps) do
    vim.keymap.set("n", key, function()
      keymap_fns[map]()
    end, { buffer = tree_bufnr, })
  end
end

M.tree({
  keymaps = {
    ["<cr>"] = "select-close-tree",
    ["o"] = "select-focus-win",
    ["t"] = "select-focus-tree",
    ["q"] = "close-tree"
  }
})

return M
