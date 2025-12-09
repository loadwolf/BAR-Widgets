-- Utility functions module
local Utils = {}

-- Format time as "Xm Ys" or "Zs"
function Utils.formatTime(seconds)
    if not seconds or seconds <= 0 then
        return "0s"
    end
    local minutes = math.floor(seconds / 60)
    local secs = math.floor(seconds % 60)
    if minutes > 0 and secs > 0 then
        return string.format("%dm %ds", minutes, secs)
    elseif minutes > 0 then
        return string.format("%dm", minutes)
    else
        return string.format("%ds", secs)
    end
end

-- Format metal income (e.g., 1K, 1.5M)
function Utils.formatMetalIncome(amount)
    if not amount or amount < 0 then
        return "0"
    end
    if amount >= 1000000 then
        return string.format("%.1fM", amount / 1000000)
    elseif amount >= 1000 then
        return string.format("%.1fK", amount / 1000)
    else
        return string.format("%.0f", amount)
    end
end

-- Get player name for a team
function Utils.getPlayerName(teamID)
    if not teamID or teamID < 0 then
        return nil
    end
    
    -- Try multiple methods to get player name
    
    -- Method 1: GetPlayerList with active players only
    local players = Spring.GetPlayerList(teamID, true) or {}
    if #players >= 1 then
        for _, playerID in ipairs(players) do
            local name, active, spectator = Spring.GetPlayerInfo(playerID)
            if name and name ~= "" and active and not spectator then
                return name
            end
        end
    end
    
    -- Method 2: GetPlayerList without active filter (includes all players)
    local allPlayers = Spring.GetPlayerList(teamID) or {}
    if #allPlayers >= 1 then
        for _, playerID in ipairs(allPlayers) do
            local name, active, spectator = Spring.GetPlayerInfo(playerID)
            if name and name ~= "" then
                -- Accept any player with a name, even if inactive/spectator
                return name
            end
        end
    end
    
    -- Method 3: Try AI name as fallback
    local success, aiName = pcall(Spring.GetAIInfo, teamID)
    if success and aiName and aiName ~= "" then
        return aiName
    end
    
    -- Method 4: Try GetTeamInfo for team name
    local success2, teamInfo = pcall(Spring.GetTeamInfo, teamID)
    if success2 and teamInfo then
        local teamName = teamInfo.name
        if teamName and teamName ~= "" then
            return teamName
        end
    end
    
    return nil  -- Return nil so caller can handle "Unknown"
end

-- Get player name from unit ID (alternative method)
function Utils.getPlayerNameFromUnit(unitID)
    if not unitID then
        return nil
    end
    
    local unitTeam = Spring.GetUnitTeam(unitID)
    if unitTeam and unitTeam >= 0 then
        return Utils.getPlayerName(unitTeam)
    end
    
    return nil
end

return Utils

