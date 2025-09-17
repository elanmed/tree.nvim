local T = MiniTest.new_set()

T["dummy"] = function()
  MiniTest.expect.equality(true, true)
end

return T
