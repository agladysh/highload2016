-- luacheck: globals import ngx

local uuid = require 'resty.jit-uuid'

require 'lua-nucleo.import'

local tstr = import 'lua-nucleo/tstr.lua' { 'tstr' }
local assert_is_string
      = import 'lua-nucleo/typeassert.lua'
      {
        'assert_is_string'
      }
local tset = import 'lua-nucleo/table-utils.lua' { 'tset' }
local redis = import 'redis.lua' { 'redis' }

--------------------------------------------------------------------------------

local ACTIONS = { }

--------------------------------------------------------------------------------

local write_hash = function(redis_id, hash)
  for k, v in pairs(hash) do
    assert(redis():hset(redis_id, k, v)) -- TODO: use hmset, check types
  end
end

local read_hash = function(redis_id)
  local keys = assert(redis():hkeys(redis_id))
  local values = assert(redis():hvals(redis_id))
  local result = { }
  for i = 1, #keys do
    result[keys[i]] = values[i]
  end
  return result
end

local key = function(id, ...)
  return table.concat({
    'go', assert(id, 'missing go key'), ... }, ':', 1, select("#", ...) + 2
  )
end

--------------------------------------------------------------------------------

local go_exists = function(id)
  return assert(redis():exists(key(id))) == 1
end

local go_write_hash = function(id, hash)
  hash.id = hash.id or id
  write_hash(key(id), hash)
end

local go_write_chr = function(id, name, value)
  assert(redis():hset(key(id, 'chrs'), name, value))
end

-- NB: Avoid using this function with data from go_read_chrs,
--     as it will write all chrs to the object itself, including
--     chrs with default values read from the prototype chain.
local go_write_chrs = function(id, chrs)
  for name, value in pairs(chrs) do
    go_write_chr(id, name, value)
  end
end

local go_write_geo = function(id, geo)
  redis():geoadd(
    'world',
    assert(
      assert(geo, 'missing geo').lon
    ),
    assert(geo.lat),
    assert(id)
  )
end

local go_read_geo_pos_raw = function(id)
  local pos = assert(redis():geopos('world', id))
  if not pos or pos == ngx.null or pos[1] == ngx.null then
    return false
  end
  return pos
end

local function go_read_geo_as(id, user_id)
  local pos = go_read_geo_pos_raw(id)
  if not pos then
    if id ~= user_id then
      -- If I see an item without geo,
      -- it is stored in me or attached to me by design
      return go_read_geo_as(user_id, user_id)
    end
    -- If user is without geo, this is probably a system-initiator, not a user.
    -- TODO: This is a hack. Make system-initiator a proper user?
    return { lon = 0, lat = 0 }
  end
  return { lon = pos[1][1], lat = pos[1][2] }
end

local go_list_in_geo_range = function(geo, max_distance)
  return assert(
    redis():georadius(
      'world',
      assert(geo.lon),
      assert(geo.lat),
      assert(max_distance, 'missing max_distance argument'), 'm'
    )
  )
end

local go_has_geo = function(id)
  return not not go_read_geo_pos_raw(id)
end

local go_write_proto_id = function(id, proto_id)
  assert(
    go_exists(assert_is_string(proto_id, 'proto_id')),
    'unknown prototype id'
  )
  assert(not go_has_geo(proto_id))
  assert(redis():hset(key(assert_is_string(id, 'id')), 'proto_id', proto_id))
end

local go_read_hash = function(id)
  return read_hash(key(id))
end

local go_read_proto_id = function(id)
  return assert(redis():hget(key(id), 'proto_id'))
end

local go_attach = function(target_id, attachment_id)
  assert(target_id ~= attachment_id)
  assert(redis():sadd(key(target_id, 'atch'), attachment_id))
end

local go_detach = function(target_id, attachment_id)
  assert(redis():srem(key(target_id, 'atch'), assert(attachment_id)))
end

local go_is_attached = function(target_id, attachment_id)
  return assert(redis():sismember(key(target_id, 'atch'), attachment_id)) == 1
end

local go_read_attachments = function(target_id)
  return assert(redis():smembers(key(target_id, 'atch')))
end

local go_store = function(target_id, item_id)
  assert(target_id ~= item_id)
  assert(redis():sadd(key(target_id, 'stor'), item_id))
end

local go_unstore = function(target_id, item_id)
  assert(redis():srem(key(target_id, 'stor'), item_id))
end

local go_is_stored = function(target_id, item_id)
  return assert(redis():sismember(key(target_id, 'stor'), item_id)) == 1
end

local go_read_storage_as = function(target_id, user_id)
  if target_id ~= user_id then
    return { }
  end
  return assert(redis():smembers(key(target_id, 'stor')))
end

local go_read_chrs_raw = function(id)
  local redis_id = key(id, 'chrs')
  local keys = assert(redis():hkeys(redis_id))
  local values = assert(redis():hvals(redis_id))

  local result = { }
  for i = 1, #keys do
    local value = values[i]
    result[keys[i]] = tonumber(value) or value
  end

  return result
end

local go_read_blocked_actions_raw = function(id)
  return assert(redis():smembers(key(id, 'bact')))
end

-- TODO: Load action chrs too, from correct prototype in the chain
local function go_read_blocked_actions(id, proto_ids)
  proto_ids = proto_ids or { }

  local proto = false

  local proto_id = go_read_proto_id(id)
  if proto_id ~= ngx.null then
    assert(not proto_ids[proto_id])
    proto_ids[proto_id] = true
    proto = go_read_blocked_actions(proto_id)
  end

  local acts = go_read_blocked_actions_raw(id)

  local ids = { } -- TODO: Overhead on recursion. Cache this.
  for i = 1, #acts do
    ids[acts[i]] = true
  end

  if proto then
    for i = 1, #proto do
      if not ids[proto[i]] then
        ids[proto[i]] = true
      end
    end
  end

  return ids
end

local go_action_write_tags = function(id, action_id, tags)
  local tags_key = key(id, 'act', action_id, 'tags')
  for i = 1, #tags do
    assert(redis():sadd(tags_key, tags[i]))
  end
end

local go_action_read_tags = function(id, action_id)
  return assert(redis():smembers(key(id, 'act', action_id, 'tags')))
end

local go_action_have_tags = function(id, action_id, tags)
  local tags_key = key(id, 'act', action_id, 'tags')
  for i = 1, #tags do
    if assert(redis():sismember(tags_key, tags[i])) == 0 then
      return false
    end
  end
  return true
end

local go_write_tags = function(id, tags)
  for i = 1, #tags do
    assert(redis():sadd(key(id, 'tags'), tags[i]))
  end
end

local go_add_tag = function(id, tag)
  assert(redis():sadd(key(assert(id), 'tags'), assert(tag)))
end

local go_remove_tag = function(id, tag)
  assert(redis():srem(key(id, 'tags'), tag))
end

local go_read_tags = function(id)
  return assert(redis():smembers(key(id, 'tags')))
end

local go_have_tags = function(id, tags)
  for i = 1, #tags do
    if assert(redis():sismember(key(id, 'tags'), tags[i])) == 0 then
      return false
    end
  end
  return true
end

local go_read_actions_raw = function(id)
  return assert(redis():smembers(key(id, 'act')))
end

local go_load_as, go_read_chrs

local go_read_distance = function(target_id, initiator_id)
  local result = assert(redis():geodist('world', target_id, initiator_id))
  if result == ngx.null then
    return 0 -- Geo-less object are always in range
  end
  return assert(tonumber(result))
end

local function go_read_actions_as(id, user_id, proto_ids)
  if not proto_ids then
    ngx.log(ngx.DEBUG, 'go_read_actions_as: id: ', id, ' user_id: ', user_id, ' begin')
  end

  -- TODO: Hack, move recursive part into impl() instead,
  --       so it would not be possible to call from outside.
  if not proto_ids then
    if
      id ~= user_id
      and not go_has_geo(id)
      and not go_is_attached(user_id, id)
      and not go_is_stored(user_id, id)
    then
      -- NB: We can act only on geo objects, ourselves
      -- and on our own attached or stored objects.
      -- We can not act on objects that are
      -- stored in or attached to someone (or something) else.
      ngx.log(ngx.DEBUG, 'go_read_actions_as: id: ', id, ' user_id: ', user_id, ' end: no actions, not actionable')
      return { }
    end

    -- TODO: We just read the user object in the caller.
    --       Force callers to pass object instead its id instead.
    local chrs = go_read_chrs(user_id)
    if
      chrs.reach -- No reach means infinite reach.
      and go_read_distance(id, user_id) > chrs.reach
    then
      ngx.log(ngx.DEBUG, 'go_read_actions_as: id: ', id, ' user_id: ', user_id, ' end: no actions, too far away')
      return { } -- Object is out of reach
    end
  end

  proto_ids = proto_ids or { }

  local proto = false

  local proto_id = go_read_proto_id(id)
  if proto_id ~= ngx.null then
    assert(not proto_ids[proto_id])
    proto_ids[proto_id] = true
    proto = go_read_actions_as(proto_id, user_id, proto_ids)
  end

  local acts = { }
  do
     local acts_raw = go_read_actions_raw(id)
     for i = 1, #acts_raw do
       -- TODO: Do this on the redis set level instead.
       if go_have_tags(user_id, go_action_read_tags(id, acts_raw[i])) then
         acts[#acts + 1] = acts_raw[i]
       else
         ngx.log(ngx.DEBUG, 'go_read_actions_as: id: ', id, ' user_id: ', user_id, ' action ', acts_raw[i], ' denied: tags')
       end
     end
  end
  if proto then
    local ids = { } -- TODO: Overhead on recursion. Cache this.
    for i = 1, #acts do
      ids[acts[i]] = true
    end

    for i = 1, #proto do
      if
        not ids[proto[i]]
        -- NB: Current object might have tags for this action too
        and go_have_tags(user_id, go_action_read_tags(id, proto[i]))
      then
        ids[proto[i]] = true
        acts[#acts + 1] = proto[i]
      else
        ngx.log(ngx.DEBUG, 'go_read_actions_as: id: ', id, ' user_id: ', user_id, ' proto action ', proto[i], ' denied: tags')
      end
    end
  end

  local result = { }
  local blocked = go_read_blocked_actions(id)
  -- TODO: Overhead. Don't iterate over acts so many times.
  for i = 1, #acts do
    if not blocked[acts[i]] then
      result[#result + 1] = acts[i]
    else
      ngx.log(ngx.DEBUG, 'go_read_actions_as: id: ', id, ' user_id: ', user_id, ' action ', acts[i], ' denied: blocked')
    end
  end

  ngx.log(ngx.DEBUG, 'go_read_actions_as: id: ', id, ' user_id: ', user_id, ' end: ', tstr(result))

  return result
end

go_read_chrs = function(id, proto_ids)
  proto_ids = proto_ids or { }

  local proto = false

  local proto_id = go_read_proto_id(id)
  if proto_id ~= ngx.null then
    assert(not proto_ids[proto_id])
    proto_ids[proto_id] = true
    proto = go_read_chrs(proto_id)
  end

  local chrs = go_read_chrs_raw(id)
  if proto then
    -- NB: Not using metatables since we want pairs to iterate over all values
    for k, v in pairs(proto) do
      if chrs[k] == nil then
        chrs[k] = v
      end
    end
  end

  -- TODO: Handle attachments too!
  local attachments = go_read_attachments(id)
  for i = 1, #attachments do
    local attachment_id = attachments[i]
    if not go_exists(attachment_id) then
      -- Probably expired
      go_detach(id, attachment_id)
    else
      local attached = go_read_chrs(attachment_id)
      for k, v in pairs(attached) do
        -- TODO: Respect hp_max
        chrs[k] = (chrs[k] or 0) + v
      end
    end
  end

  return chrs
end

go_load_as = function(id, user_id, geo)
  geo = geo or go_read_geo_as(id, user_id)

  local acts = go_read_actions_as(id, user_id)
  for i = 1, #acts do
    local action_id = acts[i]
    -- TODO: Escape url
    acts[i] =
    {
      id = action_id;
      url = '/go/' .. id .. '/act/' .. action_id;
    }
  end

  -- TODO: Protect from cyclic storage loops (a -> b -> a etc.)
  local stored = { }
  do
    -- NB: Storage is visible only for user himself
    local storage = go_read_storage_as(id, user_id)
    for i = 1, #storage do
      if go_exists(storage[i]) then
        stored[#stored + 1] = go_load_as(storage[i], user_id, geo)
      else
        go_unstore(id, storage[i])
      end
    end
  end

  -- TODO: Protect from cyclic storage loops (a -> b -> a etc.)
  local attached = { }
  do
    -- NB: Attachments are visible for everyone
    local attachments = go_read_attachments(id)
    for i = 1, #attachments do
      if go_exists(attachments[i]) then
        attached[#attached + 1] = go_load_as(attachments[i], user_id, geo)
      else
        go_detach(id, attachments[i])
      end
    end
  end

  return
  {
    id = id;
    hash = go_read_hash(id);
    geo = geo;
    chrs = go_read_chrs(id);
    acts = acts;
    stored = stored;
    attached = attached;
    tags = go_read_tags(id);
    -- TODO: Overhead. We already calculated that
    --       when checked visibility and actability.
    distance = go_read_distance(id, user_id);
  }
end

local go_remove = function(id)
  -- Not deleting actions from prototypes above the chain
  local actions = go_read_actions_raw(id)

  -- Remove hash
  assert(redis():del(key(id)))

  -- Remove geo
  assert(redis():zrem('world', id))

  for i = 1, #actions do
    -- Remove each action tags
    redis():del(key(id, 'act', actions[i], 'tags'))
  end

  -- Remove action list
  assert(redis():del(key(id, 'act')))

  -- Remove chrs
  assert(redis():del(key(id, 'chrs')))

  -- Remove attachments
  assert(redis():del(key(id, 'atch')))

  -- Remove storage
  assert(redis():del(key(id, 'stor')))

  -- Remove tags
  assert(redis():del(key(id, 'tags')))
end

local go_have_action_as = function(id, action_id, user_id)
  if not ACTIONS[action_id] then
    error('unknown action `' .. tostring(action_id) .. '`', 2)
  end
  -- NB: Overhead due to action derivation
  return not not tset(go_read_actions_as(id, user_id))[action_id]
end

local go_initiate_action = function(target_id, initiator_id, action_id)
  -- TODO: Ensure the target exists and has this action (taking in account prototype chain)
  -- TODO: Ensure initiator exists and has permissions to initiate the action
  -- TODO: Pass the action hash too (make sure to read it from the whole chain)
  if not go_have_action_as(target_id, action_id, initiator_id) then
    error(
      'action `' .. tostring(action_id) .. '`is not available on `'
      .. tostring(target_id) .. '` for `' .. tostring(initiator_id),
      2
    )
  end

  local handler = ACTIONS[action_id]
  if not handler then
    error('unknown action id `' .. tostring(action_id) .. '`', 2)
  end
  handler(go_load_as(target_id, initiator_id), go_load_as(initiator_id, initiator_id))
end

local go_add_action = function(id, action_id)
  if not ACTIONS[action_id] then
    error('unknown action `' .. tostring(action_id) .. '`', 2)
  end
  assert(redis():sadd(key(id, 'act'), action_id))
end

local go_remove_action = function(id, action_id)
  -- NB: This will NOT remove the action from any of the id's prototypes
  assert(redis():srem(key(id, 'act'), action_id))
end

local go_block_action = function(id, action_id)
  assert(redis():sadd(key(id, 'bact'), action_id))
end

local go_unblock_action = function(id, action_id)
  assert(redis():srem(key(id, 'bact'), action_id))
end

local go_uid = function()
  return uuid():gsub('%-', '')
end

local go_schedule_action_initiation = function(
  delay,
  target_id,
  initiator_id,
  action_id
)
  assert(delay > 0) -- Otherwise the run algorithm will not be stable
  assert(ACTIONS[action_id])
  local id = go_uid()
  write_hash(
    'da:' .. id,
    {
      id = action_id;
      target_id = target_id;
      initiator_id = initiator_id;
    }
  )
  assert(redis():zadd('da', math.ceil(os.time() + delay), id))
end

local go_initiate_scheduled_actions = function()
  local timestamp = os.time()
  local actions = assert(redis():zrangebyscore('da', '-inf', timestamp))
  for i = 1, #actions do
    local action_key = 'da:' .. actions[i]
    local action = read_hash(action_key)
    assert(redis():del(action_key))
    -- TODO: Hack. Not exception-safe, race-condition prone.
    go_add_tag(
      assert(action.initiator_id, 'missing scheduled action initiator id'),
      'scheduled-initiation-only'
    )
    go_initiate_action(
      assert(action.target_id),
      action.initiator_id,
      assert(action.id)
    )
    go_remove_tag(action.initiator_id, 'scheduled-initiation-only')
  end
  assert(redis():zremrangebyscore('da', '-inf', timestamp))
end

--------------------------------------------------------------------------------

return
{
  ACTIONS = ACTIONS;
  --
  go_uid = go_uid;
  go_exists = go_exists;
  go_write_hash = go_write_hash;
  go_write_chr = go_write_chr;
  go_write_chrs = go_write_chrs;
  go_write_proto_id = go_write_proto_id;
  go_read_hash = go_read_hash;
  go_read_proto_id = go_read_proto_id;
  go_read_chrs_raw = go_read_chrs_raw;
  go_read_chrs = go_read_chrs;
  go_read_actions_raw = go_read_actions_raw;
  go_read_actions_as = go_read_actions_as;
  go_attach = go_attach;
  go_detach = go_detach;
  go_is_attached = go_is_attached;
  go_read_attachments = go_read_attachments;
  go_load_as = go_load_as;
  go_remove = go_remove;
  go_initiate_action = go_initiate_action;
  go_add_action = go_add_action;
  go_have_action_as = go_have_action_as;
  go_remove_action = go_remove_action;
  go_schedule_action_initiation = go_schedule_action_initiation;
  go_initiate_scheduled_actions = go_initiate_scheduled_actions;
  go_store = go_store;
  go_unstore = go_unstore;
  go_is_stored = go_is_stored;
  go_read_storage_as = go_read_storage_as;
  go_block_action = go_block_action;
  go_unblock_action = go_unblock_action;
  go_action_write_tags = go_action_write_tags;
  go_action_read_tags = go_action_read_tags;
  go_action_have_tags = go_action_have_tags;
  go_write_tags = go_write_tags;
  go_add_tag = go_add_tag;
  go_remove_tag = go_remove_tag;
  go_read_tags = go_read_tags;
  go_have_tags = go_have_tags;
  go_write_geo = go_write_geo;
  go_read_geo_as = go_read_geo_as;
  go_read_distance = go_read_distance;
  go_list_in_geo_range = go_list_in_geo_range;
}
