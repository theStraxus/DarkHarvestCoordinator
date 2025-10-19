-- DarkHarvestCoordinator.lua
-- Addon for coordinating Warlock Dark Harvest rotation in Turtle WoW

local addonName = "DHC"
local addonVersion = "1.0"
local DARK_HARVEST_COOLDOWN = 30 -- 30 seconds in Turtle WoW

-- Data structures
local DHC = {
    warlocks = {}, -- List of warlocks in raid with their data
    rotation = {}, -- Ordered list of warlock names in rotation
    currentIndex = 1,
    lastCastTime = 0,
    rotationEnabled = false,
    frame = nil,
    debugMode = false, -- Debug mode disabled by default
    notifyMode = false, -- Notify mode disabled by default
    lastAlertTime = 0, -- Track last time we alerted player
    wasReady = false, -- Track if player was ready last update
    fullLogMode = false, -- Full event logging mode
}

-- Helper function to check if a unit is dead
local function IsUnitDead(unitName)
    if unitName == UnitName("player") then
        return UnitIsDead("player") or UnitIsGhost("player")
    end
    
    -- Check raid members
    local numRaid = GetNumRaidMembers()
    if numRaid > 0 then
        for i = 1, numRaid do
            local name = GetRaidRosterInfo(i)
            if name == unitName then
                local unitID = "raid" .. i
                return UnitIsDead(unitID) or UnitIsGhost(unitID)
            end
        end
    end
    
    -- Check party members
    local numParty = GetNumPartyMembers()
    if numParty > 0 then
        for i = 1, numParty do
            local unitID = "party" .. i
            if UnitName(unitID) == unitName then
                return UnitIsDead(unitID) or UnitIsGhost(unitID)
            end
        end
    end
    
    return false
end
-- Helper function to check if player has Dark Harvest
local function HasDarkHarvest(playerName)
    -- Can only check our own spellbook
    if playerName == UnitName("player") then
        local i = 1
        while true do
            local spellName, spellRank = GetSpellName(i, BOOKTYPE_SPELL)
            if not spellName then
                break
            end
            if string.find(spellName, "Dark Harvest") then
                return true
            end
            i = i + 1
        end
        return false
    else
        -- For other players, assume they have it (can't check remotely)
        return true
    end
end

-- Create main frame
local f = CreateFrame("Frame", "DHCFrame", UIParent)
f:SetWidth(320)
f:SetHeight(220)
f:SetPoint("CENTER", 0, 0)
f:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 }
})
f:SetMovable(true)
f:EnableMouse(true)
f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart", function()
    this:StartMoving()
end)
f:SetScript("OnDragStop", function()
    this:StopMovingOrSizing()
end)
f:Hide()

-- Title
local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", 0, -20)
title:SetText("Dark Harvest Coordinator")

-- Status text
local statusText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
statusText:SetPoint("TOP", 0, -45)
statusText:SetText("Initializing...")

-- Warlock list display (with DH)
local warlockList = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
warlockList:SetPoint("TOPLEFT", 15, -70)
warlockList:SetJustifyH("LEFT")
warlockList:SetWidth(145)
warlockList:SetText("")

-- Warlock list without DH
local warlockListNoDH = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
warlockListNoDH:SetPoint("TOPRIGHT", -15, -70)
warlockListNoDH:SetJustifyH("LEFT")
warlockListNoDH:SetWidth(145)
warlockListNoDH:SetText("")

-- Next in rotation display
local nextText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
nextText:SetPoint("BOTTOM", 0, 40)
nextText:SetTextColor(1, 0.8, 0)
nextText:SetText("")

-- Close button
local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", -5, -5)

-- Manual cast button
local castBtn = CreateFrame("Button", "DHCCastBtn", f, "GameMenuButtonTemplate")
castBtn:SetPoint("BOTTOM", 0, 15)
castBtn:SetWidth(120)
castBtn:SetHeight(25)
castBtn:SetText("I Cast It!")
castBtn:SetScript("OnClick", function()
    DHC.ManualCast(DHC)
end)

DHC.frame = f

-- Event frame for monitoring
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("CHAT_MSG_ADDON")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("UNIT_HEALTH")
eventFrame:RegisterEvent("PLAYER_DEAD")
eventFrame:RegisterEvent("PLAYER_ALIVE")
eventFrame:RegisterEvent("PLAYER_UNGHOST")
eventFrame:RegisterEvent("UNIT_SPELLCAST_SENT")
eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
eventFrame:RegisterEvent("UNIT_SPELLCAST_STOP")
eventFrame:RegisterEvent("UNIT_SPELLCAST_FAILED")
eventFrame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE")
eventFrame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE")
eventFrame:RegisterEvent("CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE")
eventFrame:RegisterEvent("CHAT_MSG_SPELL_CREATURE_DAMAGE")
-- Register for ALL CHAT_MSG_COMBAT and CHAT_MSG_SPELL events
eventFrame:RegisterEvent("CHAT_MSG_COMBAT_SELF_HITS")
eventFrame:RegisterEvent("CHAT_MSG_COMBAT_SELF_MISSES")
eventFrame:RegisterEvent("CHAT_MSG_COMBAT_PARTY_HITS")
eventFrame:RegisterEvent("CHAT_MSG_COMBAT_PARTY_MISSES")
eventFrame:RegisterEvent("CHAT_MSG_COMBAT_FRIENDLYPLAYER_HITS")
eventFrame:RegisterEvent("CHAT_MSG_COMBAT_FRIENDLYPLAYER_MISSES")
eventFrame:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS")
eventFrame:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES")
eventFrame:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")
eventFrame:RegisterEvent("CHAT_MSG_SPELL_SELF_BUFF")
eventFrame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS")
eventFrame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE")
eventFrame:RegisterEvent("CHAT_MSG_SPELL_AURA_GONE_SELF")
eventFrame:RegisterEvent("CHAT_MSG_SPELL_PARTY_DAMAGE")
eventFrame:RegisterEvent("CHAT_MSG_SPELL_PARTY_BUFF")
eventFrame:RegisterEvent("CHAT_MSG_SPELL_FRIENDLYPLAYER_DAMAGE")
eventFrame:RegisterEvent("CHAT_MSG_SPELL_FRIENDLYPLAYER_BUFF")
eventFrame:RegisterEvent("CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE")
eventFrame:RegisterEvent("CHAT_MSG_SPELL_CREATURE_VS_PARTY_DAMAGE")
eventFrame:RegisterEvent("CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE")
eventFrame:RegisterEvent("CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE")
eventFrame:RegisterEvent("CHAT_MSG_SPELL_HOSTILEPLAYER_BUFF")
eventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
eventFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

-- Track last spell cast by player
local lastSpellCast = nil
local lastSpellCastTime = 0

-- Initialize
function DHC:Initialize()
    self:ScanRaid()
    self:UpdateDisplay()
end

-- Scan raid for warlocks
function DHC:ScanRaid()
    -- Store old warlock data to preserve cooldowns
    local oldWarlocks = self.warlocks
    self.warlocks = {}
    
    local numRaid = GetNumRaidMembers()
    local foundNewWarlock = false
    
    if DHC.debugMode then
        DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9DHC Debug:|r Scanning... NumRaidMembers = " .. numRaid)
    end
    
    if numRaid > 0 then
        for i = 1, numRaid do
            local name, _, _, _, class = GetRaidRosterInfo(i)
            if DHC.debugMode then
                DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9DHC Debug:|r Raid member " .. i .. ": " .. (name or "nil") .. " - " .. (class or "nil"))
            end
            if class == "Warlock" and name then
                local hasDH = HasDarkHarvest(name)
                
                -- Preserve old data if warlock was already tracked
                if oldWarlocks[name] then
                    self.warlocks[name] = oldWarlocks[name]
                    -- Update hasDarkHarvest in case it changed
                    if name == UnitName("player") then
                        self.warlocks[name].hasDarkHarvest = hasDH
                    end
                else
                    -- New warlock joined
                    foundNewWarlock = true
                    self.warlocks[name] = {
                        name = name,
                        lastCast = 0,
                        ready = true,
                        hasDarkHarvest = hasDH,
                    }
                    if DHC.notifyMode then
                        DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9DHC:|r " .. name .. " joined the group")
                    end
                end
                
                if DHC.debugMode then
                    DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9DHC:|r Added warlock: " .. name .. " (DH: " .. tostring(self.warlocks[name].hasDarkHarvest) .. ")")
                end
            end
        end
    else
        -- Check if player is a warlock (solo or in party)
        local playerName = UnitName("player")
        local _, class = UnitClass("player")
        if DHC.debugMode then
            DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9DHC Debug:|r Not in raid. Player: " .. (playerName or "nil") .. " - " .. (class or "nil"))
        end
        if class == "Warlock" then
            local hasDH = HasDarkHarvest(playerName)
            
            -- Preserve old data if exists
            if oldWarlocks[playerName] then
                self.warlocks[playerName] = oldWarlocks[playerName]
                self.warlocks[playerName].hasDarkHarvest = hasDH
            else
                self.warlocks[playerName] = {
                    name = playerName,
                    lastCast = 0,
                    ready = true,
                    hasDarkHarvest = hasDH,
                }
            end
            
            if DHC.debugMode then
                DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9DHC:|r Added warlock: " .. playerName .. " (DH: " .. tostring(hasDH) .. ")")
            end
        end
    end
    
    -- Check for warlocks who left
    for name, _ in pairs(oldWarlocks) do
        if not self.warlocks[name] then
            if DHC.notifyMode then
                DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9DHC:|r " .. name .. " left the group")
            end
        end
    end
    
    -- If a new warlock joined, broadcast our DH status
    if foundNewWarlock then
        self:BroadcastDarkHarvestStatus()
    end
    
    self:RebuildRotation()
    self:CheckAutoShow()
end

-- Rebuild rotation order
function DHC:RebuildRotation()
    self.rotation = {}
    -- Only add warlocks with Dark Harvest to rotation
    for name, data in pairs(self.warlocks) do
        if data.hasDarkHarvest then
            table.insert(self.rotation, name)
        end
    end
    table.sort(self.rotation)
    
    local rotationCount = getn(self.rotation)
    if rotationCount > 0 and self.currentIndex > rotationCount then
        self.currentIndex = 1
    end
    
    -- Auto-enable rotation if more than 1 warlock with DH
    if rotationCount > 1 and not self.rotationEnabled then
        self.rotationEnabled = true
        if DHC.debugMode then
            DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9DHC:|r Rotation auto-enabled (" .. rotationCount .. " warlocks)")
        end
    end
end

-- Check if we should auto-show the window
function DHC:CheckAutoShow()
    local rotationCount = getn(self.rotation)
    -- Auto-show if more than 1 warlock and window isn't already shown
    if rotationCount > 1 and not self.frame:IsVisible() then
        self.frame:Show()
        if DHC.debugMode then
            DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9DHC:|r Window auto-opened (multiple warlocks detected)")
        end
    -- Auto-hide if 1 or fewer warlocks
    elseif rotationCount <= 1 and self.frame:IsVisible() then
        self.frame:Hide()
        if DHC.debugMode then
            DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9DHC:|r Window closed (left group)")
        end
    end
end

-- Toggle rotation system (kept for manual control)
function DHC:ToggleRotation()
    self.rotationEnabled = not self.rotationEnabled
    if self.rotationEnabled then
        self:SendMessage("ROTATION_START", self.currentIndex)
        if DHC.debugMode then
            DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9DHC:|r Rotation enabled")
        end
    else
        if DHC.debugMode then
            DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9DHC:|r Rotation disabled")
        end
    end
    self:UpdateDisplay()
end

-- Handle Dark Harvest cast detection
function DHC:OnDarkHarvestCast(caster)
    if not self.warlocks[caster] then 
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000CAST DEBUG:|r Warlock not found: " .. caster)
        return 
    end
    
    local currentTime = GetTime()
    
    -- Anti-spam: Don't process if we just processed this caster within 3 seconds
    if self.warlocks[caster].lastCast > 0 and (currentTime - self.warlocks[caster].lastCast) < 3 then
        if DHC.debugMode then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff0000CAST SPAM BLOCKED:|r " .. caster .. " cast detected but blocked (too soon: " .. (currentTime - self.warlocks[caster].lastCast) .. "s)")
        end
        return
    end
    
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00CAST ACCEPTED:|r Processing " .. caster .. "'s cast")
    
    self.warlocks[caster].lastCast = currentTime
    self.warlocks[caster].ready = false
    self.lastCastTime = currentTime
    
    if DHC.debugMode then
        DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9DHC:|r " .. caster .. " cast Dark Harvest!")
    end
    
    -- Move to next in rotation if enabled
    if self.rotationEnabled then
        self:AdvanceRotation()
    end
    
    self:SendMessage("CAST", caster)
    self:UpdateDisplay()
end

-- Handle cooldown refund
function DHC:OnCooldownRefund(warlock)
    if not self.warlocks[warlock] then return end
    
    self.warlocks[warlock].lastCast = 0
    self.warlocks[warlock].ready = true
    
    if DHC.debugMode then
        DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9DHC:|r " .. warlock .. "'s Dark Harvest cooldown was REFUNDED!")
    end
    
    self:UpdateDisplay()
end

-- Manual cast report
function DHC:ManualCast()
    local playerName = UnitName("player")
    if not self.warlocks[playerName] then
        if DHC.debugMode then
            DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9DHC:|r You are not a warlock in the rotation!")
        end
        return
    end
    
    self:OnDarkHarvestCast(playerName)
end

-- Advance to next warlock in rotation
function DHC:AdvanceRotation()
    local rotationCount = getn(self.rotation)
    if rotationCount == 0 then return end
    
    local startIndex = self.currentIndex
    local attempts = 0
    
    -- Loop until we find a living warlock or we've checked everyone
    repeat
        self.currentIndex = self.currentIndex + 1
        if self.currentIndex > rotationCount then
            self.currentIndex = 1
        end
        
        attempts = attempts + 1
        local nextWarlock = self.rotation[self.currentIndex]
        
        -- If this warlock is alive, we're done
        if not IsUnitDead(nextWarlock) then
            break
        end
        
        -- If we've checked everyone and they're all dead, stay on current
        if attempts >= rotationCount then
            if DHC.debugMode then
                DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9DHC:|r All warlocks are dead, rotation cannot advance")
            end
            break
        end
    until false
end

-- Send addon message
function DHC:SendMessage(msgType, data)
    local msg = msgType .. ":" .. (data or "")
    if GetNumRaidMembers() > 0 then
        SendAddonMessage(addonName, msg, "RAID")
    elseif GetNumPartyMembers() > 0 then
        SendAddonMessage(addonName, msg, "PARTY")
    end
end

-- Broadcast whether you have Dark Harvest
function DHC:BroadcastDarkHarvestStatus()
    local playerName = UnitName("player")
    local hasDH = HasDarkHarvest(playerName)
    local status = hasDH and "1" or "0"
    self:SendMessage("HASDH", playerName .. ":" .. status)
    
    if DHC.notifyMode then
        DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9DHC:|r Broadcasting DH status: " .. tostring(hasDH))
    end
end

-- Handle received addon messages
function DHC:OnAddonMessage(prefix, message, channel, sender)
    if prefix ~= addonName then return end
    
    local _, _, msgType, data = string.find(message, "([^:]+):?(.*)")
    
    if msgType == "CAST" then
        self:OnDarkHarvestCast(data)
    elseif msgType == "REFUND" then
        self:OnCooldownRefund(data)
    elseif msgType == "ROTATION_START" then
        self.currentIndex = tonumber(data) or 1
        self:UpdateDisplay()
    elseif msgType == "HASDH" then
        -- Parse "playername:1" or "playername:0"
        local _, _, warlockName, hasStatus = string.find(data, "([^:]+):([01])")
        if warlockName and hasStatus then
            local hasDH = (hasStatus == "1")
            if self.warlocks[warlockName] then
                self.warlocks[warlockName].hasDarkHarvest = hasDH
                if DHC.debugMode then
                    DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9DHC:|r Received DH status for " .. warlockName .. ": " .. tostring(hasDH))
                end
                self:RebuildRotation()
                self:UpdateDisplay()
            end
        end
    end
end

-- Update cooldowns
function DHC:UpdateCooldowns()
    local currentTime = GetTime()
    for name, data in pairs(self.warlocks) do
        if data.lastCast > 0 then
            local timeSince = currentTime - data.lastCast
            if timeSince >= DARK_HARVEST_COOLDOWN then
                data.ready = true
            else
                data.ready = false
            end
        end
    end
end

-- Update display
function DHC:UpdateDisplay()
    self:UpdateCooldowns()
    
    local rotationCount = getn(self.rotation)
    
    -- Count warlocks without DH
    local noDHCount = 0
    for _, data in pairs(self.warlocks) do
        if not data.hasDarkHarvest then
            noDHCount = noDHCount + 1
        end
    end
    
    if rotationCount == 0 and noDHCount == 0 then
        statusText:SetText("|cffff0000No warlocks found|r")
        warlockList:SetText("")
        warlockListNoDH:SetText("")
        nextText:SetText("")
        return
    end
    
    local status = string.format("With DH: %d", rotationCount)
    if noDHCount > 0 then
        status = status .. string.format(" | Without: %d", noDHCount)
    end
    if self.rotationEnabled then
        status = status .. " |cff00ff00[Active]|r"
    else
        status = status .. " |cffff0000[Inactive]|r"
    end
    statusText:SetText(status)
    
    -- Build warlock list with DH and cooldown info
    local listText = ""
    local currentTime = GetTime()
    for i = 1, rotationCount do
        local name = self.rotation[i]
        local data = self.warlocks[name]
        local prefix = ""
        if self.rotationEnabled and i == self.currentIndex then
            prefix = "|cffFFFF00► |r"
        else
            prefix = "  "
        end
        
        local cdText = ""
        if IsUnitDead(name) then
            cdText = "|cffff0000DEAD|r"
        elseif data.ready then
            cdText = "|cff00ff00READY|r"
        elseif data.lastCast > 0 then
            local remaining = DARK_HARVEST_COOLDOWN - (currentTime - data.lastCast)
            if remaining > 0 then
                cdText = string.format("|cffff0000%ds|r", remaining)
            end
        else
            cdText = "|cff00ff00READY|r"
        end
        
        listText = listText .. prefix .. name .. "\n" .. "  " .. cdText .. "\n"
    end
    warlockList:SetText(listText)
    
    -- Build list of warlocks without DH
    local noDHText = ""
    if noDHCount > 0 then
        noDHText = "|cffff9900No DH:|r\n"
        for name, data in pairs(self.warlocks) do
            if not data.hasDarkHarvest then
                noDHText = noDHText .. "|cff888888" .. name .. "|r\n"
            end
        end
    end
    warlockListNoDH:SetText(noDHText)
    
    -- Show next in rotation
    if self.rotationEnabled and rotationCount > 0 then
        local nextWarlock = self.rotation[self.currentIndex]
        local playerName = UnitName("player")
        
        if nextWarlock == playerName then
            local isReady = self.warlocks[playerName] and self.warlocks[playerName].ready
            
            if isReady then
                nextText:SetText("|cff00ff00YOUR TURN!|r")
                
                if not self.wasReady then
                    local currentTime = GetTime()
                    if currentTime - self.lastAlertTime > 5 then
                        UIErrorsFrame:AddMessage("Your turn for Dark Harvest!", 1.0, 1.0, 0.0, 1.0, UIERRORS_HOLD_TIME)
                        PlaySound("RaidWarning")
                        self.lastAlertTime = currentTime
                    end
                    self.wasReady = true
                end
            else
                nextText:SetText("|cffffff00Next: YOU (on CD)|r")
                self.wasReady = false
            end
        else
            nextText:SetText("Next: " .. nextWarlock)
        end
    else
        nextText:SetText("")
        self.wasReady = false
    end
end

-- Event handler
eventFrame:SetScript("OnEvent", function()
    -- Full log mode - log EVERYTHING
    if DHC.fullLogMode then
        DEFAULT_CHAT_FRAME:AddMessage("|cffFF1493[FULLLOG-" .. event .. "]:|r arg1=" .. tostring(arg1) .. " arg2=" .. tostring(arg2) .. " arg3=" .. tostring(arg3) .. " arg4=" .. tostring(arg4))
    end
    
    if event == "CHAT_MSG_ADDON" then
        DHC.OnAddonMessage(DHC, arg1, arg2, arg3, arg4)
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Entered combat - broadcast Dark Harvest status
        DHC.BroadcastDarkHarvestStatus(DHC)
    elseif event == "UNIT_HEALTH" or event == "PLAYER_DEAD" or event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
        -- Update display when health changes (to detect deaths/resurrections)
        if DHC.frame:IsVisible() then
            DHC.UpdateDisplay(DHC)
        end
    elseif event == "UNIT_SPELLCAST_SENT" or event == "UNIT_SPELLCAST_SUCCEEDED" or 
           event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_FAILED" then
        -- Only debug YOUR spells
        if DHC.debugMode and arg1 == "player" then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff00ff[" .. event .. "]:|r unit=" .. (arg1 or "nil") .. " spell=" .. (arg2 or "nil") .. " rank=" .. (arg3 or "nil") .. " target=" .. (arg4 or "nil"))
        end
        
        -- Check for Dark Harvest cast by player
        if arg1 == "player" and arg2 then
            if string.find(arg2, "Dark Harvest") or string.find(arg2, "dark harvest") then
                DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9DHC Debug:|r UNIT_SPELLCAST event for Dark Harvest!")
                lastSpellCast = arg2
                lastSpellCastTime = GetTime()
                
                if event == "UNIT_SPELLCAST_SUCCEEDED" or event == "UNIT_SPELLCAST_STOP" then
                    DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9DHC Debug:|r Detected your Dark Harvest cast via UNIT event")
                    DHC.OnDarkHarvestCast(DHC, UnitName("player"))
                end
            end
        end
    elseif string.find(event, "CHAT_MSG_COMBAT") or string.find(event, "CHAT_MSG_SPELL") then
        
        -- Super debug: Only show YOUR messages or Dark Harvest messages
        if DHC.debugMode and arg1 then
            local showMessage = false
            
            -- Show if it contains Dark Harvest
            if string.find(arg1, "Dark Harvest") or string.find(arg1, "dark harvest") then
                showMessage = true
            end
            
            -- Show if it's a SELF event
            if string.find(event, "SELF") then
                showMessage = true
            end
            
            if showMessage then
                DEFAULT_CHAT_FRAME:AddMessage("|cffff00ff[" .. event .. "]:|r " .. arg1)
            end
        end
        
        -- Parse combat log for Dark Harvest casts
        -- Pattern: "<target> is afflicted by Dark Harvest (1)."
        if arg1 and (string.find(arg1, "Dark Harvest") or string.find(arg1, "dark harvest")) then
            
            -- Check for full resist
            if string.find(arg1, "resist") or string.find(arg1, "Resist") then
                -- Check if it's YOUR resist
                if string.find(arg1, "Your Dark Harvest") or string.find(arg1, "your Dark Harvest") then
                    local playerName = UnitName("player")
                    if DHC.debugMode then
                        DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9DHC Debug:|r Your Dark Harvest was resisted!")
                        DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9DHC Debug:|r Full message: " .. arg1)
                    end
                    
                    -- Still register the cast since you attempted it
                    if DHC.warlocks[playerName] then
                        local currentTime = GetTime()
                        local timeSinceLast = currentTime - DHC.warlocks[playerName].lastCast
                        
                        if timeSinceLast < 10 then
                            if DHC.debugMode then
                                DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9DHC Debug:|r Ignoring resist (only " .. timeSinceLast .. "s since last cast)")
                            end
                        else
                            if DHC.debugMode then
                                DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9DHC Debug:|r Registering your resisted cast (time since last: " .. timeSinceLast .. "s)")
                            end
                            DHC.OnDarkHarvestCast(DHC, playerName)
                        end
                    end
                end
            -- Check if it's the affliction message (initial application)
            elseif string.find(arg1, "is afflicted by Dark Harvest") or string.find(arg1, "is afflicted by dark harvest") then
                -- This is from the player if it's a SELF event
                if string.find(event, "SELF") or event == "CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE" or 
                   event == "CHAT_MSG_SPELL_SELF_DAMAGE" or event == "CHAT_MSG_SPELL_SELF_BUFF" then
                    local playerName = UnitName("player")
                    if DHC.debugMode then
                        DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9DHC Debug:|r Found YOUR Dark Harvest affliction!")
                        DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9DHC Debug:|r Full message: " .. arg1)
                    end
                    
                    -- Check if enough time has passed since last cast (28 seconds minimum)
                    if DHC.warlocks[playerName] then
                        local currentTime = GetTime()
                        local timeSinceLast = currentTime - DHC.warlocks[playerName].lastCast
                        
                        if timeSinceLast >= 28 or DHC.warlocks[playerName].lastCast == 0 then
                            if DHC.debugMode then
                                DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9DHC Debug:|r Registering your cast (time since last: " .. timeSinceLast .. "s)")
                            end
                            DHC.OnDarkHarvestCast(DHC, playerName)
                        else
                            if DHC.debugMode then
                                DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9DHC Debug:|r Ignoring affliction (only " .. timeSinceLast .. "s since last cast)")
                            end
                        end
                    end
                else
                    -- It's from another warlock - try to extract their name
                    if DHC.debugMode then
                        DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9DHC Debug:|r Found Dark Harvest affliction from another warlock!")
                        DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9DHC Debug:|r Full message: " .. arg1)
                    end
                    -- Pattern might be different for other warlocks' afflictions
                end
            -- Check for damage ticks as backup
            elseif string.find(arg1, "from your Dark Harvest") or string.find(arg1, "from your dark harvest") then
                local playerName = UnitName("player")
                if DHC.debugMode then
                    DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9DHC Debug:|r Found YOUR Dark Harvest damage tick!")
                    DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9DHC Debug:|r Full message: " .. arg1)
                end
                
                -- Check if enough time has passed since last cast (10 seconds to cover full channel + buffer)
                if DHC.warlocks[playerName] then
                    local currentTime = GetTime()
                    local timeSinceLast = currentTime - DHC.warlocks[playerName].lastCast
                    
                    -- If less than 10 seconds, it's just another damage tick from the same cast
                    if timeSinceLast < 10 then
                        if DHC.debugMode then
                            DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9DHC Debug:|r Ignoring damage tick (only " .. timeSinceLast .. "s since last cast)")
                        end
                    else
                        -- It's been more than 10 seconds, so this is a new cast
                        -- This handles the cooldown refund scenario automatically
                        if DHC.debugMode then
                            DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9DHC Debug:|r Registering your cast (time since last: " .. timeSinceLast .. "s)")
                        end
                        DHC.OnDarkHarvestCast(DHC, playerName)
                    end
                end
            else
                -- Try to find cast messages from other warlocks
                local caster = nil
                
                if DHC.debugMode then
                    DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9DHC Debug:|r Found Dark Harvest message from another player!")
                    DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9DHC Debug:|r Full message: " .. arg1)
                end
                
                -- Try pattern: "from Name's Dark Harvest" or "Name casts Dark Harvest"
                caster = string.match(arg1, "from (.+)'s Dark Harvest") or 
                        string.match(arg1, "from (.+)'s dark harvest") or
                        string.match(arg1, "(.+) casts Dark Harvest onto") or 
                        string.match(arg1, "(.+) casts dark harvest onto") or
                        string.match(arg1, "(.+) casts Dark Harvest") or 
                        string.match(arg1, "(.+) casts dark harvest")
                
                if caster then
                    -- Check if this warlock is in our rotation (in our group)
                    if DHC.warlocks[caster] then
                        local currentTime = GetTime()
                        local timeSinceLast = currentTime - DHC.warlocks[caster].lastCast
                        
                        -- Same 10-second protection for other warlocks
                        if timeSinceLast < 10 then
                            if DHC.debugMode then
                                DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9DHC Debug:|r Ignoring " .. caster .. "'s damage tick (only " .. timeSinceLast .. "s since last)")
                            end
                        else
                            if DHC.debugMode then
                                DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9DHC Debug:|r Detected cast by: " .. caster)
                            end
                            DHC.OnDarkHarvestCast(DHC, caster)
                        end
                    else
                        -- This warlock is not in our group, ignore them
                        if DHC.debugMode then
                            DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9DHC Debug:|r Ignoring " .. caster .. " (not in our group)")
                        end
                    end
                end
            end
        end
    elseif event == "RAID_ROSTER_UPDATE" or 
           event == "PARTY_MEMBERS_CHANGED" or 
           event == "PLAYER_ENTERING_WORLD" then
        DHC.ScanRaid(DHC)
        DHC.UpdateDisplay(DHC)
    end
end)

-- Update timer
local updateTimer = 0
eventFrame:SetScript("OnUpdate", function()
    updateTimer = updateTimer + arg1
    if updateTimer >= 1 then -- Update every second
        updateTimer = 0
        if DHC.frame:IsVisible() then
            DHC.UpdateDisplay(DHC)
        end
    end
end)

-- Slash commands
SLASH_DHC1 = "/dhc"
SLASH_DHC2 = "/darkharvest"
SlashCmdList["DHC"] = function(msg)
    msg = string.lower(msg or "")
    
    if msg == "show" or msg == "" then
        DHC.frame:Show()
        DHC.Initialize(DHC)
    elseif msg == "hide" then
        DHC.frame:Hide()
    elseif msg == "toggle" then
        if DHC.frame:IsVisible() then
            DHC.frame:Hide()
        else
            DHC.frame:Show()
            DHC.Initialize(DHC)
        end
    elseif msg == "rotation" then
        DHC.ToggleRotation(DHC)
    elseif msg == "scan" then
        DHC.ScanRaid(DHC)
        local rotationCount = getn(DHC.rotation)
        DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9DHC:|r Scanned raid - found " .. rotationCount .. " warlocks")
    elseif msg == "debug" then
        DHC.debugMode = not DHC.debugMode
        if DHC.debugMode then
            DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9DHC:|r Debug mode ENABLED - will show ALL spell events")
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9DHC:|r Debug mode DISABLED")
        end
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9DHC Commands:|r")
        DEFAULT_CHAT_FRAME:AddMessage("/dhc show - Show window")
        DEFAULT_CHAT_FRAME:AddMessage("/dhc hide - Hide window")
        DEFAULT_CHAT_FRAME:AddMessage("/dhc toggle - Toggle window")
        DEFAULT_CHAT_FRAME:AddMessage("/dhc rotation - Toggle rotation")
        DEFAULT_CHAT_FRAME:AddMessage("/dhc scan - Rescan raid")
        DEFAULT_CHAT_FRAME:AddMessage("/dhc debug - Toggle debug mode")
    end
end

-- Initialize on load
DHC.Initialize(DHC)
if DHC.debugMode then
    DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9Dark Harvest Coordinator loaded! Type /dhc for commands|r")
end
