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
    
    -- Record kill first
    if attackerTeam and attackerTeam >= 0 then
        DataManager.addKill(attackerTeam)
        Spring.Echo(string.format("[Queen Death] Recorded kill for teamID=%d, total kills=%d", 
            attackerTeam, DataManager.getKillCount(attackerTeam)))
    else
        Spring.Echo(string.format("[Queen Death] WARNING: Invalid attackerTeam=%s", tostring(attackerTeam)))
    end
    
    -- Try multiple methods to get killer name
    local killerName = nil
    
    -- Method 1: Try to get name from attacker unit ID if available
    if attackerID and attackerID > 0 then
        killerName = Utils.getPlayerNameFromUnit(attackerID)
        if killerName then
            Spring.Echo(string.format("[Queen Death] Got killer name from attacker unit: %s", killerName))
        end
    end
    
    -- Method 2: Try to get name from team ID
    if not killerName and attackerTeam and attackerTeam >= 0 then
        killerName = Utils.getPlayerName(attackerTeam)
        if killerName then
            Spring.Echo(string.format("[Queen Death] Got killer name from team: %s", killerName))
        end
    end
    
    -- Method 3: Fallback to "Team X" if we have a team ID but no name
    if not killerName and attackerTeam and attackerTeam >= 0 then
        killerName = "Team " .. tostring(attackerTeam)
        Spring.Echo(string.format("[Queen Death] Using fallback name: %s", killerName))
    end
    
    -- Final fallback
    if not killerName then
        killerName = "Unknown"
        Spring.Echo("[Queen Death] WARNING: Could not determine killer name, using 'Unknown'")
    end
    
    local killerCount = DataManager.getKillCount(attackerTeam) or 0
    
    Spring.Echo(string.format("[Queen Death] Killer: %s (teamID=%s, count=%d)", 
        killerName, tostring(attackerTeam), killerCount))
    
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
    
    -- Log to file
    Logger.log("queen_death", pingText, {}, now, Utils.formatTime)
    
    Spring.Echo("[Queen Death Display API] " .. pingText)
    
    -- Generate CSV leaderboard after each queen kill
    QueenTracker.generateCSV()
    
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
        local deathSounds = {
            "sounds/alarm.wav",
            "sounds/ui/warning1.wav",
            "sounds/ui/warning2.wav",
            "sounds/beep6.wav",
        }
        for _, soundName in ipairs(deathSounds) do
            if Spring.PlaySoundFile(soundName, 0.7) then
                break
            end
        end
    end
end

function QueenTracker.buildLeaderboard()
    local leaderboard = {}
    local teamKills = DataManager.getTeamKills()
    
    -- Quick check: if table is empty, return empty leaderboard (no debug spam)
    local hasKills = false
    for teamID, kills in pairs(teamKills) do
        if kills and kills > 0 then
            hasKills = true
            local playerName = Utils.getPlayerName(teamID)
            table.insert(leaderboard, {
                teamID = teamID,
                name = playerName or "Unknown",
                kills = kills
            })
        end
    end
    
    -- Only log debug messages if there are actual kills (reduces spam before queens arrive)
    if hasKills then
        -- Debug: Print all entries being added
        for _, entry in ipairs(leaderboard) do
            Spring.Echo(string.format("[Leaderboard Debug] Adding teamID=%d, kills=%d, name=%s", 
                entry.teamID, entry.kills, entry.name))
        end
        
        -- Sort by kills (descending)
        table.sort(leaderboard, function(a, b)
            return a.kills > b.kills
        end)
        
        Spring.Echo(string.format("[Leaderboard Debug] Final leaderboard size: %d", #leaderboard))
    end
    
    return leaderboard
end

function QueenTracker.generateCSV()
    local leaderboard = QueenTracker.buildLeaderboard()
    
    if #leaderboard == 0 then
        Spring.Echo("[Queen Death Display API] No queen kills recorded - skipping CSV generation")
        return
    end
    
    -- Create date-based subfolder if it doesn't exist
    local dateFolder = Logger.getDateFolder()
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

