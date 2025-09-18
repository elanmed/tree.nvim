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

--- @class IndentedLine
--- @field abs_path string
--- @field indent number
--- @field type "file"|"directory"

--- @class FormattedLine : IndentedLine
--- @field formatted string
--- @field icon_char string
--- @field icon_hl string

--- @class IndentLinesOpts
--- @field json string
--- @field indent number
--- @field cwd string
--- @param opts IndentLinesOpts
local function indent_lines(opts)
  --- @type IndentedLine[]
  local lines = {}
  local function _indent_lines(json, indent)
    local rel_path = vim.fs.normalize(json.name)
    local abs_path = vim.fs.joinpath(opts.cwd, rel_path)

    if json.type == "file" then
      --- @type IndentedLine
      local line = {
        abs_path = abs_path,
        indent = indent,
        type = "file"
      }
      table.insert(lines, line)
    elseif json.type == "directory" then
      --- @type IndentedLine
      local line = {
        abs_path = abs_path,
        indent = indent,
        type = "directory"
      }
      table.insert(lines, line)

      if not json.contents then return end
      for _, file_json in ipairs(json.contents) do
        _indent_lines(file_json, indent + 1)
      end
    end
  end

  _indent_lines(opts.json, 0)
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
    local indent_chars = ("  "):rep(indented_line.indent)
    local icon_info = get_icon_info { abs_path = indented_line.abs_path, icon_type = indented_line.type, icons_enabled = opts.icons_enabled }
    local formatted = ("%s%s %s"):format(indent_chars, icon_info.icon_char, basename)

    --- @type FormattedLine
    local formatted_line = {
      abs_path = indented_line.abs_path,
      indent = indented_line.indent,
      type = indented_line.type,
      formatted = formatted,
      icon_char = icon_info.icon_char,
      icon_hl = icon_info.icon_hl
    }
    table.insert(formatted_lines, formatted_line)
  end

  return formatted_lines
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

  local tree_bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = tree_bufnr, })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = tree_bufnr, })
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

  vim.api.nvim_set_option_value("foldmethod", "indent", { win = tree_winnr, })
  vim.api.nvim_set_option_value("cursorline", true, { win = tree_winnr, })

  vim.api.nvim_win_set_buf(tree_winnr, tree_bufnr)
  vim.api.nvim_buf_set_lines(tree_bufnr, 0, -1, false, { "Loading..." })

  vim.system({ "tree", "-J", "-f", "-a", "--gitignore", }, { cwd = cwd, }, function(obj)
    if not obj.stdout then
      error "[tree.nvim] `tree` command failed to produce a stdout"
    end

    vim.schedule(function()
      local tree_json = vim.json.decode(obj.stdout)
      local indented_lines = indent_lines({ cwd = cwd, indent = 0, json = tree_json[1] })
      local lines = format_lines({ icons_enabled = opts.icons_enabled, lines = indented_lines })
      local max_line_width = get_max_line_width(lines)
      vim.api.nvim_win_set_width(tree_winnr, math.min(vim.o.columns, max_line_width))

      vim.api.nvim_buf_set_lines(tree_bufnr, 0, -1, false, vim.tbl_map(function(line) return line.formatted end, lines))

      local curr_bufnr_line = get_curr_buf_line(lines, bufname_abs_path)
      if curr_bufnr_line then
        vim.api.nvim_win_set_cursor(tree_winnr, { curr_bufnr_line, 0, })
        vim.api.nvim_buf_set_mark(0, "a", curr_bufnr_line, 0, {})
      end
      vim.cmd "normal! ^h"
      vim.cmd "normal! zz"

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
        end
      }

      for key, map in pairs(opts.keymaps) do
        vim.keymap.set("n", key, function()
          keymap_fns[map]()
        end, { buffer = tree_bufnr, })
      end
    end)
  end)
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
