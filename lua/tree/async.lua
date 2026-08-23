-- async.nvim @ eede105ccf5345bc30533ef6e53c293580b1c2fb
local M = {}

--- @alias Resolve<T> fun(...: T): nil
--- @alias Reject fun(err: any): nil
--- @alias Promise<T> fun(resolve: Resolve<T>, reject?: Reject): nil
--- @alias AsyncFn<T> fun(...: any): Promise<T>
--- @alias MakeAsync<T> fun(fn: fun(...: any): T): AsyncFn<T>
--- @alias SpawnFn fun(...: any): nil
--- @alias MakeSpawn fun(fn: fun(...: any): any): SpawnFn

local function safe_resume(...)
  local ok, err = coroutine.resume(...)
  if not ok then error(err) end
end

local function default_reject(err)
  error(err)
end

--- @generic T
--- @param callback fun(resolve: Resolve<T>, reject?: Reject): nil
--- @return Promise<T>
M.from_executor = function(callback)
  return function(resolve, reject)
    reject = reject or default_reject
    local ok, err = pcall(callback, resolve, reject)
    if not ok then reject(err) end
  end
end

--- @generic T
--- @param fn fun(...: any): T
--- @return AsyncFn<T>
M.make_async = function(fn)
  return function(...)
    local args = { ..., }
    return function(resolve, reject)
      reject = reject or default_reject
      local thread = coroutine.create(function()
        local results = { pcall(fn, unpack(args)), }
        if results[1] then
          resolve(unpack(results, 2))
        else
          reject(results[2])
        end
      end)
      safe_resume(thread)
    end
  end
end

--- @type MakeSpawn
M.make_spawn = function(fn)
  return function(...)
    local promise = M.make_async(fn)(...)
    promise(function() end, default_reject)
  end
end

--- @generic T
--- @param promise Promise<T>
--- @return T
M.await = function(promise)
  local thread = coroutine.running()
  assert(thread ~= nil, "[async.nvim] `await` can only be called in a coroutine")
  local scheduled_promise = vim.schedule_wrap(promise)
  local resolve = vim.schedule_wrap(function(...) safe_resume(thread, true, ...) end)
  local reject = vim.schedule_wrap(function(err) safe_resume(thread, false, err) end)
  scheduled_promise(resolve, reject)
  local results = { coroutine.yield(), }
  if not results[1] then
    error(results[2], 0)
  end
  return unpack(results, 2)
end

--- @class ThrottledIteratorOpts
--- @field threshold_ns? number
--- @field should_cancel? fun():boolean

--- @generic InvariantState, ControlVar
--- @param iterator_factory fun(): ((fun(invariant_state: InvariantState, control_var: ControlVar):ControlVar), InvariantState?, ControlVar?)
--- @param on_iteration fun(control_var: ControlVar, ...):nil
--- @param opts? ThrottledIteratorOpts
M.throttled_iterator = function(iterator_factory, on_iteration, opts)
  local promise = M.make_async(function()
    opts = opts or {}
    local threshold_ns = opts.threshold_ns or (10 * 1000000)
    local should_cancel = opts.should_cancel or (function() return false end)

    local function create_throttle()
      local last_yield = vim.uv.hrtime()
      return function()
        local now = vim.uv.hrtime()
        if (now - last_yield) >= threshold_ns then
          last_yield = now
          local thread = coroutine.running()
          vim.schedule(function() safe_resume(thread) end)
          coroutine.yield()
        end
      end
    end

    local maybe_pause = create_throttle()
    local iter_fn, invariant_state, control_var = iterator_factory()
    while true do
      if should_cancel() then
        return nil
      end
      maybe_pause()

      local values = { iter_fn(invariant_state, control_var), }
      control_var = values[1]

      if control_var == nil then
        return nil
      end

      on_iteration(unpack(values))
    end
  end)
  return promise()
end

return M
