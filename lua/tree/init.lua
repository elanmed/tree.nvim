local M = {}

local vimscript_true = 1
local vimscript_false = 0

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

--- @class Line
--- @field whitespace string
--- @field abs_path string
--- @field formatted string

--- @class TreeKeymaps
--- @field [string] "close-tree"|"select"|"out-dir"|"in-dir"|"inc-limit"|"dec-limit"

--- @class TreeOpts
--- @field tree_dir? string
--- @field limit? number
--- @field tree_bufnr? number
--- @field tree_winnr? number
--- @field keymaps TreeKeymaps
--- @param opts? TreeOpts
M.tree = function(opts)
  opts = default(opts, {})
  opts.limit = default(opts.limit, 1)
  opts.keymaps = default(opts.keymaps, {})

  local curr_winnr = vim.api.nvim_get_current_win()
  local curr_bufnr = vim.api.nvim_get_current_buf()
  local bufname_abs_path = vim.api.nvim_buf_get_name(curr_bufnr)
  local curr_dir = vim.fs.dirname(bufname_abs_path)
  opts.tree_dir = default(opts.tree_dir, curr_dir)

  opts.tree_bufnr = (function()
    if opts.tree_bufnr then
      return opts.tree_bufnr
    end

    local tree_bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_option_value("buftype", "nofile", { buf = tree_bufnr, })
    vim.api.nvim_set_option_value("buflisted", false, { buf = tree_bufnr, })

    return tree_bufnr
  end)()

  local obj = vim.system(
    { "tree", "-f", "-a", "--noreport", "--charset=ascii", "-L", tostring(opts.limit), },
    { cwd = opts.tree_dir, }
  ):wait()

  if not obj.stdout then
    error "[tree.nvim] no stdout from `tree`"
  end

  --- @type Line[]
  local lines = {}
  --- @type string[]
  local formatted_lines = {}
  local max_line_width = 0

  for _, str in ipairs(vim.split(obj.stdout, "\n")) do
    local period_pos = str:find "%."
    if not period_pos then
      goto continue
    end

    local prefix_length = period_pos - 1
    local whitespace = string.rep(" ", prefix_length / 2)
    local filename = str:sub(period_pos)

    local rel_path = vim.fs.normalize(filename)
    local abs_path = vim.fs.joinpath(opts.tree_dir, rel_path)
    local basename = vim.fs.basename(abs_path)
    local formatted = whitespace .. basename
    max_line_width = math.max(max_line_width, #formatted)

    --- @type Line
    local line = {
      abs_path = abs_path,
      whitespace = whitespace,
      formatted = formatted,
    }
    table.insert(lines, line)
    table.insert(formatted_lines, formatted)

    ::continue::
  end

  vim.api.nvim_buf_set_lines(opts.tree_bufnr, 0, -1, false, formatted_lines)

  local width_padding = 1

  opts.tree_winnr = (function()
    local title = ("tree %s/ -L %s"):format(vim.fs.basename(opts.tree_dir), opts.limit)
    local width = math.max(#title, max_line_width + width_padding)
    if opts.tree_winnr then
      vim.api.nvim_win_set_width(opts.tree_winnr, width)
      vim.api.nvim_win_set_height(opts.tree_winnr, #lines)
      vim.api.nvim_win_set_config(opts.tree_winnr, {
        title = title,
      })
      return opts.tree_winnr
    end

    local tree_winnr = vim.api.nvim_open_win(opts.tree_bufnr, true, {
      relative = "editor",
      row = 1,
      col = 0,
      width = width,
      height = #lines,
      border = "rounded",
      style = "minimal",
      title = title,
    })
    vim.api.nvim_set_option_value("foldmethod", "indent", { win = tree_winnr, })
    vim.api.nvim_set_option_value("cursorline", true, { win = tree_winnr, })
    return tree_winnr
  end)()
  vim.api.nvim_win_set_buf(opts.tree_winnr, opts.tree_bufnr)

  local function inc_limit()
    M.tree {
      limit = opts.limit + 1,
      tree_bufnr = opts.tree_bufnr,
      tree_dir = opts.tree_dir,
      tree_winnr = opts.tree_winnr,
      keymaps = opts.keymaps,
    }
  end

  local function dec_limit()
    if opts.limit == 1 then
      vim.notify "[tree.nvim] limit must be greater than 0"
      return
    end
    M.tree {
      limit = opts.limit - 1,
      tree_bufnr = opts.tree_bufnr,
      tree_dir = opts.tree_dir,
      tree_winnr = opts.tree_winnr,
      keymaps = opts.keymaps,
    }
  end

  local function out_dir()
    M.tree {
      limit = opts.limit + 1,
      tree_bufnr = opts.tree_bufnr,
      tree_dir = vim.fs.dirname(opts.tree_dir),
      tree_winnr = opts.tree_winnr,
      keymaps = opts.keymaps,
    }
  end

  local function in_dir()
    local line_nr = vim.fn.line "."
    local line = lines[line_nr]

    local in_tree_dir = (function()
      if vim.fn.isdirectory(line.abs_path) == vimscript_true then
        return line.abs_path
      elseif vim.fn.filereadable(line.abs_path) == vimscript_true then
        return vim.fs.dirname(line.abs_path)
      end
    end)()

    M.tree {
      limit = opts.limit,
      tree_bufnr = opts.tree_bufnr,
      tree_dir = in_tree_dir,
      tree_winnr = opts.tree_winnr,
      keymaps = opts.keymaps,
    }
  end

  local close_tree = function()
    vim.api.nvim_win_close(opts.tree_winnr, true)
  end

  local select = function()
    local line_nr = vim.fn.line "."
    local line = lines[line_nr]

    if vim.fn.filereadable(line.abs_path) == vimscript_false then
      vim.notify "[tree.nvim] selected is a directory"
      return
    end

    vim.api.nvim_set_current_win(curr_winnr)
    vim.cmd("edit " .. line.abs_path)
    close_tree()
  end

  local keymap_fns = {
    ["close-tree"] = close_tree,
    ["select"] = select,
    ["inc-limit"] = inc_limit,
    ["dec-limit"] = dec_limit,
    ["out-dir"] = out_dir,
    ["in-dir"] = in_dir,
  }

  for key, map in pairs(opts.keymaps) do
    vim.keymap.set("n", key, function()
      keymap_fns[map]()
    end, { buffer = opts.tree_bufnr, })
  end
end

-- vim.keymap.set("n", "<leader>g", function()
--   M.tree {
--     keymaps = {
--       ["<cr>"] = "select",
--       ["q"] = "close-tree",
--       ["<esc>"] = "close-tree",
--       ["<"] = "dec-limit",
--       [">"] = "inc-limit",
--       ["H"] = "out-dir",
--       ["L"] = "in-dir",
--     },
--   }
-- end)
return M
