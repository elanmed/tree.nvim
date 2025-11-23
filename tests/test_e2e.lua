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
        vim.keymap.set("n", "<cr>", "<Plug>TreeSelect" )
        vim.keymap.set("n", "q", "<Plug>TreeCloseTree")
        vim.keymap.set("n", "<", "<Plug>TreeDecreaseLevel")
        vim.keymap.set("n", ">", "<Plug>TreeIncreaseLevel")
        vim.keymap.set("n", "h", "<Plug>TreeOutDir")
        vim.keymap.set("n", "l", "<Plug>TreeInDir")
        vim.keymap.set("n", "yr", "<Plug>TreeYankRelativePath")
        vim.keymap.set("n", "ya", "<Plug>TreeYankAbsolutePath")
        vim.keymap.set("n", "o", "<Plug>TreeCreate")
        vim.keymap.set("n", "e", "<Plug>TreeRefresh")
        vim.keymap.set("n", "r", "<Plug>TreeRename")
        vim.keymap.set("n", "dd", "<Plug>TreeDelete")
      ]]
    end,
    post_once = child.stop,
  },
}

T["tree"] = MiniTest.new_set()

T["tree"] = MiniTest.new_set()
T["tree"]["inc-level"] = function()
  expect.reference_screenshot(child.get_screenshot())
  child.type_keys ">"
  expect.reference_screenshot(child.get_screenshot())
  child.type_keys ">"
  expect.reference_screenshot(child.get_screenshot())
end
T["tree"]["dec-level"] = function()
  child.type_keys { ">", ">", }
  child.type_keys ">"
  expect.reference_screenshot(child.get_screenshot())
  child.type_keys "<"
  expect.reference_screenshot(child.get_screenshot())
  child.type_keys "<"
  expect.reference_screenshot(child.get_screenshot())
end
T["tree"]["in-dir"] = function()
  expect.reference_screenshot(child.get_screenshot())
  child.type_keys { "l", }
  expect.reference_screenshot(child.get_screenshot())
  child.type_keys "l"
  expect.reference_screenshot(child.get_screenshot())
end
T["tree"]["out-dir"] = function()
  child.type_keys { "l", "l", }
  expect.reference_screenshot(child.get_screenshot())
  child.type_keys "h"
  expect.reference_screenshot(child.get_screenshot())
  child.type_keys "h"
  expect.reference_screenshot(child.get_screenshot())
end
T["tree"]["select"] = function()
  child.type_keys { "l", "l", }
  expect.reference_screenshot(child.get_screenshot())
  child.type_keys "<cr>"
  expect.reference_screenshot(child.get_screenshot())
  child.lua [[M.tree()]]
  expect.reference_screenshot(child.get_screenshot())
end
T["tree"]["close"] = function()
  expect.reference_screenshot(child.get_screenshot())
  child.type_keys "q"
  expect.reference_screenshot(child.get_screenshot())
end

return T
