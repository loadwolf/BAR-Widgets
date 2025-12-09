-- Metal Tracker module - Handles metal income tracking and notifications
local MetalTracker = {}
local DataManager = nil
local Logger = nil
local Utils = nil
local Config = nil

function MetalTracker.init(dataMgr, logger, utils, config)
    DataManager = dataMgr
    Logger = logger
    Utils = utils
    Config = config
end

-- Check if a team is a valid player team
local function isValidPlayerTeam(teamID, myTeamID)
    if not teamID or teamID < 0 then
        return false
    end
    
    local gaiaTeamID = Spring.GetGaiaTeamID()
    if teamID == gaiaTeamID or teamID == myTeamID then
        return false
    end
    
    local players = Spring.GetPlayerList(teamID)
    if not players or #players == 0 then
        return false
    end
    
    for _, playerID in ipairs(players) do
        local name, active, spectator = Spring.GetPlayerInfo(playerID)
        if name and not spectator and active then
            return true
        end
    end
    
    return false
end

-- Try to detect team from selected units
local function detectTeamFromSelection(myTeamID)
    local selectedUnits = Spring.GetSelectedUnits()
    if not selectedUnits or #selectedUnits == 0 then
        return nil
    end
    
    local unitTeam = Spring.GetUnitTeam(selectedUnits[1])
    if isValidPlayerTeam(unitTeam, myTeamID) then
        return unitTeam
    end
    
    return nil
end

-- Get the team ID to track (handles spectator mode)
local function getTrackedTeamID()
    local myTeamID = Spring.GetMyTeamID()
    if not myTeamID or myTeamID < 0 then
        return nil
    end
    
    local isSpectating = Spring.GetSpectatingState()
    if isSpectating then
        local detectedTeam = detectTeamFromSelection(myTeamID)
        if detectedTeam then
            return detectedTeam
        end
        return nil
    else
        return myTeamID
    end
end

function MetalTracker.addNotification(income, threshold)
    local now = Spring.GetGameSeconds()
    local formattedIncome = Utils.formatMetalIncome(income)
    local formattedThreshold = Utils.formatMetalIncome(threshold)
    
    local teamID = getTrackedTeamID()
    local teamName = ""
    if teamID then
        teamName = Utils.getPlayerName(teamID) or ("Team " .. tostring(teamID))
    end
    
    local pingText = string.format("Metal Income (%s): %s/s (Reached %s/s)", teamName, formattedIncome, formattedThreshold)
    
    -- Remove placeholder message if this is the first real notification
    if not DataManager.getHasRealNotification() then
        DataManager.setHasRealNotification(true)
        local deathMessages = DataManager.getDeathMessages()
        for i = #deathMessages, 1, -1 do
            if deathMessages[i].messageType == "system" then
                table.remove(deathMessages, i)
            end
        end
    end
    
    DataManager.addDeathMessage({
        time = now,
        pingText = pingText,
        valuesText = {},
        killerName = nil,
        killerCount = 0,
        totalQueens = nil,
        killedQueens = 0,
        remaining = nil,
        dismissed = false,
        messageType = "metal_income"
    })
    
    Spring.Echo("[Queen Death Display API] " .. pingText)
    Logger.log("metal_income", pingText, {}, now, Utils.formatTime)
end

function MetalTracker.update(frame)
    if frame % Config.METAL_CHECK_INTERVAL ~= 0 then
        return
    end
    
    local teamID = getTrackedTeamID()
    if not teamID or teamID < 0 then
        return
    end
    
    local trackedTeamID = DataManager.getTrackedTeamID()
    local metalIncomeTriggered = DataManager.getMetalIncomeTriggered()
    local lastMetalAmount = DataManager.getLastMetalAmount()
    local lastMetalCheckTime = DataManager.getLastMetalCheckTime()
    
    -- Update tracked team if it changed
    if trackedTeamID ~= teamID then
        DataManager.setTrackedTeamID(teamID)
        lastMetalAmount[teamID] = nil
        lastMetalCheckTime[teamID] = nil
        metalIncomeTriggered[teamID] = {}
        
        local teamName = Utils.getPlayerName(teamID) or ("Team " .. tostring(teamID))
        local isSpectating = Spring.GetSpectatingState()
        if isSpectating then
            Spring.Echo(string.format("[Queen Death Display API] Now tracking metal income for: %s (Team %d)", teamName, teamID))
        end
    end
    
    -- GetTeamResources returns: current, storage, pull, income, expense, share, sent, received
    local metal, storage, pull, income = Spring.GetTeamResources(teamID, "metal")
    
    if not income or income < 0 then
        return
    end
    
    local incomeRate = income
    
    -- Store current income rate for export (this is what gets displayed on web interface)
    local lastMetalAmount = DataManager.getLastMetalAmount()
    lastMetalAmount[teamID] = incomeRate
    
    -- Also store the check time
    local lastMetalCheckTime = DataManager.getLastMetalCheckTime()
    lastMetalCheckTime[teamID] = Spring.GetGameSeconds()
    
    -- Initialize tracking for this team
    if not metalIncomeTriggered[teamID] then
        metalIncomeTriggered[teamID] = {}
    end
    
    -- Check thresholds (per team)
    local triggered = metalIncomeTriggered[teamID] or {}
    for _, threshold in ipairs(Config.METAL_INCOME_THRESHOLDS) do
        if incomeRate >= threshold and not triggered[threshold] then
            triggered[threshold] = true
            MetalTracker.addNotification(incomeRate, threshold)
        end
    end
    metalIncomeTriggered[teamID] = triggered
end

return MetalTracker

