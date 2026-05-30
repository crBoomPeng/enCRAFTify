-- enCRAFTify Lathe UI Status Display
-- Client-seitige UI für Stromstatus der Lathe
-- HINWEIS: Nur zur Information! Server-seitige Validierung erfolgt in LatheValidation.lua

LatheUI = {}
local self = LatheUI

self.config = {
    enabled = true,
    log = false,
    latheEntityNames = {
        "Industry_Lathe",
        "Industry_Lathe_2"
    }
}

local function log(msg)
    if self.config.log then
        print("[enCRAFTify LatheUI] " .. tostring(msg))
    end
end

local function getEntityNameSafe(obj)
    if not obj then return nil end

    -- 1) EntityScript (für entity Industry_Lathe)
    if obj.getEntity then
        local ent = obj:getEntity()
        if ent and ent.getName then
            local ok, name = pcall(ent.getName, ent)
            if ok and name and name ~= "" then
                return name
            end
        end
    end

    -- 2) IsoObject
    if obj.getObjectName then
        local ok, name = pcall(obj.getObjectName, obj)
        if ok and name and name ~= "" then
            return name
        end
    end

    -- 3) InventoryItem / andere Typen
    if obj.getName then
        local ok, name = pcall(obj.getName, obj)
        if ok and name and name ~= "" then
            return name
        end
    end

    return nil
end

-- Sichere Prüfung ob Entity eine Lathe ist
function self.isLatheBench(obj)
    local entityName = getEntityNameSafe(obj)
    if not entityName then return false end

    for _, name in ipairs(self.config.latheEntityNames) do
        if entityName == name then
            return true
        end
    end

    return false
end

-- Sichere Prüfung ob Lathe Strom hat (nur Client-Info)
function self.latheHasPower(lathe)
    if not lathe or not lathe.getSquare then return false end

    local ok, sq = pcall(function() return lathe:getSquare() end)
    if not ok or not sq then return false end

    -- Prüfe Elektrizität
    if sq.haveElectricity then
        local ok2, hasElectricity = pcall(function() return sq:haveElectricity() end)
        if ok2 and hasElectricity then return true end
    end

    -- Prüfe Generator
    if sq.isPoweredByGenerator then
        local ok3, hasGenerator = pcall(function() return sq:isPoweredByGenerator() end)
        if ok3 and hasGenerator then return true end
    end

    return false
end

-- Hauptevent: Fülle WorldObject Context Menu (INFORMATIV)
-- Server-seitige Validierung erfolgt in LatheValidation.lua
if Events.OnFillWorldObjectContextMenu then
    Events.OnFillWorldObjectContextMenu.Add(function(player, context, worldobjects)
        if not self.config.enabled then
            return
        end
        
        for _, obj in ipairs(worldobjects) do
            if self:isLatheBench(obj) then
                local hasPower = self:latheHasPower(obj)
                local success, entityName = pcall(function() return obj:getEntityName() end)
                if not success then entityName = "Lathe" end
                
                if hasPower then
                    -- Grüner Status - Lathe ist bereit
                    context:addOption(entityName .. " [✓ Betriebsbereit]", nil, nil)
                    log("Lathe has power")
                else
                    -- Roter Status - Kein Strom
                    context:addOption(entityName .. " [✗ Kein Strom]", nil, nil)
                    log("Lathe needs electricity")
                end
                
                break  -- Nur erste Lathe im Stack anzeigen
            end
        end
    end)
end

-- Initialisierung
function self.init()
    log("LatheUI initialized - Client-seitige Anzeige nur)")
end

self.init()
