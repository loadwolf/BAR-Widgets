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

function MetalTracker.update(frame)
    if frame % Config.METAL_CHECK_INTERVAL ~= 0 then
        return
    end
    
    local teamID = getTrackedTeamID()
    if not teamID or teamID < 0 then
        return
    end
    
    local trackedTeamID = DataManager.getTrackedTeamID()
    local lastMetalAmount = DataManager.getLastMetalAmount()
    local lastMetalCheckTime = DataManager.getLastMetalCheckTime()
    
    -- Update tracked team if it changed
    if trackedTeamID ~= teamID then
        DataManager.setTrackedTeamID(teamID)
        lastMetalAmount[teamID] = nil
        lastMetalCheckTime[teamID] = nil
        
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
    
    -- REMOVED: Threshold checking and notifications (metal income milestones disabled)
end

return MetalTracker

