require "mini.test".setup()

local expect = MiniTest.expect
local eq = MiniTest.expect.equality
local child = MiniTest.new_child_neovim()

local root_path = vim.fs.abspath(vim.fs.joinpath(vim.fn.getcwd(), "test_dir"))

local new_file_path = "new_file.txt"
local new_dir_path = "new_dir/"
local new_nested_file_path = "nested/path/file.lua"

local new_file_path_full = vim.fs.joinpath(root_path, new_file_path)
local new_dir_path_full = vim.fs.joinpath(root_path, new_dir_path)
local new_nested_file_path_full = vim.fs.joinpath(root_path, new_nested_file_path)

local new_paths = {
  new_file_path_full,
  new_dir_path_full,
  new_nested_file_path_full,
}

local expect_fs_exists = MiniTest.new_expectation(
  "file system path exists",
  function(path) return vim.uv.fs_stat(path) ~= nil end,
  function(path) return string.format("Path: %s", path) end
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
      ]]
    end,
    post_case = function()
      for _, path in ipairs(new_paths) do
        child.fn.delete(path, "rf")
      end
    end,
    post_once = child.stop,
  },
}

T["tree"] = MiniTest.new_set()

T["tree"]["plug remaps"] = MiniTest.new_set()
T["tree"]["plug remaps"]["TreeInDir"] = function()
  expect.reference_screenshot(child.get_screenshot())
  child.type_keys "l"
  expect.reference_screenshot(child.get_screenshot())
  child.type_keys "l"
  expect.reference_screenshot(child.get_screenshot())
end
T["tree"]["plug remaps"]["TreeOutDir"] = function()
  child.type_keys { "l", "l", }
  expect.reference_screenshot(child.get_screenshot())
  child.type_keys "h"
  expect.reference_screenshot(child.get_screenshot())
  child.type_keys "h"
  expect.reference_screenshot(child.get_screenshot())
end
T["tree"]["plug remaps"]["TreeSelect"] = function()
  child.type_keys { "l", "l", }
  expect.reference_screenshot(child.get_screenshot())
  child.type_keys "<cr>"
  expect.reference_screenshot(child.get_screenshot())
  child.lua [[M.tree()]]
  expect.reference_screenshot(child.get_screenshot())
end
T["tree"]["plug remaps"]["TreeCloseTree"] = function()
  expect.reference_screenshot(child.get_screenshot())
  child.type_keys "q"
  expect.reference_screenshot(child.get_screenshot())
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
  eq(child.fn.getreg "a", vim.fs.joinpath(child.fn.getcwd(), "test_dir/dir_a"))

  child.type_keys "j"
  child.type_keys { "y", "a", }
  eq(child.fn.getreg "a", vim.fs.joinpath(child.fn.getcwd(), "test_dir/dir_b"))
end
T["tree"]["plug remaps"]["TreeYankAbsolute"] = function()
  child.type_keys { "y", "d", }
  eq(child.fn.getreg "d", vim.fs.joinpath(child.fn.getcwd(), "test_dir"))

  child.type_keys "j"
  child.type_keys { "y", "d", }
  eq(child.fn.getreg "d", vim.fs.joinpath(child.fn.getcwd(), "test_dir"))
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

  local cmdline = child.fn.getcmdline()
  eq(cmdline, "test_dir/")

  child.type_keys(new_file_path)

  mock_confirm(1)
  child.type_keys "<CR>"

  expect_fs_exists(new_file_path_full)
  validate_confirm_args("Create? " .. new_file_path_full)
end
T["tree"]["plug remaps"]["TreeCreate"]["directory"] = function() end
T["tree"]["plug remaps"]["TreeCreate"]["children path"] = function() end
T["tree"]["plug remaps"]["TreeCreate"]["parent path"] = function() end
T["tree"]["plug remaps"]["TreeCreate"]["abort empty"] = function() end
T["tree"]["plug remaps"]["TreeCreate"]["abort confirmation"] = function() end

T["tree"]["plug remaps"]["TreeRename"] = MiniTest.new_set()
T["tree"]["plug remaps"]["TreeRename"]["file"] = function() end

T["tree"]["plug remaps"]["TreeRename"]["directory"] = function() end
T["tree"]["plug remaps"]["TreeRename"]["to parent path"] = function() end
T["tree"]["plug remaps"]["TreeRename"]["to child path"] = function() end
T["tree"]["plug remaps"]["TreeRename"]["abort empty"] = function() end
T["tree"]["plug remaps"]["TreeRename"]["abort confirmation"] = function() end
T["tree"]["plug remaps"]["TreeRename"]["destination exists"] = function() end

T["tree"]["plug remaps"]["TreeDelete"] = MiniTest.new_set()
T["tree"]["plug remaps"]["TreeDelete"]["single file"] = function() end
T["tree"]["plug remaps"]["TreeDelete"]["directory"] = function() end
T["tree"]["plug remaps"]["TreeDelete"]["abort confirmation"] = function() end
T["tree"]["plug remaps"]["TreeDelete"]["visual mode"] = function() end

T["tree"]["plug remaps"]["TreeCopy"] = MiniTest.new_set()
T["tree"]["plug remaps"]["TreeCopy"]["single file"] = function() end
T["tree"]["plug remaps"]["TreeCopy"]["directory"] = function() end
T["tree"]["plug remaps"]["TreeCopy"]["to parent path"] = function() end
T["tree"]["plug remaps"]["TreeCopy"]["abort empty"] = function() end
T["tree"]["plug remaps"]["TreeCopy"]["abort confirmation"] = function() end
T["tree"]["plug remaps"]["TreeCopy"]["visual mode"] = function() end
T["tree"]["plug remaps"]["TreeCopy"]["destination exists"] = function() end

T["tree"]["plug remaps"]["TreeMove"] = MiniTest.new_set()
T["tree"]["plug remaps"]["TreeMove"]["single file"] = function() end
T["tree"]["plug remaps"]["TreeMove"]["directory"] = function() end
T["tree"]["plug remaps"]["TreeMove"]["to parent path"] = function() end
T["tree"]["plug remaps"]["TreeMove"]["abort empty"] = function() end
T["tree"]["plug remaps"]["TreeMove"]["abort confirmation"] = function() end
T["tree"]["plug remaps"]["TreeMove"]["visual mode"] = function() end
T["tree"]["plug remaps"]["TreeMove"]["files deleted"] = function() end

T["tree"]["cursor placement"] = MiniTest.new_set()
T["tree"]["cursor placement"]["curr-bufname"] = MiniTest.new_set()
T["tree"]["cursor placement"]["curr-bufname"]["found"] = function() end
T["tree"]["cursor placement"]["curr-bufname"]["not found"] = function() end
T["tree"]["cursor placement"]["prev-idx"] = function() end

T["tree"]["cursor placement"]["history-stack"] = MiniTest.new_set()
T["tree"]["cursor placement"]["history-stack"]["found"] = function() end
T["tree"]["cursor placement"]["history-stack"]["not found"] = function() end

T["tree"]["cursor placement"]["prev-dir-idx"] = MiniTest.new_set()
T["tree"]["cursor placement"]["prev-dir-idx"]["found"] = function() end
T["tree"]["cursor placement"]["prev-dir-idx"]["not found"] = function() end

T["tree"]["cursor placement"]["dest-path"] = MiniTest.new_set()
T["tree"]["cursor placement"]["dest-path"]["found"] = function() end
T["tree"]["cursor placement"]["dest-path"]["not found fallback"] = function() end

return T
