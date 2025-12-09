require "mini.test".setup()

local expect = MiniTest.expect
local eq = MiniTest.expect.equality
local child = MiniTest.new_child_neovim()

local expect_fs_exists = MiniTest.new_expectation(
  "file system path exists",
  function(path, should_exist)
    local exists = vim.uv.fs_stat(path) ~= nil
    if should_exist == nil then should_exist = true end
    return exists == should_exist
  end,
  function(path, should_exist)
    if should_exist == nil then should_exist = true end
    if should_exist then
      return string.format("Expected path to exist, does not: %s", path)
    else
      return string.format("Expected path not to exist, does: %s", path)
    end
  end
)

local expect_lines = MiniTest.new_expectation(
  "buffer lines equality",
  function(expected_lines)
    local actual_lines = child.api.nvim_buf_get_lines(child.api.nvim_get_current_buf(), 0, -1, false)
    return vim.deep_equal(actual_lines, expected_lines)
  end,
  function(expected_lines)
    local actual_lines = child.api.nvim_buf_get_lines(child.api.nvim_get_current_buf(), 0, -1, false)
    return string.format("Expected lines:\n%s\nActual lines:\n%s",
      vim.inspect(expected_lines),
      vim.inspect(actual_lines))
  end
)

local expect_message = MiniTest.new_expectation(
  "notification message",
  function(expected_msg)
    local messages = child.cmd_capture "messages"
    return eq(messages, expected_msg)
  end,
  function(expected_msg)
    local messages = child.cmd_capture "messages"
    return string.format("Expected message: %s\nActual messages: %s", expected_msg, messages)
  end
)

local expect_cursor_line = MiniTest.new_expectation(
  "cursor line number and text",
  function(expected_line, expected_text)
    local actual_line = child.fn.line "."
    local actual_text = child.fn.getline "."
    return actual_line == expected_line and actual_text == expected_text
  end,
  function(expected_line, expected_text)
    local actual_line = child.fn.line "."
    local actual_text = child.fn.getline "."
    return string.format(
      "Expected cursor at line %d with text '%s', actual line %d with text '%s'",
      expected_line,
      expected_text,
      actual_line,
      actual_text
    )
  end
)

local validate_confirm_args = function(ref_msg_pattern)
  local args = child.lua_get "_G.confirm_args"
  eq(args[1], ref_msg_pattern)
  if args[2] ~= nil then eq(args[2], "&Yes\n&No") end
  if args[3] ~= nil then eq(args[3], 2) end
end

local mock_confirm = function(user_choice)
  local lua_cmd = string.format(
    [[vim.fn.confirm = function(...)
        _G.confirm_args = { ... }
        return %d
      end]],
    user_choice
  )
  child.lua(lua_cmd)
end

local T = MiniTest.new_set {
  hooks = {
    pre_case = function()
      child.restart { "-u", "scripts/minimal_init.lua", }
      child.bo.readonly = false
      child.lua [[M = require('tree')]]
      child.o.lines = 20
      child.o.columns = 30
      child.lua [[
        M.tree {
          tree_dir = "./test_dir",
        }
        vim.keymap.set("n", "<cr>", "<Plug>TreeSelect", { buffer = true })
        vim.keymap.set("n", "q", "<Plug>TreeCloseTree", { buffer = true })
        vim.keymap.set("n", "h", "<Plug>TreeOutDir", { buffer = true })
        vim.keymap.set("n", "l", "<Plug>TreeInDir", { buffer = true })
        vim.keymap.set("n", "yr", "<Plug>TreeYankRelativePath", { buffer = true })
        vim.keymap.set("n", "ya", "<Plug>TreeYankAbsolutePath", { buffer = true })
        vim.keymap.set("n", "yd", "<Plug>TreeYankDirectory", { buffer = true })
        vim.keymap.set("n", "yb", "<Plug>TreeYankBasename", { buffer = true })
        vim.keymap.set("n", "o", "<Plug>TreeCreate", { buffer = true })
        vim.keymap.set("n", "e", "<Plug>TreeRefresh", { buffer = true })
        vim.keymap.set("n", "r", "<Plug>TreeRename", { buffer = true })
        vim.keymap.set("n", "dd", "<Plug>TreeDelete", { buffer = true })
        vim.keymap.set("n", "yy", "<Plug>TreeCopy", { buffer = true })
        vim.keymap.set("n", "m", "<Plug>TreeMove", { buffer = true })

        vim.keymap.set("v", "d", "<Plug>TreeDelete", { buffer = true })
        vim.keymap.set("v", "yy", "<Plug>TreeCopy", { buffer = true })
        vim.keymap.set("v", "m", "<Plug>TreeMove", { buffer = true })
      ]]
    end,
    post_case = function()
      child.fn.delete("test_dir", "rf")

      child.fn.mkdir "test_dir"
      child.fn.mkdir "test_dir/dir_a"
      child.fn.writefile({}, "test_dir/dir_a/init.lua")
      child.fn.writefile({}, "test_dir/dir_a/mod.ts")
      child.fn.mkdir "test_dir/dir_a/dir_c"
      child.fn.writefile({ "<div>content</div>", }, "test_dir/dir_a/dir_c/index.html")
      child.fn.writefile({}, "test_dir/dir_a/dir_c/index.js")
      child.fn.mkdir "test_dir/dir_b"
      child.fn.writefile({}, "test_dir/dir_b/Makefile")
      child.fn.writefile({}, "test_dir/dir_b/.env")
    end,
    post_once = child.stop,
  },
}

T["tree"] = MiniTest.new_set()

T["tree"]["plug remaps"] = MiniTest.new_set()
T["tree"]["plug remaps"]["TreeInDir"] = function()
  expect_lines {
    " 󰉋 dir_a",
    " 󰉋 dir_b",
  }
  child.type_keys "l"
  expect_lines {
    " 󰉋 dir_c",
    "  init.lua",
    " 󰛦 mod.ts",
  }
  child.type_keys "l"
  expect_lines {
    " 󰌝 index.html",
    " 󰌞 index.js",
  }
end
T["tree"]["plug remaps"]["TreeOutDir"] = function()
  child.type_keys { "l", "l", }
  expect_lines {
    " 󰌝 index.html",
    " 󰌞 index.js",
  }
  child.type_keys "h"
  expect_lines {
    " 󰉋 dir_c",
    "  init.lua",
    " 󰛦 mod.ts",
  }
  child.type_keys "h"
  expect_lines {
    " 󰉋 dir_a",
    " 󰉋 dir_b",
  }
end
T["tree"]["plug remaps"]["TreeSelect"] = function()
  child.type_keys { "l", "l", }
  expect_lines {
    " 󰌝 index.html",
    " 󰌞 index.js",
  }
  child.type_keys "<cr>"
  expect_lines {
    "<div>content</div>",
  }
  child.lua [[M.tree()]]
  expect_lines {
    " 󰌝 index.html",
    " 󰌞 index.js",
  }
end
T["tree"]["plug remaps"]["TreeCloseTree"] = function()
  expect_lines {
    " 󰉋 dir_a",
    " 󰉋 dir_b",
  }
  child.type_keys "q"
  expect_lines { "", }
end
T["tree"]["plug remaps"]["TreeYankRelativePath"] = function()
  child.type_keys { "y", "r", }
  eq(child.fn.getreg "r", "test_dir/dir_a")

  child.type_keys "j"
  child.type_keys { "y", "r", }
  eq(child.fn.getreg "r", "test_dir/dir_b")
end
T["tree"]["plug remaps"]["TreeYankAbsolutePath"] = function()
  child.type_keys { "y", "a", }
  eq(child.fn.getreg "a", vim.fs.abspath "test_dir/dir_a")

  child.type_keys "j"
  child.type_keys { "y", "a", }
  eq(child.fn.getreg "a", vim.fs.abspath "test_dir/dir_b")
end
T["tree"]["plug remaps"]["TreeYankAbsolute"] = function()
  child.type_keys { "y", "d", }
  eq(child.fn.getreg "d", vim.fs.abspath "test_dir")

  child.type_keys "j"
  child.type_keys { "y", "d", }
  eq(child.fn.getreg "d", vim.fs.abspath "test_dir")
end
T["tree"]["plug remaps"]["TreeYankBasename"] = function()
  child.type_keys { "l", }

  child.type_keys { "y", "b", }
  eq(child.fn.getreg "b", "dir_c")

  child.type_keys "j"
  child.type_keys { "y", "b", }
  eq(child.fn.getreg "b", "init")

  child.type_keys "j"
  child.type_keys { "y", "b", }
  eq(child.fn.getreg "b", "mod")
end

T["tree"]["plug remaps"]["TreeCreate"] = MiniTest.new_set()
T["tree"]["plug remaps"]["TreeCreate"]["file"] = function()
  child.type_keys "o"
  eq(child.fn.getcmdline(), "test_dir/")
  child.type_keys "new_file.txt"
  mock_confirm(1)
  child.type_keys "<CR>"
  expect_fs_exists(vim.fs.abspath "test_dir/new_file.txt")
  validate_confirm_args("Create? " .. vim.fs.abspath "test_dir/new_file.txt")
end
T["tree"]["plug remaps"]["TreeCreate"]["directory"] = function()
  child.type_keys "o"
  eq(child.fn.getcmdline(), "test_dir/")
  child.type_keys "new_dir/"
  mock_confirm(1)
  child.type_keys "<CR>"
  expect_fs_exists(vim.fs.abspath "test_dir/new_dir")
  validate_confirm_args("Create? " .. vim.fs.abspath "test_dir/new_dir")
end
T["tree"]["plug remaps"]["TreeCreate"]["children path"] = function()
  child.type_keys "o"
  eq(child.fn.getcmdline(), "test_dir/")
  child.type_keys "new_nested/path/file.lua"
  mock_confirm(1)
  child.type_keys "<CR>"
  expect_fs_exists(vim.fs.abspath "test_dir/new_nested/path/file.lua")
  validate_confirm_args("Create? " .. vim.fs.abspath "test_dir/new_nested/path/file.lua")
end
T["tree"]["plug remaps"]["TreeCreate"]["parent path"] = function()
  child.type_keys "l"
  child.type_keys "o"
  eq(child.fn.getcmdline(), "test_dir/dir_a/")
  child.type_keys "../"
  child.type_keys "new_file.txt"
  mock_confirm(1)
  child.type_keys "<CR>"
  expect_fs_exists(vim.fs.abspath "test_dir/new_file.txt")
  validate_confirm_args("Create? " .. vim.fs.abspath "test_dir/new_file.txt")
end

T["tree"]["plug remaps"]["TreeRename"] = MiniTest.new_set()
T["tree"]["plug remaps"]["TreeRename"]["file"] = function()
  child.type_keys { "l", "j", }
  child.type_keys "r"
  local original_path = child.fn.getcmdline()
  eq(original_path, "test_dir/dir_a/init.lua")
  child.type_keys { "<C-u>", "test_dir/dir_a/renamed.lua", }
  mock_confirm(1)
  child.type_keys "<CR>"
  expect_fs_exists(vim.fs.abspath "test_dir/dir_a/renamed.lua", true)
  expect_fs_exists(vim.fs.abspath "test_dir/dir_a/init.lua", false)
end
T["tree"]["plug remaps"]["TreeRename"]["directory"] = function()
  child.type_keys "r"
  local original_path = child.fn.getcmdline()
  eq(original_path, "test_dir/dir_a")
  child.type_keys { "<C-u>", "test_dir/renamed_dir", }
  mock_confirm(1)
  child.type_keys "<CR>"
  expect_fs_exists(vim.fs.abspath "test_dir/renamed_dir", true)
  expect_fs_exists(vim.fs.abspath "test_dir/dir_a", false)
end
T["tree"]["plug remaps"]["TreeRename"]["to parent path"] = function()
  child.type_keys { "l", "j", }
  child.type_keys "r"
  eq(child.fn.getcmdline(), "test_dir/dir_a/init.lua")
  child.type_keys { "<C-u>", "test_dir/renamed.lua", }
  mock_confirm(1)
  child.type_keys "<CR>"
  expect_fs_exists(vim.fs.abspath "test_dir/renamed.lua", true)
  expect_fs_exists(vim.fs.abspath "test_dir/dir_a/init.lua", false)
end
T["tree"]["plug remaps"]["TreeRename"]["to child path"] = function()
  child.type_keys "r"
  eq(child.fn.getcmdline(), "test_dir/dir_a")
  child.type_keys { "<C-u>", "test_dir/dir_b/renamed_dir", }
  mock_confirm(1)
  child.type_keys "<CR>"
  expect_fs_exists(vim.fs.abspath "test_dir/dir_b/renamed_dir", true)
  expect_fs_exists(vim.fs.abspath "test_dir/dir_a", false)
end
T["tree"]["plug remaps"]["TreeRename"]["abort empty"] = function()
  child.type_keys "r"
  eq(child.fn.getcmdline(), "test_dir/dir_a")
  child.type_keys "<C-u>"
  child.type_keys "<CR>"
  expect_fs_exists(vim.fs.abspath "test_dir/dir_a", true)
end
T["tree"]["plug remaps"]["TreeRename"]["abort confirmation"] = function()
  child.type_keys "r"
  eq(child.fn.getcmdline(), "test_dir/dir_a")
  child.type_keys { "<C-u>", "test_dir/renamed_dir", }
  mock_confirm(2)
  child.type_keys "<CR>"
  expect_fs_exists(vim.fs.abspath "test_dir/dir_a", true)
  expect_fs_exists(vim.fs.abspath "test_dir/renamed_dir", false)
end
T["tree"]["plug remaps"]["TreeRename"]["destination exists"] = function()
  child.type_keys "r"
  eq(child.fn.getcmdline(), "test_dir/dir_a")
  child.type_keys { "<C-u>", "test_dir/dir_b", }
  mock_confirm(1)
  expect.error(function() child.type_keys "<CR>" end)
  expect_message("[tree.nvim]: Rename path already exists: " .. vim.fs.abspath "test_dir/dir_b")
  expect_fs_exists(vim.fs.abspath "test_dir/dir_a", true)
  expect_fs_exists(vim.fs.abspath "test_dir/dir_b", true)
end

T["tree"]["plug remaps"]["TreeDelete"] = MiniTest.new_set()
T["tree"]["plug remaps"]["TreeDelete"]["single file"] = function()
  child.type_keys { "l", "j", }
  expect_fs_exists(vim.fs.abspath "test_dir/dir_a/init.lua")
  mock_confirm(1)
  child.type_keys "dd"
  expect_fs_exists(vim.fs.abspath "test_dir/dir_a/init.lua", false)
  validate_confirm_args("Delete?\n" .. vim.fs.abspath "test_dir/dir_a/init.lua")
end
T["tree"]["plug remaps"]["TreeDelete"]["directory"] = function()
  expect_fs_exists(vim.fs.abspath "test_dir/dir_a")
  mock_confirm(1)
  child.type_keys "dd"
  expect_fs_exists(vim.fs.abspath "test_dir/dir_a", false)
  validate_confirm_args("Delete?\n" .. vim.fs.abspath "test_dir/dir_a")
end
T["tree"]["plug remaps"]["TreeDelete"]["abort confirmation"] = function()
  child.type_keys { "l", "j", }
  expect_fs_exists(vim.fs.abspath "test_dir/dir_a/init.lua")
  mock_confirm(2)
  child.type_keys "dd"
  expect_fs_exists(vim.fs.abspath "test_dir/dir_a/init.lua")
end
T["tree"]["plug remaps"]["TreeDelete"]["visual mode"] = function()
  child.type_keys "l"
  expect_fs_exists(vim.fs.abspath "test_dir/dir_a/dir_c")
  expect_fs_exists(vim.fs.abspath "test_dir/dir_a/init.lua")
  child.type_keys "V"
  child.type_keys "j"
  mock_confirm(1)
  child.type_keys "d"
  expect_fs_exists(vim.fs.abspath "test_dir/dir_a/dir_c", false)
  expect_fs_exists(vim.fs.abspath "test_dir/dir_a/init.lua", false)
  validate_confirm_args(
    "Delete?\n" .. vim.fs.abspath "test_dir/dir_a/dir_c" .. "\n" .. vim.fs.abspath "test_dir/dir_a/init.lua"
  )
end

T["tree"]["plug remaps"]["TreeCopy"] = MiniTest.new_set()
T["tree"]["plug remaps"]["TreeCopy"]["single file"] = function()
  child.type_keys { "l", "j", }
  expect_fs_exists(vim.fs.abspath "test_dir/dir_a/init.lua")
  child.type_keys "yy"
  child.type_keys "test_dir/dir_b"
  mock_confirm(1)
  child.type_keys "<CR>"
  expect_fs_exists(vim.fs.abspath "test_dir/dir_a/init.lua")
  expect_fs_exists(vim.fs.abspath "test_dir/dir_b/init.lua")
  validate_confirm_args(
    "Copy\nFiles:\n" .. vim.fs.abspath "test_dir/dir_a/init.lua" .. "\nTo:\n" .. vim.fs.abspath "test_dir/dir_b"
  )
end
T["tree"]["plug remaps"]["TreeCopy"]["directory"] = function()
  expect_fs_exists(vim.fs.abspath "test_dir/dir_a")
  child.type_keys "yy"
  child.type_keys "test_dir/dir_b"
  mock_confirm(1)
  child.type_keys "<CR>"
  expect_fs_exists(vim.fs.abspath "test_dir/dir_a")
  expect_fs_exists(vim.fs.abspath "test_dir/dir_b/dir_a")
  validate_confirm_args(
    "Copy\nFiles:\n" .. vim.fs.abspath "test_dir/dir_a" .. "\nTo:\n" .. vim.fs.abspath "test_dir/dir_b"
  )
end
T["tree"]["plug remaps"]["TreeCopy"]["to parent path"] = function()
  child.type_keys { "l", "j", }
  expect_fs_exists(vim.fs.abspath "test_dir/dir_a/init.lua")
  child.type_keys "yy"
  child.type_keys "test_dir"
  mock_confirm(1)
  child.type_keys "<CR>"
  expect_fs_exists(vim.fs.abspath "test_dir/dir_a/init.lua")
  expect_fs_exists(vim.fs.abspath "test_dir/init.lua")
  validate_confirm_args(
    "Copy\nFiles:\n" .. vim.fs.abspath "test_dir/dir_a/init.lua" .. "\nTo:\n" .. vim.fs.abspath "test_dir"
  )
end
T["tree"]["plug remaps"]["TreeCopy"]["abort empty"] = function()
  child.type_keys { "l", "j", }
  expect_fs_exists(vim.fs.abspath "test_dir/dir_a/init.lua")
  child.type_keys "yy"
  child.type_keys "<CR>"
  expect_fs_exists(vim.fs.abspath "test_dir/dir_a/init.lua")
end
T["tree"]["plug remaps"]["TreeCopy"]["abort confirmation"] = function()
  child.type_keys { "l", "j", }
  expect_fs_exists(vim.fs.abspath "test_dir/dir_a/init.lua")
  child.type_keys "yy"
  child.type_keys "test_dir/dir_b"
  mock_confirm(2)
  child.type_keys "<CR>"
  expect_fs_exists(vim.fs.abspath "test_dir/dir_a/init.lua")
  expect_fs_exists(vim.fs.abspath "test_dir/dir_b/init.lua", false)
end
T["tree"]["plug remaps"]["TreeCopy"]["visual mode"] = function()
  child.type_keys "l"
  expect_fs_exists(vim.fs.abspath "test_dir/dir_a/dir_c")
  expect_fs_exists(vim.fs.abspath "test_dir/dir_a/init.lua")
  child.type_keys "V"
  child.type_keys "j"
  child.type_keys "yy"
  child.type_keys "test_dir/dir_b"
  mock_confirm(1)
  child.type_keys "<CR>"
  expect_fs_exists(vim.fs.abspath "test_dir/dir_a/dir_c")
  expect_fs_exists(vim.fs.abspath "test_dir/dir_a/init.lua")
  expect_fs_exists(vim.fs.abspath "test_dir/dir_b/dir_c")
  expect_fs_exists(vim.fs.abspath "test_dir/dir_b/init.lua")
  validate_confirm_args(
    "Copy\nFiles:\n"
    .. vim.fs.abspath "test_dir/dir_a/dir_c"
    .. "\n"
    .. vim.fs.abspath "test_dir/dir_a/init.lua"
    .. "\nTo:\n"
    .. vim.fs.abspath "test_dir/dir_b"
  )
end
T["tree"]["plug remaps"]["TreeCopy"]["destination exists"] = function()
  child.type_keys { "l", "j", }
  expect_fs_exists(vim.fs.abspath "test_dir/dir_a/init.lua")
  child.fn.writefile({}, "test_dir/dir_b/init.lua")
  child.type_keys "yy"
  child.type_keys "test_dir/dir_b"
  mock_confirm(1)
  expect.error(function() child.type_keys "<CR>" end)
  expect_message(
    "[tree.nvim]: A file init.lua already exists at path " .. vim.fs.abspath "test_dir/dir_b" .. ", skipping"
  )
end

T["tree"]["plug remaps"]["TreeMove"] = MiniTest.new_set()
T["tree"]["plug remaps"]["TreeMove"]["single file"] = function()
  child.type_keys { "l", "j", }
  expect_fs_exists(vim.fs.abspath "test_dir/dir_a/init.lua")
  child.type_keys "m"
  child.type_keys "test_dir/dir_b"
  mock_confirm(1)
  child.type_keys "<CR>"
  expect_fs_exists(vim.fs.abspath "test_dir/dir_a/init.lua", false)
  expect_fs_exists(vim.fs.abspath "test_dir/dir_b/init.lua")
  validate_confirm_args(
    "Move\nFiles:\n" .. vim.fs.abspath "test_dir/dir_a/init.lua" .. "\nTo:\n" .. vim.fs.abspath "test_dir/dir_b"
  )
end
T["tree"]["plug remaps"]["TreeMove"]["directory"] = function()
  expect_fs_exists(vim.fs.abspath "test_dir/dir_a")
  child.type_keys "m"
  child.type_keys "test_dir/dir_b"
  mock_confirm(1)
  child.type_keys "<CR>"
  expect_fs_exists(vim.fs.abspath "test_dir/dir_a", false)
  expect_fs_exists(vim.fs.abspath "test_dir/dir_b/dir_a")
  validate_confirm_args(
    "Move\nFiles:\n" .. vim.fs.abspath "test_dir/dir_a" .. "\nTo:\n" .. vim.fs.abspath "test_dir/dir_b"
  )
end
T["tree"]["plug remaps"]["TreeMove"]["to parent path"] = function()
  child.type_keys { "l", "j", }
  expect_fs_exists(vim.fs.abspath "test_dir/dir_a/init.lua")
  child.type_keys "m"
  child.type_keys "test_dir"
  mock_confirm(1)
  child.type_keys "<CR>"
  expect_fs_exists(vim.fs.abspath "test_dir/dir_a/init.lua", false)
  expect_fs_exists(vim.fs.abspath "test_dir/init.lua")
  validate_confirm_args(
    "Move\nFiles:\n" .. vim.fs.abspath "test_dir/dir_a/init.lua" .. "\nTo:\n" .. vim.fs.abspath "test_dir"
  )
end
T["tree"]["plug remaps"]["TreeMove"]["abort empty"] = function()
  child.type_keys { "l", "j", }
  expect_fs_exists(vim.fs.abspath "test_dir/dir_a/init.lua")
  child.type_keys "m"
  child.type_keys "<CR>"
  expect_fs_exists(vim.fs.abspath "test_dir/dir_a/init.lua")
end
T["tree"]["plug remaps"]["TreeMove"]["abort confirmation"] = function()
  child.type_keys { "l", "j", }
  expect_fs_exists(vim.fs.abspath "test_dir/dir_a/init.lua")
  child.type_keys "m"
  child.type_keys "test_dir/dir_b"
  mock_confirm(2)
  child.type_keys "<CR>"
  expect_fs_exists(vim.fs.abspath "test_dir/dir_a/init.lua")
  expect_fs_exists(vim.fs.abspath "test_dir/dir_b/init.lua", false)
end
T["tree"]["plug remaps"]["TreeMove"]["visual mode"] = function()
  child.type_keys "l"
  expect_fs_exists(vim.fs.abspath "test_dir/dir_a/dir_c")
  expect_fs_exists(vim.fs.abspath "test_dir/dir_a/init.lua")
  child.type_keys "V"
  child.type_keys "j"
  child.type_keys "m"
  child.type_keys "test_dir/dir_b"
  mock_confirm(1)
  child.type_keys "<CR>"
  expect_fs_exists(vim.fs.abspath "test_dir/dir_a/dir_c", false)
  expect_fs_exists(vim.fs.abspath "test_dir/dir_a/init.lua", false)
  expect_fs_exists(vim.fs.abspath "test_dir/dir_b/dir_c")
  expect_fs_exists(vim.fs.abspath "test_dir/dir_b/init.lua")
  validate_confirm_args(
    "Move\nFiles:\n"
    .. vim.fs.abspath "test_dir/dir_a/dir_c"
    .. "\n"
    .. vim.fs.abspath "test_dir/dir_a/init.lua"
    .. "\nTo:\n"
    .. vim.fs.abspath "test_dir/dir_b"
  )
end
T["tree"]["plug remaps"]["TreeMove"]["files deleted"] = function()
  child.type_keys { "l", "j", }
  expect_fs_exists(vim.fs.abspath "test_dir/dir_a/init.lua")
  child.type_keys "m"
  child.type_keys "test_dir/dir_b"
  mock_confirm(1)
  child.type_keys "<CR>"
  expect_fs_exists(vim.fs.abspath "test_dir/dir_a/init.lua", false)
  expect_fs_exists(vim.fs.abspath "test_dir/dir_b/init.lua")
end

T["tree"]["cursor placement"] = MiniTest.new_set()
T["tree"]["cursor placement"]["curr-bufname"] = MiniTest.new_set()
T["tree"]["cursor placement"]["curr-bufname"]["found"] = function()
  child.lua [[vim.cmd.edit("test_dir/dir_a/init.lua")]]
  child.lua [[M.tree()]]
  expect_cursor_line(2, "  init.lua")
end
T["tree"]["cursor placement"]["curr-bufname"]["not found"] = function()
  child.lua [[vim.cmd.edit("test_dir/dir_b/Makefile")]]
  child.lua [[M.tree({ tree_dir = "./test_dir/dir_a" })]]
  expect_cursor_line(1, " 󰉋 dir_c")
end

T["tree"]["cursor placement"]["prev-idx"] = MiniTest.new_set()
T["tree"]["cursor placement"]["prev-idx"]["same cursor position before and after"] = function()
  child.type_keys "lj"
  expect_cursor_line(2, "  init.lua")
  mock_confirm(1)
  child.type_keys "dd"
  expect_cursor_line(2, " 󰛦 mod.ts")
end
T["tree"]["cursor placement"]["prev-idx"]["cursor is forced to an earlier index"] = function()
  child.type_keys "ljj"
  expect_cursor_line(3, " 󰛦 mod.ts")
  mock_confirm(1)
  child.type_keys "dd"
  expect_cursor_line(2, "  init.lua")
end
T["tree"]["cursor placement"]["prev-idx"]["cursor is forced to the top of the buf"] = function()
  child.type_keys "lVjj"
  expect_cursor_line(3, " 󰛦 mod.ts")
  mock_confirm(1)
  child.type_keys "d"
  expect_cursor_line(1, "")
end

T["tree"]["cursor placement"]["history-stack"] = MiniTest.new_set()
T["tree"]["cursor placement"]["history-stack"]["found"] = function()
  child.type_keys "llj"
  expect_cursor_line(2, " 󰌞 index.js")
  child.type_keys "hhll"
  expect_cursor_line(2, " 󰌞 index.js")
end
T["tree"]["cursor placement"]["history-stack"]["not found"] = function()
  child.type_keys "llj"
  expect_cursor_line(2, " 󰌞 index.js")
  child.type_keys "hhj"
  expect_cursor_line(2, " 󰉋 dir_b")
  child.type_keys "l"
  expect_cursor_line(1, "  .env") -- not 2
end

T["tree"]["cursor placement"]["prev-dir-idx"] = function()
  child.type_keys "j"
  expect_cursor_line(2, " 󰉋 dir_b")
  child.type_keys "l"
  expect_cursor_line(1, "  .env")
  child.type_keys "h"
  expect_cursor_line(2, " 󰉋 dir_b") -- not 1
end

T["tree"]["cursor placement"]["dest-path"] = MiniTest.new_set()
T["tree"]["cursor placement"]["dest-path"]["found"] = function()
  child.type_keys "o"
  child.type_keys "new_file.txt"
  mock_confirm(1)
  child.type_keys "<CR>"
  expect_cursor_line(3, " 󰦪 new_file.txt")
end
T["tree"]["cursor placement"]["dest-path"]["found nested"] = function()
  child.type_keys "o"
  child.type_keys "new_nested/path/file.lua"
  mock_confirm(1)
  child.type_keys "<CR>"
  expect_cursor_line(3, " 󰉋 new_nested")
end
T["tree"]["cursor placement"]["not found fallback"] = function()
  child.type_keys "l"
  expect_cursor_line(1, " 󰉋 dir_c")
  child.type_keys "o"
  child.type_keys "../new_file.txt"
  mock_confirm(1)
  child.type_keys "<CR>"
  expect_cursor_line(1, " 󰉋 dir_c")
end

return T
