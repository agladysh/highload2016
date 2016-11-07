-- luacheck: globals ngx import

require 'lua-nucleo.import'

local tstr = import 'lua-nucleo/tstr.lua' { 'tstr' }
local tpretty = import 'lua-nucleo/tpretty.lua' { 'tpretty' }
local tjson_simple = import 'lua-nucleo/string.lua' { 'tjson_simple' }

local go_exists,
      go_initiate_scheduled_actions,
      go_load_as,
      go_write_geo,
      go_list_in_geo_range
      = import 'go.lua'
      {
        'go_exists',
        'go_initiate_scheduled_actions',
        'go_load_as',
        'go_write_geo',
        'go_list_in_geo_range'
      }

-- TODO: Fix this and above file so them both are always imported together
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

local user = go_load_as(USER_ID, USER_ID)
if not user.geo or not user.chrs.vision then
  error('missing user vision for ' .. tstr(user))
end

local result = { }
local gos = go_list_in_geo_range(user.geo, user.chrs.vision)
for i = 1, #gos do
  result[#result + 1] = go_load_as(gos[i], USER_ID)
end

ngx.say(tjson_simple({ status = 'ok', gos = result }))
