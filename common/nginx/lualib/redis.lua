-- luacheck: globals ngx import

require 'lua-nucleo.import'

local resty_redis = require 'resty.redis'

--------------------------------------------------------------------------------

local redis
do
  local conn
  redis = function()
    if conn then
      return conn
    end

    conn = assert(resty_redis:new())
    conn:set_timeout(1000) -- 1 second
    assert(conn:connect('redis', 6379))

    return conn
  end
end

--------------------------------------------------------------------------------

return
{
  redis = redis;
}
