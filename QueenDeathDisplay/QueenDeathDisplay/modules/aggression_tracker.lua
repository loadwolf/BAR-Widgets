-- Aggression Tracker module - Handles player aggression (eco attraction) tracking
local AggressionTracker = {}
local DataManager = nil
local Utils = nil
local Config = nil
local HarmonyRaptor = nil
local harmonyRaptorAvailable = false

function AggressionTracker.init(dataMgr, utils, config, hr)
    DataManager = dataMgr
    Utils = utils
    Config = config
    HarmonyRaptor = hr
    harmonyRaptorAvailable = (hr ~= nil)
end

function AggressionTracker.updatePlayerTeams()
    if not harmonyRaptorAvailable or not HarmonyRaptor then
        -- Fallback: get teams manually
        local allTeams = Spring.GetTeamList()
        local gaiaTeamID = Spring.GetGaiaTeamID()
        local myTeamID = Spring.GetMyTeamID()
        
        local playerTeams = {}
        local playerEcoAttractionsRaw = DataManager.getPlayerEcoAttractionsRaw()
        
        for _, teamID in ipairs(allTeams) do
            if teamID ~= gaiaTeamID and teamID >= 0 then
                local players = Spring.GetPlayerList(teamID, true) or Spring.GetPlayerList(teamID) or {}
                if #players > 0 then
                    local hasActivePlayer = false
                    for _, playerID in ipairs(players) do
                        local name, active, spectator = Spring.GetPlayerInfo(playerID)
                        if name and active and not spectator then
                            hasActivePlayer = true
                            break
                        end
                    end
                    if hasActivePlayer then
                        table.insert(playerTeams, teamID)
                        if not playerEcoAttractionsRaw[teamID] then
                            playerEcoAttractionsRaw[teamID] = 0
                        end
                    end
                end
            end
        end
        DataManager.setPlayerTeams(playerTeams)
        return
    end
    
    local newPlayerTeams = HarmonyRaptor.getPlayerTeams()
    if not newPlayerTeams then
        return
    end
    
    DataManager.setPlayerTeams(newPlayerTeams)
    
    -- Initialize eco tracking for new teams
    local playerEcoAttractionsRaw = DataManager.getPlayerEcoAttractionsRaw()
    for _, teamID in ipairs(newPlayerTeams) do
        if not playerEcoAttractionsRaw[teamID] then
            playerEcoAttractionsRaw[teamID] = 0
        end
    end
end

function AggressionTracker.scanExistingUnits()
    if not harmonyRaptorAvailable or not HarmonyRaptor then
        Spring.Echo("[AggressionTracker] ERROR: HarmonyRaptor not available for unit scan")
        return
    end
    
    local playerEcoAttractionsRaw = DataManager.getPlayerEcoAttractionsRaw()
    local raptorsTeamID = HarmonyRaptor.getRaptorsTeamID()
    
    -- Ensure all player teams are initialized BEFORE scanning (critical!)
    -- HarmonyRaptor.updatePlayerEcoValues requires the team to exist in the table
    local playerTeams = DataManager.getPlayerTeams()
    for _, teamID in ipairs(playerTeams) do
        if not playerEcoAttractionsRaw[teamID] then
            playerEcoAttractionsRaw[teamID] = 0
        end
    end
    
    -- Scan all units and update eco values (matching raptor-panel.lua pattern)
    local allUnits = Spring.GetAllUnits()
    local unitsScanned = 0
    local unitsWithEco = 0
    
    for _, unitID in ipairs(allUnits) do
        local unitDefID = Spring.GetUnitDefID(unitID)
        local unitTeamID = Spring.GetUnitTeam(unitID)
        
        -- Skip raptor units, update all other units
        if unitTeamID and unitTeamID ~= raptorsTeamID and unitDefID then
            unitsScanned = unitsScanned + 1
            
            -- Initialize team eco value if it doesn't exist (defensive)
            if not playerEcoAttractionsRaw[unitTeamID] then
                playerEcoAttractionsRaw[unitTeamID] = 0
            end
            
            -- Get eco value before update to check if it will change
            local ecoBefore = playerEcoAttractionsRaw[unitTeamID] or 0
            local unitEcoValue = HarmonyRaptor.getUnitEcoValue and HarmonyRaptor.getUnitEcoValue(unitDefID) or 0
            
            -- Update eco value for this unit
            HarmonyRaptor.updatePlayerEcoValues(playerEcoAttractionsRaw, unitDefID, unitTeamID, true)
            
            -- Check if value changed
            local ecoAfter = playerEcoAttractionsRaw[unitTeamID] or 0
            if ecoAfter > ecoBefore then
                unitsWithEco = unitsWithEco + 1
            end
        end
    end
    
    Spring.Echo(string.format("[AggressionTracker] Unit scan complete: %d units scanned, %d units contributed eco value", unitsScanned, unitsWithEco))
end

function AggressionTracker.onUnitCreated(unitID, unitDefID, unitTeamID)
    if not harmonyRaptorAvailable or not HarmonyRaptor then
        return
    end
    
    local playerEcoAttractionsRaw = DataManager.getPlayerEcoAttractionsRaw()
    
    -- Initialize team eco value if it doesn't exist (matching raptor-panel.lua pattern)
    if not playerEcoAttractionsRaw[unitTeamID] then
        playerEcoAttractionsRaw[unitTeamID] = 0
    end
    
    -- Update eco value for this unit
    HarmonyRaptor.updatePlayerEcoValues(playerEcoAttractionsRaw, unitDefID, unitTeamID, true)
end

function AggressionTracker.onUnitGiven(unitID, unitDefID, newTeamID, oldTeamID)
    if not harmonyRaptorAvailable or not HarmonyRaptor then
        return
    end
    
    local playerEcoAttractionsRaw = DataManager.getPlayerEcoAttractionsRaw()
    
    -- Initialize teams if needed (matching raptor-panel.lua pattern)
    if not playerEcoAttractionsRaw[newTeamID] then
        playerEcoAttractionsRaw[newTeamID] = 0
    end
    if not playerEcoAttractionsRaw[oldTeamID] then
        playerEcoAttractionsRaw[oldTeamID] = 0
    end
    
    -- Update eco values: add to new team, subtract from old team
    HarmonyRaptor.updatePlayerEcoValues(playerEcoAttractionsRaw, unitDefID, newTeamID, true)
    HarmonyRaptor.updatePlayerEcoValues(playerEcoAttractionsRaw, unitDefID, oldTeamID, false)
end

function AggressionTracker.onUnitDestroyed(unitID, unitDefID, unitTeam)
    if not harmonyRaptorAvailable or not HarmonyRaptor then
        return
    end
    
    local playerEcoAttractionsRaw = DataManager.getPlayerEcoAttractionsRaw()
    
    -- Initialize team if needed (shouldn't happen, but defensive)
    if not playerEcoAttractionsRaw[unitTeam] then
        playerEcoAttractionsRaw[unitTeam] = 0
    end
    
    -- Update eco value: subtract from team (matching raptor-panel.lua pattern)
    HarmonyRaptor.updatePlayerEcoValues(playerEcoAttractionsRaw, unitDefID, unitTeam, false)
end

function AggressionTracker.getAggressionData()
    local aggressionData = {}
    local sum = 0
    local myTeamID = Spring.GetMyTeamID()
    local playerTeams = DataManager.getPlayerTeams()
    local playerEcoAttractionsRaw = DataManager.getPlayerEcoAttractionsRaw()
    
    -- First, collect all teams with eco values > 0 (matching raptor-panel.lua pattern)
    -- This ensures we only calculate percentages for teams that actually have units
    local teamsWithEco = {}
    for _, teamID in ipairs(playerTeams) do
        local ecoValue = playerEcoAttractionsRaw[teamID] or 0
        ecoValue = math.max(0, ecoValue)
        if ecoValue > 0 then
            table.insert(teamsWithEco, teamID)
            sum = sum + ecoValue
        end
    end
    
    -- Also check for teams in playerEcoAttractionsRaw that might not be in playerTeams
    -- (defensive: handles edge cases where teams were added during unit scanning)
    for teamID, ecoValue in pairs(playerEcoAttractionsRaw) do
        if ecoValue and ecoValue > 0 then
            local found = false
            for _, tid in ipairs(teamsWithEco) do
                if tid == teamID then
                    found = true
                    break
                end
            end
            if not found then
                -- Check if this is a valid player team (not raptors, not gaia)
                local raptorsTeamID = nil
                if HarmonyRaptor and HarmonyRaptor.getRaptorsTeamID then
                    raptorsTeamID = HarmonyRaptor.getRaptorsTeamID()
                end
                local gaiaTeamID = Spring.GetGaiaTeamID()
                if teamID ~= raptorsTeamID and teamID ~= gaiaTeamID and teamID >= 0 then
                    table.insert(teamsWithEco, teamID)
                    sum = sum + ecoValue
                end
            end
        end
    end
    
    -- Build aggression data only for teams with eco values > 0
    for _, teamID in ipairs(teamsWithEco) do
        local playerName = Utils.getPlayerName(teamID)
        if not playerName or playerName == "" then
            playerName = "Team " .. tostring(teamID)
        end
        
        local ecoValue = playerEcoAttractionsRaw[teamID] or 0
        ecoValue = math.max(0, ecoValue)
        
        local percentage = 0
        local multiplier = 0
        if sum > 0 then
            percentage = (ecoValue / sum) * 100
            multiplier = (#teamsWithEco * ecoValue) / sum
        end
        
        local threatLevel = "low"
        if multiplier > Config.THREAT_HIGH then
            threatLevel = "high"
        elseif multiplier > Config.THREAT_MEDIUM then
            threatLevel = "medium"
        end
        
        table.insert(aggressionData, {
            teamID = teamID,
            name = playerName,
            ecoValue = ecoValue,
            percentage = percentage,
            multiplier = multiplier,
            threatLevel = threatLevel,
            isMe = (myTeamID == teamID),
        })
    end
    
    -- Sort by eco value (descending)
    table.sort(aggressionData, function(a, b)
        return a.ecoValue > b.ecoValue
    end)
    
    return aggressionData
end

return AggressionTracker

