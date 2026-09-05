-- async.nvim @ debde5c5a3f10fa9cbcd98b2d86afb9fe29d2728
local M = {}

local function safe_resume(...)
  local ok, err = coroutine.resume(...)
  if not ok then
    error(err)
  end
end

--- @class ThrottledIteratorOpts<ControlVar>
--- @field threshold_ns? number The minimum time in nanoseconds between yields to the main loop. Defaults to 10ms.
--- @field should_cancel? fun():boolean Called before each iteration; return true to stop early. Defaults to always returning false.
--- @field on_iteration fun(control_var: ControlVar, ...):nil Called for each item with the control variable and the iterator values.

--- @generic InvariantState, ControlVar
--- @param iterator_factory fun(): ((fun(invariant_state: InvariantState, control_var: ControlVar):ControlVar), InvariantState?, ControlVar?)
--- @param opts ThrottledIteratorOpts<ControlVar>
--- @param callback fun(arg:nil):nil
M.throttled_iterator_callback = function(iterator_factory, opts, callback)
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
        local thread = coroutine.running()
        vim.schedule(function()
          safe_resume(thread)
        end)
        coroutine.yield()
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

M.throttled_iterator_async = vim.async.wrap(
  2,
  --- @class ThrottledIteratorAsyncArgs<InvariantState, ControlVar>
  --- @field iterator_factory fun(): ((fun(invariant_state: InvariantState, control_var: ControlVar):ControlVar), InvariantState?, ControlVar?)
  --- @field opts ThrottledIteratorOpts<ControlVar>

  --- @generic InvariantState, ControlVar
  --- @param args ThrottledIteratorAsyncArgs<InvariantState, ControlVar>
  --- @param callback fun(arg:nil):nil
  function(args, callback)
    return M.throttled_iterator_callback(args.iterator_factory, args.opts, callback)
  end
)

return M
