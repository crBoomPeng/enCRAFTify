if isClient() then return end

---------------------------------------------------------
-- Debugging
---------------------------------------------------------
local DEBUG_ENABLED = true
local function logDebug(message)
    if DEBUG_ENABLED then
        print("[enCRAFTify StationMapper] " .. tostring(message))
    end
end

---------------------------------------------------------
-- Helpers
---------------------------------------------------------
local function getSpriteName(squareObject)
    local sprite = squareObject and squareObject:getSprite()
    return sprite and sprite:getName() or nil
end

---------------------------------------------------------
-- NW-normalized Station Patterns
---------------------------------------------------------
local stationPatterns = {
    Industry_Lathe = {
        entity = "Industry_Lathe",
        facings = {
            S = { ["0,0"] = "industry_03_3",  ["1,0"] = "industry_03_4",  ["2,0"] = "industry_03_5"  },
            E = { ["0,0"] = "industry_03_2",  ["0,1"] = "industry_03_1",  ["0,2"] = "industry_03_0"  },
            N = { ["0,0"] = "industry_03_8",  ["1,0"] = "industry_03_9",  ["2,0"] = "industry_03_10" },
            W = { ["0,0"] = "industry_03_13", ["0,1"] = "industry_03_12", ["0,2"] = "industry_03_11" },
        },
    },

    Industry_Lathe_2 = {
        entity = "Industry_Lathe_2",
        facings = {
            S = { ["0,0"] = "industry_03_35", ["1,0"] = "industry_03_36", ["2,0"] = "industry_03_37" },
            E = { ["0,0"] = "industry_03_34", ["0,1"] = "industry_03_33", ["0,2"] = "industry_03_32" },
            N = { ["0,0"] = "industry_03_40", ["1,0"] = "industry_03_41", ["2,0"] = "industry_03_42" },
            W = { ["0,0"] = "industry_03_45", ["0,1"] = "industry_03_44", ["0,2"] = "industry_03_43" },
        },
    },

    Industry_DrillPress = {
        entity = "Industry_DrillPress",
        facings = {
            S = { ["0,0"] = "industry_02_269" },
            E = { ["0,0"] = "industry_02_268" },
            N = { ["0,0"] = "industry_02_270" },
            W = { ["0,0"] = "industry_02_271" },
        },
    },
}

---------------------------------------------------------
-- Sprite → Pattern Lookup (O(1))
---------------------------------------------------------
local spritePatternLookup = {}

for stationType, stationPattern in pairs(stationPatterns) do
    for facing, patternTiles in pairs(stationPattern.facings) do
        for tileOffsetKey, spriteName in pairs(patternTiles) do
            local offsetX, offsetY = tileOffsetKey:match("([^,]+),(.+)")
            offsetX, offsetY = tonumber(offsetX), tonumber(offsetY)

            spritePatternLookup[spriteName] = {
                stationType = stationType,
                facing = facing,
                offsetX = offsetX,
                offsetY = offsetY,
            }
        end
    end
end

---------------------------------------------------------
-- Already-converted Guard
---------------------------------------------------------
local stationNames = {}
for stationType, _ in pairs(stationPatterns) do
    stationNames[stationType] = true
end

local function squareHasStationEntity(gridSquare)
    if not gridSquare then return false end
    local squareObjects = gridSquare:getObjects()

    for i = 0, squareObjects:size() - 1 do
        local squareObject = squareObjects:get(i)
        if squareObject.getEntity then
            local entity = squareObject:getEntity()
            if entity and entity.getName and stationNames[entity:getName()] then
                return true
            end
        end
    end
    return false
end

---------------------------------------------------------
-- Pattern Verification
---------------------------------------------------------
local function verifyPattern(originX, originY, originZ, stationType, facing)
    local stationPattern = stationPatterns[stationType]
    local patternTiles = stationPattern.facings[facing]

    for tileOffsetKey, expectedSpriteName in pairs(patternTiles) do
        local offsetX, offsetY = tileOffsetKey:match("([^,]+),(.+)")
        offsetX, offsetY = tonumber(offsetX), tonumber(offsetY)

        local gridSquare = getCell():getGridSquare(originX + offsetX, originY + offsetY, originZ)
        if not gridSquare then return false end

        local squareObjects = gridSquare:getObjects()
        local found = false

        for i = 0, squareObjects:size() - 1 do
            if getSpriteName(squareObjects:get(i)) == expectedSpriteName then
                found = true
                break
            end
        end

        if not found then return false end
    end

    return true
end

---------------------------------------------------------
-- Pattern Replacement
---------------------------------------------------------
local function replacePattern(originX, originY, originZ, stationType, facing)
    local stationPattern = stationPatterns[stationType]
    local patternTiles = stationPattern.facings[facing]

    logDebug("Ersetze Muster durch Entity: " .. stationType .. " facing=" .. facing)

    local removedTiles = {}

    for tileOffsetKey, expectedSpriteName in pairs(patternTiles) do
        local offsetX, offsetY = tileOffsetKey:match("([^,]+),(.+)")
        offsetX, offsetY = tonumber(offsetX), tonumber(offsetY)

        local gridSquare = getCell():getGridSquare(originX + offsetX, originY + offsetY, originZ)
        if gridSquare then
            local squareObjects = gridSquare:getObjects()

            for i = squareObjects:size() - 1, 0, -1 do
                local spriteName = getSpriteName(squareObjects:get(i))
                if spriteName == expectedSpriteName then
                    local removedObjectIndex = gridSquare:transmitRemoveItemFromSquare(squareObjects:get(i))

                    removedTiles[#removedTiles+1] = {
                        offsetX = offsetX,
                        offsetY = offsetY,
                        spriteName = spriteName,
                        originalObjectIndex = removedObjectIndex,
                    }

                    break
                end
            end
        end
    end

    if #removedTiles == 0 then
        logDebug("Keine Tiles entfernt — Abbruch")
        return
    end

    spawnEntityFromPattern(originX, originY, originZ, stationType, facing, removedTiles)
end

---------------------------------------------------------
-- Entity Spawning
---------------------------------------------------------
function spawnEntityFromPattern(originX, originY, originZ, stationType, facing, removedTiles)
    local stationPattern = stationPatterns[stationType]

    local entityModule = ScriptManager.instance:getModule("enCRAFTify")
    if not entityModule then
        logDebug("Modul enCRAFTify nicht gefunden")
        return
    end

    local entityTemplate = nil
    local allEntities = ScriptManager.instance:getAllGameEntities()

    for i = 0, allEntities:size() - 1 do
        local script = allEntities:get(i)
        if script and script.getScriptObjectFullType and script:getScriptObjectFullType() == "enCRAFTify." .. stationPattern.entity then
            entityTemplate = script
            break
        end
    end

    if not entityTemplate then
        logDebug("EntityTemplate nicht gefunden: " .. stationPattern.entity)
        return
    end

    logDebug("EntityTemplate " .. stationPattern.entity .. " gefunden: ")
    local isNorthOrSouthFacing = (facing == "N" or facing == "S")
    local primaryThumpable = nil

    for _, removedTileData in ipairs(removedTiles) do
        local gridSquare = getCell():getGridSquare(originX + removedTileData.offsetX, originY + removedTileData.offsetY, originZ)
        if gridSquare then
            local thumpableObject = IsoThumpable.new(getCell(), gridSquare, removedTileData.spriteName, isNorthOrSouthFacing, nil)

            if removedTileData.originalObjectIndex and removedTileData.originalObjectIndex >= 0 then
                gridSquare:AddSpecialObject(thumpableObject, removedTileData.originalObjectIndex)
            else
                gridSquare:AddSpecialObject(thumpableObject)
            end

            if not primaryThumpable or (removedTileData.offsetX == 0 and removedTileData.offsetY == 0) then
                primaryThumpable = thumpableObject
            end

            if isServer() then
                thumpableObject:transmitCompleteItemToClients()
            end
        end
    end

    if not primaryThumpable then
        logDebug("Zentraler Thumpable nicht gefunden — Abbruch")
        return
    end

    GameEntityFactory.CreateIsoObjectEntity(primaryThumpable, entityTemplate, true)

    for _, removedTileData in ipairs(removedTiles) do
        local gridSquare = getCell():getGridSquare(originX + removedTileData.offsetX, originY + removedTileData.offsetY, originZ)
        if gridSquare then
            gridSquare:RecalcAllWithNeighbours(true)
        end
    end
end

---------------------------------------------------------
-- Square Processing
---------------------------------------------------------
local function processGridSquare(gridSquare)
    if not gridSquare then return end

    local sqX, sqY, sqZ = gridSquare:getX(), gridSquare:getY(), gridSquare:getZ()
    local squareObjects = gridSquare:getObjects()

    for i = 0, squareObjects:size() - 1 do
        local spriteName = getSpriteName(squareObjects:get(i))
        if spriteName then
            local spriteLookupEntry = spritePatternLookup[spriteName]
            if spriteLookupEntry then
                local stationType = spriteLookupEntry.stationType
                local facing = spriteLookupEntry.facing
                local offsetX = spriteLookupEntry.offsetX
                local offsetY = spriteLookupEntry.offsetY

                local originX = sqX - offsetX
                local originY = sqY - offsetY

                logDebug("Sprite erkannt: " .. spriteName .. " → " .. stationType .. " facing=" .. facing)

                if verifyPattern(originX, originY, sqZ, stationType, facing) then
                    replacePattern(originX, originY, sqZ, stationType, facing)
                end
            end
        end
    end
end

---------------------------------------------------------
-- Event Hooks
---------------------------------------------------------
Events.LoadGridsquare.Add(processGridSquare)
Events.OnObjectAdded.Add(function(squareObject)
    processGridSquare(squareObject:getSquare())
end)

logDebug("StationMapper geladen (Final Version, 42.18-kompatibel)")
