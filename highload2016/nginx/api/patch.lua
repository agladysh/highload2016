-- luacheck: globals ngx import

require 'lua-nucleo.import'

local tjson_simple = import 'lua-nucleo/string.lua' { 'tjson_simple' }
local tstr = import 'lua-nucleo/tstr.lua' { 'tstr' }

local redis = import 'redis.lua' { 'redis' }

--------------------------------------------------------------------------------

local go_write_chr,
      go_write_hash,
      go_write_proto_id,
      go_write_chrs,
      go_add_action,
      go_action_write_tags
      = import 'go.lua'
      {
        'go_write_chr',
        'go_write_hash',
        'go_write_proto_id',
        'go_write_chrs',
        'go_add_action',
        'go_action_write_tags'
      }

import 'actions.lua' ()

--------------------------------------------------------------------------------

-- TODO: Patch in a loop until fully patched?

local version = assert(redis():get('geo:db:version'))
if not version or version == ngx.null then
  version = '0.0.1'
  assert(redis():set('geo:db:version', version))
elseif version == '0.0.1' then
  ngx.status = ngx.HTTP_OK -- Not quite an error.
  ngx.say(tjson_simple({
    status = 'ERROR';
    message = 'already at latest db version';
  }))
  return ngx.exit(ngx.status)
else
  ngx.status = ngx.HTTP_INTERNAL_SERVER_ERROR
  ngx.say(tjson_simple({
    status = 'ERROR';
    message = 'unknown db version';
  }))
  return ngx.exit(ngx.status)
end

--------------------------------------------------------------------------------

ngx.say(tjson_simple({ status = 'ok' }))
