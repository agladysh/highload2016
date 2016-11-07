--------------------------------------------------------------------------------
--- Coroutine module extensions
-- @module lua-nucleo.coro
-- This file is a part of lua-nucleo library
-- @copyright lua-nucleo authors (see file `COPYRIGHT` for the license)
--------------------------------------------------------------------------------

-- Supports yielding from inner to outer coroutine across nested coroutines.
-- Depends on built-in Lua coroutine module.
-- Also provides yield_outer-compliant pcall function.
-- See basic test for example.

-- TODO: Try to provide xpcall as well.

local setmetatable = setmetatable

local coroutine = coroutine
local coroutine_create, coroutine_resume, coroutine_yield =
      coroutine.create, coroutine.resume, coroutine.yield

-- Should be newproxy()
local outer_yield_tag = function() end

local function maybe_forward_yield(co, status, tag, ...)
  if status == true and tag == outer_yield_tag then
    return maybe_forward_yield(
        co,
        coroutine_resume(
            co,
            coroutine_yield(tag, ...)
          )
      )
  end
  return status, tag, ...
end

local resume_inner = function(co, ...)
  return maybe_forward_yield(co, coroutine_resume(co, ...))
end

local yield_outer = function(...)
  return coroutine_yield(outer_yield_tag, ...)
end

local is_outer_yield_tag = function(v)
  return v == outer_yield_tag
end

local eat_tag = function(status, v, ...)
  if v == outer_yield_tag then
    return status, ...
  end
  return status, v, ...
end

return
{
  resume_inner = resume_inner;
  yield_outer = yield_outer;
  is_outer_yield_tag = is_outer_yield_tag;
  eat_tag = eat_tag;
}
