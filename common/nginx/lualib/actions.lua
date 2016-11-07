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

  go_block_action(id, 'act.die.mob.common')
  if tset(initiator.tags)['system-initiator'] then
    go_remove(initiator.id)
  end
end

ACTIONS['act.die.mob.common'] = function(target, _)
  -- TODO: Handle coordinates

  ngx.log(ngx.NOTICE,
    'mob died id ', target.id,
    ' proto id ', target.proto_id,
    ' geo (', target.geo.lon, ', ', target.geo.lat, ')'
  )

  --
  -- Generate drop
  --

  if math.random() > 0.25 then
    local drop_id = go_uid()
    go_write_hash(drop_id, { })
    go_write_geo(drop_id, target.geo)
    go_write_proto_id(drop_id, 'proto.drop.potion.attack')
  end

  if math.random() > 0.25 then
    local drop_id = go_uid()
    go_write_hash(drop_id, { })
    go_write_geo(drop_id, target.geo)
    go_write_proto_id(drop_id, 'proto.drop.potion.hp')
  end

  if math.random() > 0.9 then
    local drop_id = go_uid()
    go_write_hash(drop_id, { })
    go_write_geo(drop_id, target.geo)
    go_write_proto_id(drop_id, 'proto.drop.item.sword.1')
  end

  --
  -- Schedule mob respawn
  --
  local initiator_id = go_uid()
  go_write_hash(initiator_id, { })
  -- Can't write geo to the GO directly,
  -- otherwise it would be visible on the map
  go_write_chrs(initiator_id, {
    id = go_read_proto_id(target.id);
    lon = target.geo.lon;
    lat = target.geo.lat;
  })
  go_write_tags(initiator_id, { 'system-initiator' })
  go_schedule_action_initiation(
    assert(target.chrs.respawn_dt),
    'world', initiator_id, 'act.spawn.mob.common'
  )

  --
  -- Remove target object
  --
  go_remove(target.id)
end

ACTIONS['act.remove.common'] = function(target, _)
  go_remove(target.id)
end

ACTIONS['act.die.player.common'] = function(target, _)
  go_remove_tag(target.id, 'user.alive')
  go_add_tag(target.id, 'user.needs-respawn')
  go_block_action(target.id, 'act.die.player.common')
end

ACTIONS['act.potion.drink.common'] = function(target, initiator)
  if target.chrs.ttl and target.chrs.ttl > 0 then
    -- The effect is temporary, create an attachment
    local effect_id = go_uid()
    go_write_hash(effect_id, { })
    go_write_proto_id(effect_id, 'proto.temporary.buff.common')
    go_write_chrs(effect_id, target.chrs)
    go_add_action(effect_id, 'act.remove.common')
    go_action_write_tags(
      effect_id, 'act.remove.common',
      { 'scheduled-initiation-only' }
    )
    go_schedule_action_initiation(
      target.chrs.ttl, effect_id, initiator.id, 'act.remove.common'
    )
    go_attach(initiator.id, effect_id)
  else
    -- The effect is permanent
    for name, value in pairs(target.chrs) do
      if value ~= 0 then
        -- TODO: Respect hp_max
        go_write_chr(
          initiator.id,
          name,
          (tonumber(initiator.chrs[name] or 0) or 0) + value
        )
      end
    end
  end

  -- Remove the potion object
  go_remove(target.id)
end

ACTIONS['act.drop.pickup.common'] = function(target, initiator)
  local item_id = go_uid()
  go_write_proto_id(item_id, target.chrs.id)
  go_write_hash(item_id, { })
  go_write_chrs(item_id, { })
  go_store(initiator.id, item_id)

  -- TODO: Do this only if these actions are available for the new object
  go_block_action(item_id, 'act.doff.common')
  go_unblock_action(item_id, 'act.don.common')

  -- Remove the drop object
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

ACTIONS['act.attack.common'] = function(target, initiator)
  --
  -- 1. Take damage
  --
  target.chrs.hp_cur = target.chrs.hp_cur - initiator.chrs.attack
  go_write_chr(target.id, 'hp_cur', target.chrs.hp_cur)

  --
  -- 2. If dead, generate drop, remove self, initiate respawn
  --
  if target.chrs.hp_cur <= 0 then
    go_unblock_action(target.id, 'act.die.mob.common')
    go_initiate_action(target.id, initiator.id, 'act.die.mob.common')
    return
  end

  --
  -- 3. If alive, deal damage to attacker
  --
  initiator.chrs.hp_cur = initiator.chrs.hp_cur - target.chrs.attack
  go_write_chr(initiator.id, 'hp_cur', initiator.chrs.hp_cur)

  --
  -- 4. If attacker dead, mark attacker as 'needs respawn'
  --
  if initiator.chrs.hp_cur <= 0 then
    -- TODO: Attacker may not always be a player,
    --       in theory it could be another mob.
    go_unblock_action(initiator.id, 'act.die.player.common')
    go_initiate_action(initiator.id, target.id, 'act.die.player.common')
    return
  end
end

ACTIONS['act.user.hq.deploy'] = function(target, initiator)
  assert(go_is_stored(initiator.id, target.id))

  go_unstore(initiator.id, target.id)
  go_remove(target.id)

  local id = go_uid()
  go_write_hash(id, { owner_id = initiator.id })
  go_write_geo(id, initiator.geo)
  go_write_chrs(id, { })
  go_write_proto_id(id, 'proto.user.hq.common')
  go_action_write_tags(
    id, 'act.user.respawn',
    { 'user.id=' .. initiator.id }
  )
  go_action_write_tags(
    id, 'act.user.hq.pack',
    { 'user.id=' .. initiator.id }
  )

  go_add_tag(initiator.id, 'user.has-hq')
end

ACTIONS['act.user.hq.pack'] = function(target, initiator)
  go_remove(target.id)

  local id = go_uid()
  go_write_hash(id, { })
  go_write_chrs(id, { })
  go_write_proto_id(id, 'proto.item.user.hq.common')
  go_store(initiator.id, id)

  go_remove_tag(initiator.id, 'user.has-hq')
end

ACTIONS['act.user.respawn'] = function(_, initiator)
  go_write_chr(initiator.id, 'hp_cur', initiator.chrs.hp_max)
  go_add_tag(initiator.id, 'user.alive')
  go_remove_tag(initiator.id, 'user.needs-respawn')
end

--------------------------------------------------------------------------------

return
{
  ACTIONS = ACTIONS;
}
