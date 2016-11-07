-- luacheck: globals import ngx

local tstr = import 'lua-nucleo/tstr.lua' { 'tstr' }
local tset = import 'lua-nucleo/table-utils.lua' { 'tset' }

local ACTIONS,
      go_uid,
      go_write_hash,
      go_write_proto_id,
      go_read_proto_id,
      go_remove,
      go_schedule_action_initiation,
      go_write_chr,
      go_write_chrs,
      go_initiate_action,
      go_add_action,
      go_action_write_tags,
      go_attach,
      go_detach,
      go_is_attached,
      go_store,
      go_unstore,
      go_is_stored,
      go_block_action,
      go_unblock_action,
      go_add_tag,
      go_remove_tag,
      go_write_tags,
      go_write_geo
      = import 'go.lua'
      {
        'ACTIONS',
        'go_uid',
        'go_write_hash',
        'go_write_proto_id',
        'go_read_proto_id',
        'go_remove',
        'go_schedule_action_initiation',
        'go_write_chr',
        'go_write_chrs',
        'go_initiate_action',
        'go_add_action',
        'go_action_write_tags',
        'go_attach',
        'go_detach',
        'go_is_attached',
        'go_store',
        'go_unstore',
        'go_is_stored',
        'go_block_action',
        'go_unblock_action',
        'go_add_tag',
        'go_remove_tag',
        'go_write_tags',
        'go_write_geo'
      }

--------------------------------------------------------------------------------

--
-- NB:
-- Target is the owner of the action
-- Initiator is the initiator of the action
--

ACTIONS['act.spawn.mob.common'] = function(target, initiator)
  local id = go_uid()
  local geo = (initiator.chrs.lon and initiator.chrs.lat)
    and initiator.chrs
     or initiator.geo
  local proto_id = assert(
    target.chrs.id or initiator.chrs.id,
    'missing proto id in chrs'
  )

  ngx.log(ngx.NOTICE,
    'spawning mob id ', id,
    ' proto id ', proto_id,
    ' geo (', geo.lon, ', ', geo.lat, ')'
  )

  go_write_hash(id, { })
  go_write_geo(id, { lon = assert(geo.lon), lat = assert(geo.lat) })
  go_write_proto_id(id, proto_id)

  if tset(initiator.tags)['system-initiator'] then
    go_remove(initiator.id)
  end
end

ACTIONS['act.remove.common'] = function(target, _)
  go_remove(target.id)
end

ACTIONS['act.don.common'] = function(target, initiator)
  assert(
    go_is_stored(initiator.id, target.id),
    'the item is not stored in the initiator'
  )
  go_unstore(initiator.id, target.id)
  go_attach(initiator.id, target.id)
  go_block_action(target.id, 'act.don.common')
  go_unblock_action(target.id, 'act.doff.common')

  -- TODO: Hack. This approach to the implementation needs
  --       reference counters to keep track of how many items provide
  --       that tag or another. Redesign from scratch.
  if target.hash.provides_tags then
    local tags = assert(loadstring('return ' .. target.hash.provides_tags))()
    for i = 1, #tags do
      go_add_tag(initiator.id, tags[i])
    end
  end
end

ACTIONS['act.doff.common'] = function(target, initiator)
  assert(
    go_is_attached(initiator.id, target.id),
    'the item is not attached to the initiator'
  )
  go_detach(initiator.id, target.id)
  go_store(initiator.id, target.id)
  go_block_action(target.id, 'act.doff.common')
  go_unblock_action(target.id, 'act.don.common')

  -- TODO: Hack. See above.
  if target.hash.provides_tags then
    local tags = assert(loadstring('return ' .. target.hash.provides_tags))()
    for i = 1, #tags do
      go_remove_tag(initiator.id, tags[i])
    end
  end
end

ACTIONS['act.mob.collect.common'] = function(target, initiator)
  if
    math.random() * (initiator.chrs.collect_skill or 0) >
    (target.chrs.escape_chance or 0)
  then
    local proto_id = assert(go_read_proto_id(target.id))

    ngx.log(
      ngx.NOTICE,
      'caught ', target.id, ' ', proto_id, ' by ', initiator.id
    )

    -- Inc number of catches for this mob type
    go_write_chr(
      initiator.id, proto_id,
      (initiator.chrs[proto_id] or 0) + 1
    )

    -- Schedule respawn
    local initiator_id = go_uid()
    go_write_hash(initiator_id, { })
    -- Can't write geo to the GO directly,
    -- otherwise it would be visible on the map
    go_write_chrs(initiator_id, {
      id = proto_id;
      lon = target.geo.lon;
      lat = target.geo.lat;
    })
    go_write_tags(initiator_id, { 'system-initiator' })
    go_schedule_action_initiation(
      assert(target.chrs.respawn_dt),
      'world', initiator_id, 'act.spawn.mob.common'
    )

    go_remove(target.id) -- Mob is caught, remove end
  else
    -- Inc number of catch fails
    go_write_chr(
      initiator.id, 'fails',
      (initiator.chrs.fails or 0) + 1
    )
  end
end

--------------------------------------------------------------------------------

return
{
  ACTIONS = ACTIONS;
}
