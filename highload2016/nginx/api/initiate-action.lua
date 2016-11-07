-- luacheck: globals ngx import

require 'lua-nucleo.import'

local tjson_simple = import 'lua-nucleo/string.lua' { 'tjson_simple' }

local go_exists,
      go_have_action_as,
      go_initiate_action,
      go_initiate_scheduled_actions,
      go_write_geo
      = import 'go.lua'
      {
        'go_exists',
        'go_have_action_as',
        'go_initiate_action',
        'go_initiate_scheduled_actions',
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

if not go_exists(USER_ID) then
  ngx.status = ngx.HTTP_UNAUTHORIZED
  ngx.say(tjson_simple({
    status = 'ERROR';
    message = 'unknown user ID, please /register';
  }))
  return ngx.exit(ngx.status)
end

go_write_geo(USER_ID, GEO)

--------------------------------------------------------------------------------

go_initiate_scheduled_actions()

--------------------------------------------------------------------------------

local go_id = ngx.var[1]
local action_id = ngx.var[2]

if not go_exists(go_id) then
  ngx.status = ngx.HTTP_NOT_FOUND
  ngx.say(tjson_simple({ status = 'ERROR', message = 'game object not found' }))
  ngx.log(ngx.NOTICE, 'go not found ', go_id)
  return ngx.exit(ngx.status)
end

if not go_have_action_as(go_id, action_id, USER_ID) then
  ngx.status = ngx.HTTP_NOT_FOUND
  ngx.say(tjson_simple({ status = 'ERROR', message = 'action not found' }))
  ngx.log(ngx.NOTICE,
    'action not found go ', go_id,
    ' act ', action_id,
    ' user ', USER_ID
  )
  return ngx.exit(ngx.status)
end

ngx.log(
  ngx.NOTICE,
  'initiate-action go ', go_id, ' act ', action_id, ' user ', USER_ID
)

go_initiate_action(go_id, USER_ID, action_id)

--------------------------------------------------------------------------------

ngx.say(tjson_simple({ status = 'ok' }))
