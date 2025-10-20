-- DarkHarvestCoordinator.lua
-- Addon for coordinating Warlock Dark Harvest rotation in Turtle WoW
-- Compatible with WoW 1.12 client

local addonName = "DHC"
local addonVersion = "1.0"
local DARK_HARVEST_COOLDOWN = 30

-- Color constants
local COLORS = {
    background = {0.05, 0.05, 0.05, 0.85},
    border = {0.3, 0.3, 0.3, 1},
    barBg = {0.15, 0.15, 0.15, 0.8},
    barActive = {0.58, 0.29, 0.77, 1}, -- Purple for active cooldown
    ready = {0.2, 0.8, 0.2, 1}, -- Green for ready
    dead = {0.8, 0.2, 0.2, 1}, -- Red for dead
    next = {1, 0.82, 0, 1}, -- Gold for next in rotation
    header = {0.67, 0.83, 0.45, 1}, -- Light green header
}

local DHC = {
    warlocks = {},
    rotation = {},
    currentIndex = 1,
    lastCastTime = 0,
    rotationEnabled = false,
    frame = nil,
    notifyMode = false,
    lastAlertTime = 0,
    wasReady = false,
    manuallyOpened = false,
    warlockFrames = {},
}

-- Helper functions
local function IsUnitDead(unitName)
    if unitName == UnitName("player") then
        return UnitIsDead("player") or UnitIsGhost("player")
    end
    
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

local function HasDarkHarvest(playerName)
    if playerName == UnitName("player") then
        local i = 1
        while true do
            local spellName, spellRank = GetSpellName(i, BOOKTYPE_SPELL)
            if not spellName then break end
            if string.find(spellName, "Dark Harvest") then
                return true
            end
            i = i + 1
        end
        return false
    else
        return true
    end
end

-- Create main frame with dark styling
local f = CreateFrame("Frame", "DHCFrame", UIParent)
f:SetWidth(400)
f:SetHeight(450)
f:SetPoint("CENTER", 0, 0)
f:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 16,
    insets = {left = 4, right = 4, top = 4, bottom = 4}
})
f:SetBackdropColor(unpack(COLORS.background))
f:SetBackdropBorderColor(unpack(COLORS.border))
f:SetMovable(true)
f:SetResizable(true)
f:SetMinResize(300, 250)
f:SetMaxResize(600, 800)
f:EnableMouse(true)
f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart", function() this:StartMoving() end)
f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
f:Hide()

-- Resize button (bottom right corner)
local resizeBtn = CreateFrame("Button", nil, f)
resizeBtn:SetPoint("BOTTOMRIGHT", -5, 5)
resizeBtn:SetWidth(16)
resizeBtn:SetHeight(16)
resizeBtn:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
resizeBtn:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
resizeBtn:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
resizeBtn:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_CURSOR")
    GameTooltip:SetText("Resize Window")
    GameTooltip:Show()
end)
resizeBtn:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)
resizeBtn:EnableMouse(true)
resizeBtn:SetScript("OnMouseDown", function()
    f:StartSizing("BOTTOMRIGHT")
end)
resizeBtn:SetScript("OnMouseUp", function()
    f:StopMovingOrSizing()
end)

-- Title bar
local titleBar = CreateFrame("Frame", nil, f)
titleBar:SetPoint("TOPLEFT", 5, -5)
titleBar:SetPoint("TOPRIGHT", -5, -5)
titleBar:SetHeight(30)
titleBar:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    tile = true,
    tileSize = 16,
})
titleBar:SetBackdropColor(0.1, 0.1, 0.1, 0.9)

-- Title text
local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("LEFT", 10, 0)
title:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
title:SetTextColor(unpack(COLORS.header))
title:SetText("Dark Harvest Coordinator")

-- Version text
local versionText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
versionText:SetPoint("LEFT", title, "RIGHT", 10, 0)
versionText:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
versionText:SetTextColor(0.6, 0.6, 0.6, 1)
versionText:SetText("v" .. addonVersion)

-- Status bar
local statusBar = CreateFrame("Frame", nil, f)
statusBar:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 0, -2)
statusBar:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", 0, -2)
statusBar:SetHeight(22)
statusBar:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    tile = true,
    tileSize = 16,
})
statusBar:SetBackdropColor(0.08, 0.08, 0.08, 0.9)

local statusText = statusBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
statusText:SetPoint("CENTER", 0, 0)
statusText:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
statusText:SetText("Initializing...")

-- Create scroll frame
local scrollFrame = CreateFrame("ScrollFrame", "DHCScrollFrame", f, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", statusBar, "BOTTOMLEFT", 8, -5)
scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -28, 35)

local scrollChild = CreateFrame("Frame", "DHCScrollChild", scrollFrame)
scrollChild:SetHeight(1)
scrollFrame:SetScrollChild(scrollChild)

-- Update scroll child width when frame resizes
f:SetScript("OnSizeChanged", function()
    local newWidth = this:GetWidth() - 36
    scrollChild:SetWidth(newWidth)
    -- Force update of all warlock frames to match new width
    for _, warlockFrame in pairs(DHC.warlockFrames) do
        if warlockFrame:IsVisible() then
            warlockFrame:SetWidth(newWidth)
        end
    end
    DHC:UpdateDisplay()
end)

-- Style the scrollbar
local scrollbar = getglobal("DHCScrollFrameScrollBar")
scrollbar:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    tile = true,
    tileSize = 16,
})
scrollbar:SetBackdropColor(0.1, 0.1, 0.1, 0.5)

-- Close button
local closeBtn = CreateFrame("Button", nil, titleBar)
closeBtn:SetPoint("RIGHT", -5, 0)
closeBtn:SetWidth(20)
closeBtn:SetHeight(20)
closeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
closeBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "ADD")
closeBtn:SetScript("OnClick", function()
    f:Hide()
    DHC.manuallyOpened = false
end)

-- Manual cast button
local castBtn = CreateFrame("Button", "DHCCastBtn", f)
castBtn:SetPoint("BOTTOM", 0, 8)
castBtn:SetWidth(150)
castBtn:SetHeight(22)
castBtn:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 16,
    insets = {left = 4, right = 4, top = 4, bottom = 4}
})
castBtn:SetBackdropColor(0.2, 0.15, 0.25, 0.9)
castBtn:SetBackdropBorderColor(0.4, 0.3, 0.5, 1)

local castBtnText = castBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
castBtnText:SetPoint("CENTER", 0, 0)
castBtnText:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
castBtnText:SetText("I Cast It!")

castBtn:SetScript("OnEnter", function()
    this:SetBackdropColor(0.3, 0.2, 0.35, 1)
end)
castBtn:SetScript("OnLeave", function()
    this:SetBackdropColor(0.2, 0.15, 0.25, 0.9)
end)
castBtn:SetScript("OnClick", function()
    DHC.ManualCast(DHC)
end)

DHC.frame = f

-- Event frame
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

local lastSpellCast = nil
local lastSpellCastTime = 0

function DHC:Initialize()
    self:ScanRaid()
    self:UpdateDisplay()
end

function DHC:CreateWarlockFrame(name, index)
    local warlockFrame = self.warlockFrames[name]
    
    if not warlockFrame then
        warlockFrame = CreateFrame("Frame", "DHCWarlock_"..name, scrollChild)
        warlockFrame:SetHeight(48)
        warlockFrame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 12,
            insets = {left = 3, right = 3, top = 3, bottom = 3}
        })
        warlockFrame:SetBackdropColor(unpack(COLORS.barBg))
        warlockFrame:SetBackdropBorderColor(0.2, 0.2, 0.2, 0.8)
        
        -- Name label
        warlockFrame.nameText = warlockFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        warlockFrame.nameText:SetPoint("TOPLEFT", 8, -6)
        warlockFrame.nameText:SetFont(STANDARD_TEXT_FONT, 13, "OUTLINE")
        warlockFrame.nameText:SetJustifyH("LEFT")
        
        -- Status indicator
        warlockFrame.statusText = warlockFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        warlockFrame.statusText:SetPoint("TOPRIGHT", -8, -6)
        warlockFrame.statusText:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
        warlockFrame.statusText:SetJustifyH("RIGHT")
        
        -- Bar background
        warlockFrame.barBg = CreateFrame("Frame", nil, warlockFrame)
        warlockFrame.barBg:SetPoint("BOTTOMLEFT", 6, 6)
        warlockFrame.barBg:SetPoint("BOTTOMRIGHT", -6, 6)
        warlockFrame.barBg:SetHeight(18)
        warlockFrame.barBg:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 8,
            insets = {left = 2, right = 2, top = 2, bottom = 2}
        })
        warlockFrame.barBg:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
        warlockFrame.barBg:SetBackdropBorderColor(0.15, 0.15, 0.15, 1)
        
        -- Countdown bar (StatusBar frame)
        warlockFrame.bar = CreateFrame("StatusBar", nil, warlockFrame.barBg)
        warlockFrame.bar:SetPoint("TOPLEFT", 2, -2)
        warlockFrame.bar:SetPoint("BOTTOMRIGHT", -2, 2)
        warlockFrame.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        warlockFrame.bar:SetStatusBarColor(unpack(COLORS.barActive))
        warlockFrame.bar:SetMinMaxValues(0, DARK_HARVEST_COOLDOWN)
        warlockFrame.bar:SetValue(0)
        
        -- Text overlay frame
        warlockFrame.textOverlay = CreateFrame("Frame", nil, warlockFrame.barBg)
        warlockFrame.textOverlay:SetAllPoints(warlockFrame.barBg)
        warlockFrame.textOverlay:SetFrameLevel(warlockFrame.barBg:GetFrameLevel() + 2)
        
        -- Timer text
        warlockFrame.timerText = warlockFrame.textOverlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        warlockFrame.timerText:SetPoint("CENTER", 0, 0)
        warlockFrame.timerText:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
        warlockFrame.timerText:SetText("")
        
        self.warlockFrames[name] = warlockFrame
    end
    
    -- Update width and position
    local frameWidth = scrollChild:GetWidth()
    warlockFrame:SetWidth(frameWidth)
    warlockFrame:SetPoint("TOPLEFT", 5, -(index - 1) * 52)
    warlockFrame:Show()
    
    return warlockFrame
end

function DHC:ScanRaid()
    local oldWarlocks = self.warlocks
    self.warlocks = {}
    
    local numRaid = GetNumRaidMembers()
    local foundNewWarlock = false
    
    if numRaid > 0 then
        for i = 1, numRaid do
            local name, _, _, _, class = GetRaidRosterInfo(i)
            if class == "Warlock" and name then
                local hasDH = HasDarkHarvest(name)
                
                if oldWarlocks[name] then
                    self.warlocks[name] = oldWarlocks[name]
                    if name == UnitName("player") then
                        self.warlocks[name].hasDarkHarvest = hasDH
                    end
                else
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
            end
        end
    else
        local playerName = UnitName("player")
        local _, class = UnitClass("player")
        if class == "Warlock" then
            local hasDH = HasDarkHarvest(playerName)
            
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
        end
    end
    
    for name, _ in pairs(oldWarlocks) do
        if not self.warlocks[name] then
            if DHC.notifyMode then
                DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9DHC:|r " .. name .. " left the group")
            end
        end
    end
    
    if foundNewWarlock then
        self:BroadcastDarkHarvestStatus()
    end
    
    self:RebuildRotation()
    self:CheckAutoShow()
end

function DHC:RebuildRotation()
    self.rotation = {}
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
    
    if rotationCount > 1 and not self.rotationEnabled then
        self.rotationEnabled = true
    end
end

function DHC:CheckAutoShow()
    local rotationCount = getn(self.rotation)
    if rotationCount > 1 and not self.frame:IsVisible() then
        self.frame:Show()
    elseif rotationCount <= 1 and self.frame:IsVisible() and not self.manuallyOpened then
        self.frame:Hide()
    end
end

function DHC:ToggleRotation()
    self.rotationEnabled = not self.rotationEnabled
    if self.rotationEnabled then
        self:SendMessage("ROTATION_START", self.currentIndex)
    end
    self:UpdateDisplay()
end

function DHC:OnDarkHarvestCast(caster)
    if not self.warlocks[caster] then return end
    
    local currentTime = GetTime()
    
    -- Anti-spam: Don't process if we just processed this caster within 3 seconds
    if self.warlocks[caster].lastCast > 0 and (currentTime - self.warlocks[caster].lastCast) < 3 then
        return
    end
    
    if DHC.notifyMode then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00DHC:|r Processing " .. caster .. "'s cast")
    end
    
    self.warlocks[caster].lastCast = currentTime
    self.warlocks[caster].ready = false
    self.lastCastTime = currentTime
    
    if self.rotationEnabled then
        -- Find the caster's position in rotation
        local casterIndex = nil
        for i = 1, getn(self.rotation) do
            if self.rotation[i] == caster then
                casterIndex = i
                break
            end
        end
        
        -- If caster is in rotation, advance from their position
        if casterIndex then
            self.currentIndex = casterIndex
            self:AdvanceRotation()
        end
    end
    
    self:SendMessage("CAST", caster)
    self:UpdateDisplay()
end

function DHC:AdvanceRotation()
    local rotationCount = getn(self.rotation)
    if rotationCount == 0 then return end
    
    local startIndex = self.currentIndex
    local attempts = 0
    
    repeat
        self.currentIndex = self.currentIndex + 1
        if self.currentIndex > rotationCount then
            self.currentIndex = 1
        end
        
        attempts = attempts + 1
        local nextWarlock = self.rotation[self.currentIndex]
        
        if not IsUnitDead(nextWarlock) then
            break
        end
        
        if attempts >= rotationCount then
            break
        end
    until false
end

function DHC:SendMessage(msgType, data)
    local msg = msgType .. ":" .. (data or "")
    if GetNumRaidMembers() > 0 then
        SendAddonMessage(addonName, msg, "RAID")
    elseif GetNumPartyMembers() > 0 then
        SendAddonMessage(addonName, msg, "PARTY")
    end
end

function DHC:BroadcastDarkHarvestStatus()
    local playerName = UnitName("player")
    local hasDH = HasDarkHarvest(playerName)
    local status = hasDH and "1" or "0"
    self:SendMessage("HASDH", playerName .. ":" .. status)
    
    if DHC.notifyMode then
        DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9DHC:|r Broadcasting DH status: " .. tostring(hasDH))
    end
end

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
        local _, _, warlockName, hasStatus = string.find(data, "([^:]+):([01])")
        if warlockName and hasStatus then
            local hasDH = (hasStatus == "1")
            if self.warlocks[warlockName] then
                self.warlocks[warlockName].hasDarkHarvest = hasDH
                self:RebuildRotation()
                self:UpdateDisplay()
            end
        end
    end
end

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

function DHC:UpdateDisplay()
    self:UpdateCooldowns()
    
    local rotationCount = getn(self.rotation)
    local noDHCount = 0
    for _, data in pairs(self.warlocks) do
        if not data.hasDarkHarvest then
            noDHCount = noDHCount + 1
        end
    end
    
    if rotationCount == 0 and noDHCount == 0 then
        statusText:SetText("|cffff0000No warlocks found|r")
        for _, frame in pairs(self.warlockFrames) do
            frame:Hide()
        end
        return
    end
    
    local status = string.format("Warlocks: |cffabd473%d|r", rotationCount)
    if noDHCount > 0 then
        status = status .. string.format(" | Without DH: |cff888888%d|r", noDHCount)
    end
    if self.rotationEnabled then
        status = status .. " |cff58ff00[Active]|r"
    else
        status = status .. " |cffff6060[Inactive]|r"
    end
    statusText:SetText(status)
    
    -- Update warlock frames
    local currentTime = GetTime()
    local index = 1
    
    -- Show warlocks with DH
    for i = 1, rotationCount do
        local name = self.rotation[i]
        local data = self.warlocks[name]
        local warlockFrame = self:CreateWarlockFrame(name, index)
        
        -- Update name with class color
        local nameColor = "ffffffff"
        if name == UnitName("player") then
            nameColor = "ff9482c9" -- Purple for player
        end
        warlockFrame.nameText:SetText("|c" .. nameColor .. name .. "|r")
        
        -- Update status
        if self.rotationEnabled and i == self.currentIndex then
            warlockFrame.statusText:SetText("|cffffd100► NEXT|r")
        else
            warlockFrame.statusText:SetText("")
        end
        
        -- Update countdown bar
        if IsUnitDead(name) then
            warlockFrame.bar:SetMinMaxValues(0, 1)
            warlockFrame.bar:SetValue(0)
            warlockFrame.bar:SetStatusBarColor(unpack(COLORS.dead))
            warlockFrame.timerText:SetText("|cffff6060DEAD|r")
        elseif data.ready then
            warlockFrame.bar:SetMinMaxValues(0, 1)
            warlockFrame.bar:SetValue(0)
            warlockFrame.bar:SetStatusBarColor(unpack(COLORS.ready))
            warlockFrame.timerText:SetText("|cff33ff33READY|r")
        elseif data.lastCast > 0 then
            local remaining = DARK_HARVEST_COOLDOWN - (currentTime - data.lastCast)
            if remaining > 0 then
                warlockFrame.bar:SetMinMaxValues(0, DARK_HARVEST_COOLDOWN)
                warlockFrame.bar:SetValue(remaining)
                warlockFrame.bar:SetStatusBarColor(unpack(COLORS.barActive))
                warlockFrame.timerText:SetText(string.format("%ds", math.ceil(remaining)))
            else
                warlockFrame.bar:SetMinMaxValues(0, 1)
                warlockFrame.bar:SetValue(0)
                warlockFrame.bar:SetStatusBarColor(unpack(COLORS.ready))
                warlockFrame.timerText:SetText("|cff33ff33READY|r")
            end
        else
            warlockFrame.bar:SetMinMaxValues(0, 1)
            warlockFrame.bar:SetValue(0)
            warlockFrame.bar:SetStatusBarColor(unpack(COLORS.ready))
            warlockFrame.timerText:SetText("|cff33ff33READY|r")
        end
        
        index = index + 1
    end
    
    -- Show warlocks without DH
    for name, data in pairs(self.warlocks) do
        if not data.hasDarkHarvest then
            local warlockFrame = self:CreateWarlockFrame(name, index)
            warlockFrame.nameText:SetText("|cff666666" .. name .. " (No DH)|r")
            warlockFrame.statusText:SetText("")
            warlockFrame.bar:SetMinMaxValues(0, 1)
            warlockFrame.bar:SetValue(0)
            warlockFrame.bar:SetStatusBarColor(0.3, 0.3, 0.3, 0.5)
            warlockFrame.timerText:SetText("")
            index = index + 1
        end
    end
    
    -- Hide unused frames
    for name, frame in pairs(self.warlockFrames) do
        if not self.warlocks[name] then
            frame:Hide()
        end
    end
    
    -- Update scroll child height
    scrollChild:SetHeight(math.max(1, (index - 1) * 52))
    
    -- Check if player is next
    if self.rotationEnabled and rotationCount > 0 then
        local nextWarlock = self.rotation[self.currentIndex]
        local playerName = UnitName("player")
        
        if nextWarlock == playerName then
            local isReady = self.warlocks[playerName] and self.warlocks[playerName].ready
            
            if isReady and not self.wasReady then
                local currentTime = GetTime()
                if currentTime - self.lastAlertTime > 5 then
                    UIErrorsFrame:AddMessage("Your turn for Dark Harvest!", 1.0, 1.0, 0.0, 1.0, UIERRORS_HOLD_TIME)
                    PlaySound("RaidWarning")
                    self.lastAlertTime = currentTime
                end
                self.wasReady = true
            elseif not isReady then
                self.wasReady = false
            end
        else
            self.wasReady = false
        end
    else
        self.wasReady = false
    end
end

function DHC:OnCooldownRefund(warlock)
    if not self.warlocks[warlock] then return end
    
    self.warlocks[warlock].lastCast = 0
    self.warlocks[warlock].ready = true
    
    self:UpdateDisplay()
end

function DHC:ManualCast()
    local playerName = UnitName("player")
    if not self.warlocks[playerName] then
        return
    end
    
    self:OnDarkHarvestCast(playerName)
end

-- Event handler
eventFrame:SetScript("OnEvent", function()
    if event == "CHAT_MSG_ADDON" then
        DHC.OnAddonMessage(DHC, arg1, arg2, arg3, arg4)
    elseif event == "PLAYER_REGEN_DISABLED" then
        DHC.BroadcastDarkHarvestStatus(DHC)
    elseif event == "UNIT_HEALTH" or event == "PLAYER_DEAD" or event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
        if DHC.frame:IsVisible() then
            DHC.UpdateDisplay(DHC)
        end
    elseif event == "UNIT_SPELLCAST_SENT" or event == "UNIT_SPELLCAST_SUCCEEDED" or 
           event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_FAILED" then
        
        if arg1 == "player" and arg2 then
            if string.find(arg2, "Dark Harvest") or string.find(arg2, "dark harvest") then
                lastSpellCast = arg2
                lastSpellCastTime = GetTime()
                
                if event == "UNIT_SPELLCAST_SUCCEEDED" or event == "UNIT_SPELLCAST_STOP" then
                    DHC.OnDarkHarvestCast(DHC, UnitName("player"))
                end
            end
        end
    elseif string.find(event, "CHAT_MSG_COMBAT") or string.find(event, "CHAT_MSG_SPELL") then
        
        if arg1 and (string.find(arg1, "Dark Harvest") or string.find(arg1, "dark harvest")) then
            
            if string.find(arg1, "resist") or string.find(arg1, "Resist") then
                if string.find(arg1, "Your Dark Harvest") or string.find(arg1, "your Dark Harvest") then
                    local playerName = UnitName("player")
                    
                    if DHC.warlocks[playerName] then
                        local currentTime = GetTime()
                        local timeSinceLast = currentTime - DHC.warlocks[playerName].lastCast
                        
                        if timeSinceLast >= 10 then
                            DHC.OnDarkHarvestCast(DHC, playerName)
                        end
                    end
                end
            elseif string.find(arg1, "is afflicted by Dark Harvest") or string.find(arg1, "is afflicted by dark harvest") then
                if string.find(event, "SELF") or event == "CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE" or 
                   event == "CHAT_MSG_SPELL_SELF_DAMAGE" or event == "CHAT_MSG_SPELL_SELF_BUFF" then
                    local playerName = UnitName("player")
                    
                    if DHC.warlocks[playerName] then
                        local currentTime = GetTime()
                        local timeSinceLast = currentTime - DHC.warlocks[playerName].lastCast
                        
                        if timeSinceLast >= 28 or DHC.warlocks[playerName].lastCast == 0 then
                            DHC.OnDarkHarvestCast(DHC, playerName)
                        end
                    end
                end
            elseif string.find(arg1, "from your Dark Harvest") or string.find(arg1, "from your dark harvest") then
                local playerName = UnitName("player")
                
                if DHC.warlocks[playerName] then
                    local currentTime = GetTime()
                    local timeSinceLast = currentTime - DHC.warlocks[playerName].lastCast
                    
                    if timeSinceLast >= 10 then
                        DHC.OnDarkHarvestCast(DHC, playerName)
                    end
                end
            else
                -- Try to find cast messages from other warlocks
                if arg1 then
                    local caster = string.match(arg1, "from (.+)'s Dark Harvest") or 
                            string.match(arg1, "from (.+)'s dark harvest") or
                            string.match(arg1, "(.+) casts Dark Harvest onto") or 
                            string.match(arg1, "(.+) casts dark harvest onto") or
                            string.match(arg1, "(.+) casts Dark Harvest") or 
                            string.match(arg1, "(.+) casts dark harvest")
                    
                    if caster then
                        if DHC.warlocks[caster] then
                            local currentTime = GetTime()
                            local timeSinceLast = currentTime - DHC.warlocks[caster].lastCast
                            
                            if timeSinceLast >= 10 then
                                DHC.OnDarkHarvestCast(DHC, caster)
                            end
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
    if updateTimer >= 1 then
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
        DHC.manuallyOpened = true
        DHC.Initialize(DHC)
    elseif msg == "hide" then
        DHC.frame:Hide()
        DHC.manuallyOpened = false
    elseif msg == "toggle" then
        if DHC.frame:IsVisible() then
            DHC.frame:Hide()
            DHC.manuallyOpened = false
        else
            DHC.frame:Show()
            DHC.manuallyOpened = true
            DHC.Initialize(DHC)
        end
    elseif msg == "rotation" then
        DHC.ToggleRotation(DHC)
    elseif msg == "scan" then
        DHC.ScanRaid(DHC)
        local rotationCount = getn(DHC.rotation)
        DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9DHC:|r Scanned raid - found " .. rotationCount .. " warlocks")
    elseif msg == "notify" then
        DHC.notifyMode = not DHC.notifyMode
        if DHC.notifyMode then
            DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9DHC:|r Notify mode ENABLED")
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9DHC:|r Notify mode DISABLED")
        end
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9DHC Commands:|r")
        DEFAULT_CHAT_FRAME:AddMessage("/dhc show - Show window")
        DEFAULT_CHAT_FRAME:AddMessage("/dhc hide - Hide window")
        DEFAULT_CHAT_FRAME:AddMessage("/dhc toggle - Toggle window")
        DEFAULT_CHAT_FRAME:AddMessage("/dhc rotation - Toggle rotation")
        DEFAULT_CHAT_FRAME:AddMessage("/dhc scan - Rescan raid")
        DEFAULT_CHAT_FRAME:AddMessage("/dhc notify - Toggle notify mode")
    end
end

-- Initialize on load
DHC.Initialize(DHC)
