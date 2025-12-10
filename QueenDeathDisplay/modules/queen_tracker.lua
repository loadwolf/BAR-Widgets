-- Queen Tracker module - Handles queen death tracking and leaderboard
local QueenTracker = {}
local DataManager = nil
local Logger = nil
local Utils = nil
local TimerManager = nil

function QueenTracker.init(dataMgr, logger, utils, timerMgr)
    DataManager = dataMgr
    Logger = logger
    Utils = utils
    TimerManager = timerMgr
end

function QueenTracker.onUnitDestroyed(unitID, unitDefID, unitTeam, attackerID, attackerDefID, attackerTeam)
    if not DataManager.isQueenDefID(unitDefID) then
        return
    end
    
    -- Get position
    local x, y, z = Spring.GetUnitPosition(unitID)
    
    -- Resolve killer team with fallbacks
    local killerTeam = attackerTeam
    if (not killerTeam or killerTeam < 0) and attackerID and attackerID > 0 then
        killerTeam = Spring.GetUnitTeam(attackerID)
    end
    
    -- Record kill first
    if killerTeam and killerTeam >= 0 then
        DataManager.addKill(killerTeam)
    end
    
    -- Try multiple methods to get killer name
    local killerName = nil
    
    -- Method 1: Try to get name from attacker unit ID if available
    if attackerID and attackerID > 0 then
        killerName = Utils.getPlayerNameFromUnit(attackerID)
    end
    
    -- Method 2: Try to get name from team ID
    if not killerName and killerTeam and killerTeam >= 0 then
        killerName = Utils.getPlayerName(killerTeam)
    end
    
    -- Method 3: Fallback to "Team X" if we have a team ID but no name
    if not killerName and killerTeam and killerTeam >= 0 then
        killerName = "Team " .. tostring(killerTeam)
    end
    
    -- Final fallback
    if not killerName then
        killerName = "Unknown"
    end
    
    local killerCount = DataManager.getKillCount(killerTeam) or 0
    
    -- Get queen totals
    local totalQueens, killedQueens, remaining = TimerManager.getQueenTotals()
    
    -- Create death message
    local now = Spring.GetGameSeconds()
    local pingText = string.format("Queen Killed by %s #%d", killerName, killerCount)
    
    if remaining and remaining >= 0 then
        if remaining > 0 then
            pingText = pingText .. string.format(" (%d remaining)", remaining)
        else
            pingText = pingText .. " (ALL DEFEATED!)"
        end
    end
    
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
    
    -- Add to messages list
    DataManager.addDeathMessage({
        time = now,
        pingText = pingText,
        valuesText = {},
        killerName = killerName,
        killerCount = killerCount,
        totalQueens = totalQueens,
        killedQueens = killedQueens,
        remaining = remaining,
        dismissed = false,
        messageType = "queen_death"
    })
    
    -- REMOVED: Logger.log call (logging disabled)
    
    -- REMOVED: Automatic CSV generation (now manual via web interface button)
    
    -- Ping on map
    if x and y and z then
        -- Check if we're spectating and warn about visibility limitation (only once)
        local isSpectating = Spring.GetSpectatingState()
        local myTeamID = Spring.GetMyTeamID()
        
        if isSpectating and not DataManager.getSpectatorWarningShown() then
            Spring.Echo("[Queen Death Display API] WARNING: Spectator mode detected")
            Spring.Echo("[Queen Death Display API] Pings created by spectators may have limited visibility.")
            DataManager.setSpectatorWarningShown(true)
        end
        
        -- Create marker
        Spring.MarkerAddPoint(x, y, z, pingText, true)
        
        -- Play sound for queen death
        Spring.PlaySoundFile("sounds/ui/teleport-charge-loop.wav", 0.7)
    end
end

function QueenTracker.buildLeaderboard()
    local leaderboard = {}
    local teamKills = DataManager.getTeamKills()
    
    for teamID, kills in pairs(teamKills) do
        if kills and kills > 0 then
            local playerName = Utils.getPlayerName(teamID)
            table.insert(leaderboard, {
                teamID = teamID,
                name = playerName or "Unknown",
                kills = kills
            })
        end
    end
    
    -- Sort by kills (descending)
    table.sort(leaderboard, function(a, b)
        return a.kills > b.kills
    end)
    
    return leaderboard
end

function QueenTracker.generateCSV()
    local leaderboard = QueenTracker.buildLeaderboard()
    
    if #leaderboard == 0 then
        Spring.Echo("[Queen Death Display API] No queen kills recorded - skipping CSV generation")
        return
    end
    
    -- Create date-based subfolder if it doesn't exist (replacing Logger.getDateFolder)
    -- Note: This function is no longer called automatically, only via web interface
    local dateStr = os.date("%Y-%m-%d")
    local dateFolder = "LuaUI/Widgets/QueenDeathDisplay/" .. dateStr .. "/"
    Spring.CreateDir(dateFolder)
    
    local timestamp = os.date("%Y%m%d_%H%M%S")
    local filename = dateFolder .. "queen_kills_leaderboard_" .. timestamp .. ".csv"
    local csvFile = io.open(filename, "w")
    
    if not csvFile then
        Spring.Echo("[Queen Death Display API] WARNING: Could not create CSV file: " .. filename)
        return
    end
    
    -- Write CSV header
    csvFile:write("Rank,Player Name,Team ID,Kills\n")
    
    -- Write leaderboard entries
    for rank, entry in ipairs(leaderboard) do
        local playerName = entry.name:gsub(",", " ")
        csvFile:write(string.format("%d,%s,%d,%d\n", rank, playerName, entry.teamID, entry.kills))
    end
    
    csvFile:close()
    Spring.Echo(string.format("[Queen Death Display API] Kill leaderboard CSV saved to: %s", filename))
end

return QueenTracker

