require "mini.test".setup()

local expect = MiniTest.expect
local child = MiniTest.new_child_neovim()

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
        vim.keymap.set("n", "<", "<Plug>TreeDecreaseLevel", { buffer = true })
        vim.keymap.set("n", ">", "<Plug>TreeIncreaseLevel", { buffer = true })
        vim.keymap.set("n", "h", "<Plug>TreeOutDir", { buffer = true })
        vim.keymap.set("n", "l", "<Plug>TreeInDir", { buffer = true })
        vim.keymap.set("n", "yr", "<Plug>TreeYankRelativePath", { buffer = true })
        vim.keymap.set("n", "ya", "<Plug>TreeYankAbsolutePath", { buffer = true })
        vim.keymap.set("n", "yd", "<Plug>TreeYankDirectoryPath", { buffer = true })
        vim.keymap.set("n", "o", "<Plug>TreeCreate", { buffer = true })
        vim.keymap.set("n", "e", "<Plug>TreeRefresh", { buffer = true })
        vim.keymap.set("n", "r", "<Plug>TreeRename", { buffer = true })
        vim.keymap.set("n", "dd", "<Plug>TreeDelete", { buffer = true })
      ]]
    end,
    post_once = child.stop,
  },
}

T["tree"] = MiniTest.new_set()

T["tree"]["plug remaps"] = MiniTest.new_set()
T["tree"]["plug remaps"]["TreeIncreaseLevel"] = function()
  expect.reference_screenshot(child.get_screenshot())
  child.type_keys ">"
  expect.reference_screenshot(child.get_screenshot())
  child.type_keys ">"
  expect.reference_screenshot(child.get_screenshot())
end
T["tree"]["plug remaps"]["TreeDecreaseLevel"] = function()
  child.type_keys { ">", ">", }
  child.type_keys ">"
  expect.reference_screenshot(child.get_screenshot())
  child.type_keys "<"
  expect.reference_screenshot(child.get_screenshot())
  child.type_keys "<"
  expect.reference_screenshot(child.get_screenshot())
end
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
  MiniTest.expect.equality(child.fn.getreg "", "test_dir/dir_a")

  child.type_keys "j"
  child.type_keys { "y", "r", }
  MiniTest.expect.equality(child.fn.getreg "", "test_dir/dir_b")
end
T["tree"]["plug remaps"]["TreeYankAbsolutePath"] = function()
  child.type_keys { "y", "a", }
  MiniTest.expect.equality(child.fn.getreg "", vim.fs.joinpath(child.fn.getcwd(), "test_dir/dir_a"))

  child.type_keys "j"
  child.type_keys { "y", "a", }
  MiniTest.expect.equality(child.fn.getreg "", vim.fs.joinpath(child.fn.getcwd(), "test_dir/dir_b"))
end
T["tree"]["plug remaps"]["TreeYankAbsolutePath"] = function()
  child.type_keys { "y", "d", }
  MiniTest.expect.equality(child.fn.getreg "", vim.fs.joinpath(child.fn.getcwd(), "test_dir"))

  child.type_keys "j"
  child.type_keys { "y", "d", }
  MiniTest.expect.equality(child.fn.getreg "", vim.fs.joinpath(child.fn.getcwd(), "test_dir"))
end

return T
