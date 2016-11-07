-- luacheck: globals ngx import

require 'lua-nucleo.import'

local tjson_simple = import 'lua-nucleo/string.lua' { 'tjson_simple' }

local go_write_geo,
      go_exists,
      go_read_distance,
      go_load_as,
      go_initiate_scheduled_actions
      = import 'go.lua'
      {
        'go_write_geo',
        'go_exists',
        'go_read_distance',
        'go_load_as',
        'go_initiate_scheduled_actions'
      }

import 'actions.lua' ()

--------------------------------------------------------------------------------

go_initiate_scheduled_actions()

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

if not go_exists(USER_ID) then
  ngx.status = ngx.HTTP_UNAUTHORIZED
  ngx.say(tjson_simple({
    status = 'ERROR';
    message = 'unknown user ID, please /register';
  }))
  return ngx.exit(ngx.status)
end

go_write_geo(USER_ID, GEO)

local user = go_load_as(USER_ID, USER_ID)

ngx.header.content_type = 'application/json'

local id = ngx.var[1]
if not go_exists(id) or go_read_distance(id, USER_ID) > user.chrs.vision then
  ngx.status = ngx.HTTP_NOT_FOUND
  ngx.say(tjson_simple({
    status = 'ERROR';
    message = 'game object not found or is not visible';
  }))
  return ngx.exit(ngx.status)
end

ngx.say(tjson_simple(go_load_as(id, USER_ID)))
