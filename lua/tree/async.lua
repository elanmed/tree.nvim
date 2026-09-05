-- async.nvim @ 53f68e5ad41c0ceae9173926cec194dc0520c370
local M = {}

--- @class ThrottledIteratorOpts<InvariantState, ControlVar>
--- @field iterator_factory fun(): ((fun(invariant_state: InvariantState, control_var: ControlVar):ControlVar), InvariantState?, ControlVar?)
--- @field threshold_ns? number
--- @field should_cancel? fun():boolean
--- @field on_iteration fun(control_var: ControlVar, ...):nil

--- @generic InvariantState, ControlVar
--- @param opts ThrottledIteratorOpts<InvariantState, ControlVar>
--- @param callback fun(arg:nil):nil
local throttled_iterator_callback = function(opts, callback)
  local iterator_factory = opts.iterator_factory
  local threshold_ns = opts.threshold_ns or (10 * 1000000)
  local should_cancel = opts.should_cancel or function()
    return false
  end

  local function make_throttle()
    local last_yield = vim.uv.hrtime()
    return function()
      local now = vim.uv.hrtime()
      if (now - last_yield) >= threshold_ns then
        last_yield = now
        vim.async.sleep(0)
      end
    end
  end

  local maybe_pause = make_throttle()
  local iter_fn, invariant_state, control_var = iterator_factory()
  while true do
    if should_cancel() then
      callback(nil)
      return
    end
    maybe_pause()

    local values = { iter_fn(invariant_state, control_var) }
    control_var = values[1]

    if control_var == nil then
      callback(nil)
      return
    end

    opts.on_iteration(unpack(values))
  end
end

M.throttled_iterator = vim.async.wrap(
  2,
  --- @generic InvariantState, ControlVar
  --- @param opts ThrottledIteratorOpts<InvariantState, ControlVar>
  --- @param callback fun(arg:nil):nil
  function(opts, callback)
    local task = vim.async.run("throttled_iterator_taks", function()
      throttled_iterator_callback(opts, function()
        callback(nil)
      end)
    end)
    task:on_complete(function(err)
      if err then
        callback(err)
      end
    end)
    return task
  end
)

return M
