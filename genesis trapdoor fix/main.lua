local mod = RegisterMod('Genesis Trapdoor Fix', 1)
local json = require('json')
local game = Game()

mod.onGameStartHasRun = false

mod.state = {}
mod.state.spawnStairsGenesis = false
mod.state.spawnStairsError = false
mod.state.spawnStairsMarket = false

function mod:onGameStart()
  if mod:HasData() then
    local _, state = pcall(json.decode, mod:LoadData())
    
    if type(state) == 'table' then
      for _, v in ipairs({ 'spawnStairsGenesis', 'spawnStairsError', 'spawnStairsMarket' }) do
        if type(state[v]) == 'boolean' then
          mod.state[v] = state[v]
        end
      end
    end
  end
  
  mod.onGameStartHasRun = true
  mod:onNewRoom()
end

function mod:onGameExit()
  mod:save()
  mod.onGameStartHasRun = false
end

function mod:save()
  mod:SaveData(json.encode(mod.state))
end

function mod:onNewRoom()
  if not mod.onGameStartHasRun then
    return
  end
  
  local level = game:GetLevel()
  local room = level:GetCurrentRoom()
  local roomDesc = level:GetCurrentRoomDesc()
  local stage = level:GetStage()
  local stageType = level:GetStageType()
  
  if (
       (room:GetType() == RoomType.ROOM_ISAACS and (roomDesc.GridIndex == GridRooms.ROOM_DEVIL_IDX or roomDesc.Data.Subtype == 99)) or -- genesis room
       room:GetType() == RoomType.ROOM_ERROR or -- error room, ROOM_ERROR_IDX/ROOM_DEBUG_IDX
       room:GetType() == RoomType.ROOM_BLACK_MARKET -- black market, ROOM_BLACK_MARKET_IDX/ROOM_DEBUG_IDX
     ) and
     room:IsFirstVisit()
  then
    local spawnStairs
    if room:GetType() == RoomType.ROOM_ERROR then
      spawnStairs = mod.state.spawnStairsError
    elseif room:GetType() == RoomType.ROOM_BLACK_MARKET then
      spawnStairs = mod.state.spawnStairsMarket
    else
      spawnStairs = mod.state.spawnStairsGenesis
    end
    
    local heavenDoors = Isaac.FindByType(EntityType.ENTITY_EFFECT, EffectVariant.HEAVEN_LIGHT_DOOR, 0, false, false)
    local trapdoors = mod:getTrapdoors() -- ignore void portals and stairs
    
    while #heavenDoors + #trapdoors > 0 do
      local heavenDoor = table.remove(heavenDoors)
      local trapdoor = table.remove(trapdoors)
      local gridIdx = heavenDoor and room:GetGridIndex(heavenDoor.Position) or trapdoor:GetGridIndex()
      
      if spawnStairs then
        mod:removeEntities(heavenDoor, nil)
        mod:spawnStairs(gridIdx) -- we can spawn stairs directly over a trapdoor
      elseif not game:IsGreedMode() and
             (
               ( -- womb/utero/scarred womb ii/xl, ???
                 (stage == LevelStage.STAGE4_2 or (mod:isCurseOfTheLabyrinth() and stage == LevelStage.STAGE4_1)) and
                 (stageType == StageType.STAGETYPE_ORIGINAL or stageType == StageType.STAGETYPE_WOTL or stageType == StageType.STAGETYPE_AFTERBIRTH)
               ) or
               stage == LevelStage.STAGE4_3
             )
      then
        -- flips to true when you take a heaven door, doesn't flip back to false when you take a trapdoor
        game:SetStateFlag(GameStateFlag.STATE_HEAVEN_PATH, false)
        mod:removeEntities(nil, trapdoor)
        mod:spawnTrapdoorAndHeavenDoor(heavenDoor, gridIdx - 1, gridIdx + 1)
      end
    end
  end
end

function mod:getTrapdoors()
  local room = game:GetRoom()
  local gridEntities = {}
  
  for i = 0, room:GetGridSize() - 1 do
    local gridEntity = room:GetGridEntity(i)
    
    -- exclude void portals
    if gridEntity and gridEntity:GetType() == GridEntityType.GRID_TRAPDOOR and gridEntity:GetVariant() == 0 then
      table.insert(gridEntities, gridEntity)
    end
  end
  
  return gridEntities
end

function mod:removeEntities(entity, gridEntity)
  if entity then
    entity:Remove()
  end
  
  if gridEntity then
    mod:removeGridEntity(gridEntity:GetGridIndex(), 0, false, false)
  end
end

function mod:spawnStairs(gridIdx)
  mod:spawnGridEntity(GridEntityType.GRID_STAIRS, 3, gridIdx)
end

function mod:spawnTrapdoorAndHeavenDoor(entity, gridIdxLeft, gridIdxRight)
  local room = game:GetRoom()
  
  mod:spawnGridEntity(GridEntityType.GRID_TRAPDOOR, 0, gridIdxLeft)
  
  if entity then
    entity.Position = room:GetGridPosition(gridIdxRight)
  else
    Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.HEAVEN_LIGHT_DOOR, 0, room:GetGridPosition(gridIdxRight), Vector.Zero, nil)
  end
end

function mod:spawnGridEntity(gridEntityType, gridEntityVariant, gridIdx)
  local room = game:GetRoom()
  
  local gridEntity = Isaac.GridSpawn(gridEntityType, gridEntityVariant, room:GetGridPosition(gridIdx), true)
  if gridEntity:GetType() ~= gridEntityType then
    mod:removeGridEntity(gridIdx, 0, false, true)
    Isaac.GridSpawn(gridEntityType, gridEntityVariant, room:GetGridPosition(gridIdx), true)
  end
end

function mod:removeGridEntity(gridIdx, pathTrail, keepDecoration, update)
  local room = game:GetRoom()
  
  if REPENTOGON then
    room:RemoveGridEntityImmediate(gridIdx, pathTrail, keepDecoration)
  else
    room:RemoveGridEntity(gridIdx, pathTrail, keepDecoration)
    if update then
      room:Update()
    end
  end
end

function mod:isCurseOfTheLabyrinth()
  local level = game:GetLevel()
  local curses = level:GetCurses()
  local curse = LevelCurse.CURSE_OF_LABYRINTH
  
  return curses & curse == curse
end

-- start ModConfigMenu --
function mod:setupModConfigMenu()
  local category = 'Genesis Trapdoor' -- Fix
  for _, v in ipairs({ 'Settings' }) do
    ModConfigMenu.RemoveSubcategory(category, v)
  end
  for i, v in ipairs({
                      { title = 'Genesis'     , field = 'spawnStairsGenesis' },
                      { title = 'I Am Error'  , field = 'spawnStairsError' },
                      { title = 'Black Market', field = 'spawnStairsMarket' },
                    })
  do
    if i ~= 1 then
      ModConfigMenu.AddSpace(category, 'Settings')
    end
    ModConfigMenu.AddTitle(category, 'Settings', v.title)
    ModConfigMenu.AddSetting(
      category,
      'Settings',
      {
        Type = ModConfigMenu.OptionType.BOOLEAN,
        CurrentSetting = function()
          return mod.state[v.field]
        end,
        Display = function()
          return mod.state[v.field] and 'Spawn stairs back to starting room' or 'Spawn both in womb/utero/???'
        end,
        OnChange = function(b)
          mod.state[v.field] = b
          mod:save()
        end,
        Info = { 'Both: trapdoor + heaven door', 'Stairs: instead of trapdoor or heaven door' }
      }
    )
  end
end
-- end ModConfigMenu --

mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, mod.onGameStart)
mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, mod.onGameExit)
mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, mod.onNewRoom)

if ModConfigMenu then
  mod:setupModConfigMenu()
end