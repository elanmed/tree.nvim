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

--- @param opts TreeOpts
M.tree = function(opts)
  opts = default(opts, {})
  opts.icons_enabled = default(opts.icons_enabled, true)

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

  --- @type Line[]
  local lines = {}
  local max_line_width = 0

  local function indent_lines(json, indent)
    local indent_chars = (" "):rep(indent)
    local rel_path = vim.fs.normalize(json.name)
    local abs_path = vim.fs.joinpath(cwd, rel_path)

    local icon_info = get_icon_info { abs_path = abs_path, icon_type = json.type, icons_enabled = opts.icons_enabled }

    if json.type == "file" then
      local formatted = ("%s%s %s"):format(indent_chars, icon_info.icon_char, rel_path)

      --- @type Line
      local line = {
        abs_path = abs_path,
        formatted = formatted,
        icon_hl = icon_info.icon_hl,
        icon_char = icon_info.icon_char,
        indent = indent
      }
      table.insert(lines, line)
      max_line_width = math.max(max_line_width, #line.formatted)
      if abs_path == bufname_abs_path then
        curr_bufnr_line = #lines
      end
    elseif json.type == "directory" then
      local formatted = ("%s%s %s/"):format(indent_chars, icon_info.icon_char, vim.fs.basename(rel_path))
      --- @type Line
      local line = {
        abs_path = abs_path,
        formatted = formatted,
        icon_char = icon_info.icon_char,
        icon_hl = icon_info.icon_hl,
        indent = indent
      }
      table.insert(lines, line)
      max_line_width = math.max(max_line_width, #line.formatted)

      if not json.contents then return end
      for _, file_json in ipairs(json.contents) do
        indent_lines(file_json, indent + 2)
      end
    end
  end

  indent_lines(tree_json[1], 0)

  local results_bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = results_bufnr, })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = results_bufnr, })
  vim.api.nvim_set_option_value("buflisted", false, { buf = results_bufnr, })

  local border_height = 2
  local winnr = vim.api.nvim_open_win(results_bufnr, true, {
    relative = "editor",
    row = 1,
    col = 0,
    width = math.min(vim.o.columns, max_line_width + 2),
    height = math.min(vim.o.lines - 1 - border_height, #lines),
    border = "rounded",
    style = "minimal",
    title = "Tree",
  })
  vim.api.nvim_set_option_value("foldmethod", "indent", { win = winnr, })

  vim.api.nvim_win_set_buf(winnr, results_bufnr)
  local formatted_lines = vim.tbl_map(function(line) return line.formatted end, lines)
  vim.api.nvim_buf_set_lines(results_bufnr, 0, -1, false, formatted_lines)
  if curr_bufnr_line then
    vim.api.nvim_win_set_cursor(winnr, { curr_bufnr_line, 0, })
  end
  vim.cmd "normal! ^"

  vim.schedule(function()
    for index, line in ipairs(lines) do
      local icon_hl_col_0_indexed = line.indent
      local row_1_indexed = index
      local row_0_indexed = row_1_indexed - 1

      vim.hl.range(
        results_bufnr,
        ns_id,
        line.icon_hl,
        { row_0_indexed, icon_hl_col_0_indexed },
        { row_0_indexed, icon_hl_col_0_indexed + 1 }
      )
    end
  end)


  vim.keymap.set("n", "<cr>", function()
    local line_nr = vim.fn.line "."
    local line = lines[line_nr]
    vim.api.nvim_win_close(winnr, true)
    vim.cmd("edit " .. vim.trim(line.abs_path))
  end, { buffer = results_bufnr, })
end

-- M.tree({ icons_enabled = true })

return M
