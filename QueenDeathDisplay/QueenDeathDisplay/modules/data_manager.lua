-- Data Manager module - Centralized state management
local DataManager = {}

local state = {
    -- Queen tracking
    teamKills = {},
    raptorQueenDefIDs = {},
    
    -- Messages
    deathMessages = {},
    hasRealNotification = false,
    leaderboardShown = false,
    spectatorWarningShown = false,
    
    -- Metal income tracking
    metalIncomeTriggered = {},
    lastMetalAmount = {},
    lastMetalCheckTime = {},
    trackedTeamID = nil,
    
    -- Player aggression tracking
    playerEcoAttractionsRaw = {},
    playerTeams = {},
}

function DataManager.init(queenDefIDs)
    state.raptorQueenDefIDs = queenDefIDs or {}
    -- Reset state
    state.teamKills = {}
    state.deathMessages = {}
    state.metalIncomeTriggered = {}
    state.lastMetalAmount = {}
    state.lastMetalCheckTime = {}
    state.playerEcoAttractionsRaw = {}
    state.playerTeams = {}
    state.hasRealNotification = false
    state.leaderboardShown = false
    state.spectatorWarningShown = false
    state.trackedTeamID = nil
end

function DataManager.getState()
    return state
end

-- Queen tracking
function DataManager.getTeamKills()
    return state.teamKills
end

function DataManager.addKill(teamID)
    state.teamKills[teamID] = (state.teamKills[teamID] or 0) + 1
end

function DataManager.getKillCount(teamID)
    return state.teamKills[teamID] or 0
end

function DataManager.isQueenDefID(unitDefID)
    if state.raptorQueenDefIDs[unitDefID] == true then
        return true
    end
    -- Fallback: match by unit name prefix to be robust if defs change
    if UnitDefs and unitDefID and UnitDefs[unitDefID] and UnitDefs[unitDefID].name then
        local name = UnitDefs[unitDefID].name
        if name:find("^raptor_queen") then
            return true
        end
    end
    return false
end

-- Messages
function DataManager.addDeathMessage(message)
    table.insert(state.deathMessages, message)
    if #state.deathMessages > 20 then
        table.remove(state.deathMessages, 1)
    end
end

function DataManager.getDeathMessages()
    return state.deathMessages
end

function DataManager.setHasRealNotification(value)
    state.hasRealNotification = value
end

function DataManager.getHasRealNotification()
    return state.hasRealNotification
end

function DataManager.setLeaderboardShown(value)
    state.leaderboardShown = value
end

function DataManager.getLeaderboardShown()
    return state.leaderboardShown
end

function DataManager.setSpectatorWarningShown(value)
    state.spectatorWarningShown = value
end

function DataManager.getSpectatorWarningShown()
    return state.spectatorWarningShown
end

-- Metal income
function DataManager.getMetalIncomeTriggered()
    return state.metalIncomeTriggered
end

function DataManager.getLastMetalAmount()
    return state.lastMetalAmount
end

function DataManager.getLastMetalCheckTime()
    return state.lastMetalCheckTime
end

function DataManager.getTrackedTeamID()
    return state.trackedTeamID
end

function DataManager.setTrackedTeamID(teamID)
    state.trackedTeamID = teamID
end

-- Player aggression
function DataManager.getPlayerEcoAttractionsRaw()
    return state.playerEcoAttractionsRaw
end

function DataManager.getPlayerTeams()
    return state.playerTeams
end

function DataManager.setPlayerTeams(teams)
    state.playerTeams = teams
end

return DataManager

