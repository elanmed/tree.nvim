require "mini.test".setup()

local expect = MiniTest.expect
local child = MiniTest.new_child_neovim()

local T = MiniTest.new_set {
  hooks = {
    pre_case = function()
      child.restart { "-u", "scripts/minimal_init.lua", }
      child.bo.readonly = false
      child.lua [[M = require('tree')]]
      child.o.lines = 30
      child.o.columns = 30
      child.lua [[
        M.tree {
          tree_dir = "./test_dir",
          keymaps = {
            ["<cr>"] = "select",
            ["q"] = "close-tree",
            ["<"] = "dec-limit",
            [">"] = "inc-limit",
            ["h"] = "out-dir",
            ["l"] = "in-dir",
          }
        }
      ]]
    end,
    post_once = child.stop,
  },
}

T["tree"] = MiniTest.new_set()

T["tree"]["keymaps"] = MiniTest.new_set()
T["tree"]["keymaps"]["inc-limit"] = function()
  expect.reference_screenshot(child.get_screenshot())
  child.type_keys ">"
  expect.reference_screenshot(child.get_screenshot())
  child.type_keys ">"
  expect.reference_screenshot(child.get_screenshot())
end
T["tree"]["keymaps"]["dec-limit"] = function()
  child.type_keys { ">", ">", }
  child.type_keys ">"
  expect.reference_screenshot(child.get_screenshot())
  child.type_keys "<"
  expect.reference_screenshot(child.get_screenshot())
  child.type_keys "<"
  expect.reference_screenshot(child.get_screenshot())
end
T["tree"]["keymaps"]["in-dir"] = function()
  expect.reference_screenshot(child.get_screenshot())
  child.type_keys { "j", "l", }
  expect.reference_screenshot(child.get_screenshot())
  child.type_keys "l"
  expect.reference_screenshot(child.get_screenshot())
end
T["tree"]["keymaps"]["out-dir"] = function()
  child.type_keys { "j", "l", "l", }
  expect.reference_screenshot(child.get_screenshot())
  child.type_keys "h"
  expect.reference_screenshot(child.get_screenshot())
  child.type_keys "h"
  expect.reference_screenshot(child.get_screenshot())
end
T["tree"]["keymaps"]["select"] = function()
  child.type_keys { "j", "l", "l", }
  expect.reference_screenshot(child.get_screenshot())
  child.type_keys "<cr>"
  expect.reference_screenshot(child.get_screenshot())
  child.lua [[M.tree()]]
  expect.reference_screenshot(child.get_screenshot())
end
T["tree"]["keymaps"]["close"] = function()
  expect.reference_screenshot(child.get_screenshot())
  child.type_keys "q"
  expect.reference_screenshot(child.get_screenshot())
end

T["tree"]["buffer switching autocommand"] = function()
  child.type_keys { "j", "l", "l", "<cr>", }
  expect.reference_screenshot(child.get_screenshot())
  child.lua [[M.tree()]]
  expect.reference_screenshot(child.get_screenshot())
  child.type_keys "<C-o>"
  expect.reference_screenshot(child.get_screenshot())
end

return T
