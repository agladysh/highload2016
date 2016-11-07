-- luacheck: globals ngx import

require 'lua-nucleo.import'

local tjson_simple = import 'lua-nucleo/string.lua' { 'tjson_simple' }
local tstr = import 'lua-nucleo/tstr.lua' { 'tstr' }

local redis = import 'redis.lua' { 'redis' }

--------------------------------------------------------------------------------

local go_write_hash,
      go_write_chrs,
      go_add_action,
      go_action_write_tags,
      go_write_proto_id,
      go_store,
      go_attach,
      go_write_tags,
      go_block_action,
      go_unblock_action,
      go_write_geo
      = import 'go.lua'
      {
        'go_write_hash',
        'go_write_chrs',
        'go_add_action',
        'go_action_write_tags',
        'go_write_proto_id',
        'go_store',
        'go_attach',
        'go_write_tags',
        'go_block_action',
        'go_unblock_action',
        'go_write_geo'
      }

import 'actions.lua' ()

--------------------------------------------------------------------------------

-- NB: Not requiring USER_ID here for obvious reasons.
local GEO = { }
do
  local uri_args = ngx.req.get_uri_args()
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

--------------------------------------------------------------------------------

assert(redis():flushall())
assert(redis():set('geo:db:version', '0.0.1'))

--------------------------------------------------------------------------------

go_write_hash('world', { })
go_write_geo('world', { lon = 0, lat = 0 }) -- TODO: Are these good defaults?
go_write_chrs('world', { })
go_add_action('world', 'act.spawn.mob.common')
go_action_write_tags('world', 'act.spawn.mob.common', { 'system-initiator' })

--------------------------------------------------------------------------------

go_write_hash('proto.mob.common', { })
go_write_chrs('proto.mob.common', { })
go_add_action('proto.mob.common', 'act.remove.common')
go_action_write_tags(
  'proto.mob.common', 'act.remove.common',
  { 'user.admin' }
)

--------------------------------------------------------------------------------

go_write_hash('proto.mob.collectable', { })
go_write_proto_id('proto.mob.collectable', 'proto.mob.common')
go_write_chrs('proto.mob.collectable', { })
go_add_action('proto.mob.collectable', 'act.mob.collect.common')

--------------------------------------------------------------------------------

go_write_hash('proto.toad.green', { })
go_write_proto_id('proto.toad.green', 'proto.mob.collectable')
go_write_chrs('proto.toad.green', {
  respawn_dt = 10; -- Seconds
  escape_chance = 0.25;
})

--------------------------------------------------------------------------------

go_write_hash('proto.item.wearable', { })
go_write_chrs('proto.item.wearable', { })
go_add_action('proto.item.wearable', 'act.don.common')
go_add_action('proto.item.wearable', 'act.doff.common')

--------------------------------------------------------------------------------

go_write_hash('proto.item.admin-hat', { })
go_write_proto_id('proto.item.admin-hat', 'proto.item.wearable')
go_write_chrs('proto.item.admin-hat', { collect_skill = 0.25 })

--------------------------------------------------------------------------------

go_write_hash('proto.spawn-wand.common', { })
go_write_chrs('proto.spawn-wand.common', { })
go_add_action('proto.spawn-wand.common', 'act.spawn.mob.common')
go_action_write_tags(
  'proto.spawn-wand.common', 'act.spawn.mob.common',
  { 'user.admin' }
)

--------------------------------------------------------------------------------

go_write_hash('proto.spawn-wand.toad.green', { })
go_write_proto_id('proto.spawn-wand.toad.green', 'proto.spawn-wand.common')
go_write_chrs('proto.spawn-wand.toad.green', { id = 'proto.toad.green' })

--------------------------------------------------------------------------------

go_write_hash('proto.user', { })
go_write_chrs('proto.user', {
  vision = 100; -- Meters
  reach = 75; -- Meters
  collect_skill = 0.5;
})

--------------------------------------------------------------------------------

ngx.say(tjson_simple({ status = 'ok' }))
