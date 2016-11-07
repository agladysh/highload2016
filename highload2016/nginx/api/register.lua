-- luacheck: globals ngx import

require 'lua-nucleo.import'

local tjson_simple = import 'lua-nucleo/string.lua' { 'tjson_simple' }
local tstr = import 'lua-nucleo/tstr.lua' { 'tstr' }

--------------------------------------------------------------------------------

local go_exists,
      go_uid,
      go_write_hash,
      go_write_chrs,
      go_add_action,
      go_write_proto_id,
      go_store,
      go_write_tags,
      go_block_action,
      go_unblock_action,
      go_write_geo
      = import 'go.lua'
      {
        'go_exists',
        'go_uid',
        'go_write_hash',
        'go_write_chrs',
        'go_add_action',
        'go_write_proto_id',
        'go_store',
        'go_write_tags',
        'go_block_action',
        'go_unblock_action',
        'go_write_geo'
      }

import 'actions.lua' ()

--------------------------------------------------------------------------------

local USER_ID
local GEO = { }
do
  local uri_args = ngx.req.get_uri_args()

  USER_ID = uri_args.usr
  if not USER_ID then
    ngx.status = ngx.HTTP_BAD_REQUEST
    ngx.say(tjson_simple({
      status = 'ERROR';
      message = 'missing user id';
    }))
    return ngx.exit(ngx.status)
  end

  GEO.lon = uri_args.lon and tonumber(uri_args.lon)
  GEO.lat = uri_args.lat and tonumber(uri_args.lat)
  if not GEO.lon or not GEO.lat then
    ngx.status = ngx.HTTP_BAD_REQUEST
    ngx.say(tjson_simple({
      status = 'ERROR';
      message = 'missing geo coordinates';
    }))
    return ngx.exit(ngx.status)
  end
end

if go_exists(USER_ID) then
  ngx.status = ngx.HTTP_CONFLICT
  ngx.say(tjson_simple({
    status = 'ERROR';
    message = 'duplicate user id';
  }))
  return ngx.exit(ngx.status)
end

--------------------------------------------------------------------------------

-- TODO: Generalize all this stuff with /reset code!
go_write_hash(USER_ID, { })
go_write_geo(USER_ID, GEO)
go_write_proto_id(USER_ID, 'proto.user')
go_write_tags(USER_ID, { 'user.alive', 'user.id=' .. USER_ID })

--------------------------------------------------------------------------------
-- Admin items for everyone --- in this version of the prototype.
--------------------------------------------------------------------------------

do
  local id = go_uid()
  go_write_hash(id, { provides_tags = tstr { 'user.admin' } })
  go_write_proto_id(id, 'proto.item.admin-hat')
  go_write_chrs(id, { })
  go_block_action(id, 'act.doff.common')
  go_unblock_action(id, 'act.don.common')
  go_store(USER_ID, id)
end

do
  local id = go_uid()
  go_write_hash(id, { })
  go_write_proto_id(id, 'proto.spawn-wand.toad.green')
  go_store(USER_ID, id)
end

--------------------------------------------------------------------------------

ngx.say(tjson_simple({ status = 'ok' }))
