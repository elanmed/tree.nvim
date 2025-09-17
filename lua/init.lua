local M = {}

M.tree = function()
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

  --- @type Line[]
  local lines = {}
  local max_line_width = 0

  local function indent_lines(json, indent)
    local indent_chars = ("  "):rep(indent)
    local abs_path = vim.fs.normalize(json.name)
    local rel_path = vim.fs.relpath(cwd, abs_path)

    if json.type == "file" then
      --- @type Line
      local line = {
        abs_path = abs_path,
        formatted = indent_chars .. rel_path,
        icon_hl = "",
        icon_char = ""
      }
      table.insert(lines, line)
      max_line_width = math.max(max_line_width, #line.formatted)
      if abs_path == bufname_abs_path then
        curr_bufnr_line = #lines
      end
    elseif json.type == "directory" then
      --- @type Line
      local line = {
        abs_path = abs_path,
        formatted = indent_chars .. vim.fs.basename(rel_path) .. "/",
        icon_hl = "",
        icon_char = ""
      }
      table.insert(lines, line)
      max_line_width = math.max(max_line_width, #line.formatted)

      if not json.contents then return end
      for _, file_json in ipairs(json.contents) do
        indent_lines(file_json, indent + 1)
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

  vim.keymap.set("n", "<cr>", function()
    local line = vim.api.nvim_get_current_line()
    vim.api.nvim_win_close(winnr, true)
    vim.cmd("edit " .. vim.trim(line))
  end, { buffer = results_bufnr, })
end

-- M.tree()

return M
