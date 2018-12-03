-------------------------------------------------------------------------------
--[[Pipelayer ground penetrating highligther]] --
-------------------------------------------------------------------------------
-- Concept designed and code written by TheStaplergun (staplergun on mod portal)
-- Code revision and adaptation by Zeibach/Therax

local M = {}

--? Bit styled table. 2 ^ defines.direction is used for entry to the table. Only compatible with 4 way directions.
local directional_table = {
  [0x00] = '',
  [0x01] = '-n',
  [0x04] = '-e',
  [0x05] = '-ne',
  [0x10] = '-s',
  [0x11] = '-ns',
  [0x14] = '-se',
  [0x15] = '-nse',
  [0x40] = '-w',
  [0x41] = '-nw',
  [0x44] = '-ew',
  [0x45] = '-new',
  [0x50] = '-sw',
  [0x51] = '-nsw',
  [0x54] = '-sew',
  [0x55] = '-nsew'
}

--? Tables for read-limits
local allowed_types = {
  ['pipe'] = true,
  ['pipe-to-ground'] = true,
  ['storage-tank'] = true,
}

local not_allowed_names = {
  ['factory-fluid-dummy-connector'] = true,
  ['factory-fluid-dummy-connector-south'] = true,
  ['offshore-pump-output'] = true
}

--? Table for types and names to draw dashes between
local draw_dashes_types = {
  ['pipe-to-ground'] = true
}
local draw_dashes_names = {
  ['4-to-4-pipe'] = true
}

local function get_ew(delta_x)
  return delta_x > 0 and defines.direction.west or defines.direction.east
end

local function get_ns(delta_y)
  return delta_y > 0 and defines.direction.north or defines.direction.south
end

--? Gets fourway direction relation based on positions
local abs = math.abs
local function get_direction(entity_position, neighbour_position)
  local delta_x = entity_position.x - neighbour_position.x
  local delta_y = entity_position.y - neighbour_position.y
  if delta_x == 0 then
    return get_ns(delta_y)
  elseif delta_y == 0 then
    return get_ew(delta_x)
  else
    local adx, ady = abs(delta_x), abs(delta_y)
    if adx > ady then
      return get_ew(delta_x)
    else --? Exact diagonal relations get returned as a north/south relation.
      return get_ns(delta_y)
    end
  end
end

--? Destroy markers from player's global data table
local function destroy_markers(markers)
  if markers then
    for _, entity in pairs(markers) do
      if entity.valid then
        entity.destroy()
      end
    end
  end
end

local bor = bit32.bor
local lshift = bit32.lshift
local function highlight_pipelayer_surface(player_index, editor_surface)

  --? Get player and build player's global data table for markers
  local player = game.players[player_index]
  local pdata = global.players[player_index]

  --? Declare working tables
  local read_entity_data = {}
  local all_entities_marked = {}
  local all_markers = {}

  --? Assign working table references to global reference under player
  pdata.current_pipelayer_marker_table = all_markers
  pdata.current_pipelayer_table = all_entities_marked

  --? Setting and cache create entity function
  local max_distance = settings.global['pipelayer-max-distance-checked'].value
  local create = player.surface.create_entity

  --? Variables
  local markers_made = 0

  --? Draws marker at position based on connected directions
  local function draw_marker(position, directions)
    markers_made = markers_made + 1
    all_markers[markers_made] = create{
      name = 'pipelayer-pipe-dot' .. directional_table[directions],
      position = position
    }
  end

  --? Handles drawing dashes between two pipe to ground.
  local function draw_dashes(entity_position, neighbour_position)
    markers_made = markers_made + 1
    all_markers[markers_made] = create{
      name = 'pipelayer-pipe-marker-beam',
      position = entity_position,
      --? Beam source position is off. Have to compensate by shifting down one tile.
      source_position = {entity_position.x, entity_position.y + 1},
      --TODO 0.17 source_position = {entity_position.x, entity_position.y},
      target_position = {neighbour_position.x, neighbour_position.y},
      duration = 2000000000
    }
  end

  local function get_directions(entity_position, entity_neighbours)
    local table_entry = 0
    for _, neighbour_unit_number in pairs(entity_neighbours) do
      local current_neighbour = read_entity_data[neighbour_unit_number]
      if current_neighbour then
        local direction = get_direction(entity_position, current_neighbour[1])
        table_entry = bor(table_entry, lshift(1, direction))
      end
    end
    return table_entry
  end

  --? Construct filter table fed to function below
  local filter = {
    area = {{player.position.x - max_distance, player.position.y - max_distance}, {player.position.x + max_distance, player.position.y + max_distance}},
    type = {'pipe-to-ground', 'pipe', 'storage-tank'},
    force = player.force
  }

  --? Get pipes within filter area and cache them
  for _, entity in pairs(editor_surface.find_entities_filtered(filter)) do
    local entity_unit_number = entity.unit_number
    local entity_position = entity.position
    local entity_neighbours = entity.neighbours[1]
    local entity_type = entity.type
    local entity_name = entity.name

    --? Verify entity is allowed to be stored
    if allowed_types[entity_type] and not not_allowed_names[entity_name] then
      read_entity_data[entity_unit_number] = {
        entity_position,
        entity_neighbours,
        entity_type,
        entity_name
      }
    end

    --? Convert neighbour table to unit number references to gain access to already cached data above at later point
    for neighbour_index_number, neighbour in pairs(entity_neighbours) do
      local neighbour_unit_number = neighbour.unit_number
      entity_neighbours[neighbour_index_number] = neighbour_unit_number
    end
  end

  --? Step through all cached pipes
  for unit_number, current_entity in pairs(read_entity_data) do
    --? Ensure no double marking
    if not all_entities_marked[unit_number] then
      --? Draw dashed beam entity if pipe_to_ground
      if draw_dashes_types[current_entity[3]] or draw_dashes_names[current_entity[4]] then
        for _, neighbour_unit_number in pairs(current_entity[2]) do
          --? Retrieve cached neighbour data
          local current_neighbour = read_entity_data[neighbour_unit_number]
          if current_neighbour then
            --? Ensure it's a valid name or type to draw dashes between. Don't draw dashes between "clamped" pipes (They are pipe to ground entities) and ensure we're not marking towards an already marked entity
            if (draw_dashes_types[current_neighbour[3]] or draw_dashes_names[current_neighbour[4]]) and not string.find(current_neighbour[4], '%-clamped%-') and not all_entities_marked[neighbour_unit_number] then
              draw_dashes(current_entity[1], current_neighbour[1])
            end
          end
        end
      end
      --? Draw a marker on the current entity with lines pointing towards each neighbour (Overlaps beam drawings without an issue)
      draw_marker(current_entity[1], get_directions(current_entity[1], current_entity[2]))
      --? Set current entity as marked
      all_entities_marked[unit_number] = true
    end
  end
end

function M.update_pipelayer_markers(player, editor_surface)
  --? Build player indexed storage location for references in global
  local player_index = player.index
  global.players = global.players or {}
  global.players[player_index] = global.players[player_index] or {}

  --? Get reference to current players data table in global
  local pdata = global.players[player_index]
  pdata.current_pipelayer_marker_table = pdata.current_pipelayer_marker_table or {}

  --? Destroy any existing markers
  if next(pdata.current_pipelayer_marker_table) then
    destroy_markers(pdata.current_pipelayer_marker_table)
    pdata.current_pipelayer_marker_table = nil
  end

  --? This is left in if you want to create a toggle
  --if not pdata.disable_auto_highlight then
    local cursor_item = player.cursor_stack.valid_for_read and player.cursor_stack.name
    if cursor_item and cursor_item == 'pipelayer-connector' then
      highlight_pipelayer_surface(player_index, editor_surface)
    end
  --end
end

return M
