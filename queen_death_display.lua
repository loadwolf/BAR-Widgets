function widget:GetInfo()
    return {
        name    = "Queen Death Display",
        desc    = "Shows queen death info on screen and pings on map",
        author  = "Auto",
        date    = "2025-01-XX",
        version = "1.0",
        layer   = 0,
        enabled = true,
        handler = true,
    }
end

local Spring = Spring

local TARGET_UNITDEF_NAMES = {
    "raptor_queen_easy", "raptor_queen_veryeasy",
    "raptor_queen_hard", "raptor_queen_veryhard",
    "raptor_queen_epic",
    "raptor_queen_normal",
}

local raptorQueenDefIDs = {}
for _, name in ipairs(TARGET_UNITDEF_NAMES) do
    local def = UnitDefNames[name]
    if def then
        raptorQueenDefIDs[def.id] = true
    end
end

-- Track queen kills per team
local teamKills = {}

-- Display state
local deathMessages = {}  -- Table of {time, text, values, dismissed, messageType}
local MESSAGE_DURATION = 10  -- seconds (no longer used to hide, panel is always visible)
local MAX_MESSAGES = 10
local hasRealNotification = false  -- Track if we've had at least one real notification
local showLeaderboard = false  -- Show kill leaderboard when all queens defeated
local leaderboardShown = false  -- Track if we've already shown the leaderboard

-- Logging
local LOG_DIR = "LuaUI/Widgets/QueenDeathDisplay/"
local logFile = nil

-- Metal income tracking
local metalIncomeThresholds = {100, 200, 500, 1000, 2000,3000,4000, 5000,6000,7000,8000,9000, 10000,15000, 20000,30000,40000, 50000, 100000, 200000, 500000, 1000000, 2000000,5000000,10000000,50000000,100000000, }  -- Metal per second thresholds
local metalIncomeTriggered = {}  -- Track which thresholds have been triggered (per team: metalIncomeTriggered[teamID][threshold] = true)
local lastMetalAmount = {}  -- Track last metal amount per team: lastMetalAmount[teamID] = amount
local lastMetalCheckTime = {}  -- Track last check time per team: lastMetalCheckTime[teamID] = time
local trackedTeamID = nil  -- Team ID we're currently tracking

-- Panel position (draggable)
local panelX = 20
local panelY = nil  -- Will be set in Initialize based on screen size
local panelDragging = false
local panelDragDX = 0
local panelDragDY = 0

-- Spring shortcuts (define early so they can be used in functions defined later)
local GetPlayerList = Spring.GetPlayerList
local GetPlayerInfo = Spring.GetPlayerInfo
local GetGameRulesParam = Spring.GetGameRulesParam
local GetModOptions = Spring.GetModOptions
local GetGameSeconds = Spring.GetGameSeconds
local GetUnitPosition = Spring.GetUnitPosition
local MarkerAddPoint = Spring.MarkerAddPoint
local GetTeamResources = Spring.GetTeamResources
local GetMyTeamID = Spring.GetMyTeamID
local GetSpectatingState = Spring.GetSpectatingState
local GetTeamList = Spring.GetTeamList
local GetGaiaTeamID = Spring.GetGaiaTeamID
local PlaySoundFile = Spring.PlaySoundFile

-- VFS for listing files
local VFS = VFS

-- Format time as "Xm Ys" or "Zs"
local function formatTime(seconds)
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

-- Text-to-speech function (cross-platform)
-- Note: os.execute is not available in Spring RTS widgets, so TTS is disabled
local function speakText(text)
    if not text or text == "" then
        return
    end
    
    -- os.execute is not available in Spring RTS widget environment
    -- TTS functionality is disabled for security/sandboxing reasons
    -- The notification will still appear on screen and in logs
    
    -- Uncomment below if you want to try (will likely fail):
    --[[
    if not os.execute then
        return  -- os.execute not available
    end
    
    -- Escape quotes and special characters for shell commands
    local escapedText = string.gsub(text, '"', '\\"')
    escapedText = string.gsub(escapedText, "'", "\\'")
    
    -- Try Windows PowerShell TTS first (most common)
    local command = string.format('powershell -Command "Add-Type -AssemblyName System.Speech; $speak = New-Object System.Speech.Synthesis.SpeechSynthesizer; $speak.Speak(\'%s\')"', escapedText)
    local success, result = pcall(os.execute, command)
    
    -- If PowerShell fails, try alternative methods
    if not success or (result and result ~= 0) then
        -- Try Windows SAPI directly
        command = string.format('powershell -Command "$sapi = New-Object -ComObject SAPI.SpVoice; $sapi.Speak(\'%s\')"', escapedText)
        pcall(os.execute, command)
    end
    --]]
end

-- Initialize log file
local function initLogFile()
    Spring.CreateDir(LOG_DIR)
    local timestamp = os.date("%Y%m%d_%H%M%S")
    local filename = LOG_DIR .. "notifications_" .. timestamp .. ".log"
    logFile = io.open(filename, "w")
    if logFile then
        logFile:write("Queen Death Display - Notification Log\n")
        logFile:write("Started: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n")
        logFile:write("========================================\n\n")
        Spring.Echo("[Queen Death Display] Logging to: " .. filename)
    else
        Spring.Echo("[Queen Death Display] WARNING: Could not open log file: " .. filename)
    end
end

-- Write notification to log file
local function logNotification(messageType, pingText, valuesText)
    if not logFile then return end
    
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local gameTime = GetGameSeconds()
    local gameTimeFormatted = formatTime(gameTime)
    
    -- Just log the ping text - no verbose details (they're duplicates)
    logFile:write(string.format("[%s] Game Time: %s | %s\n", timestamp, gameTimeFormatted, pingText))
    logFile:write("\n")
    logFile:flush()  -- Ensure it's written immediately
end

-- List available sound files in common directories
local function listAvailableSounds()
    if not VFS or not VFS.DirList then
        Spring.Echo("[Queen Death Display] VFS.DirList not available - cannot list sound files")
        return {}
    end
    
    local soundFiles = {}
    local searchDirs = {
        "sounds",
        "Sounds",
        "sounds/voice",
        "Sounds/voice",
        "sounds/commands",
        "Sounds/commands",
        "sounds/ui",
        "Sounds/ui",
    }
    
    local extensions = {"*.wav", "*.ogg", "*.mp3", "*.flac"}
    
    Spring.Echo("[Queen Death Display] === Searching for sound files ===")
    
    for _, dir in ipairs(searchDirs) do
        for _, ext in ipairs(extensions) do
            local files = VFS.DirList(dir, ext, VFS.RAW_FIRST)
            if files and #files > 0 then
                Spring.Echo(string.format("[Queen Death Display] Found %d files in %s/%s:", #files, dir, ext))
                for i, file in ipairs(files) do
                    -- Extract just the filename
                    local filename = file:match("([^/\\]+)$") or file
                    table.insert(soundFiles, file)  -- Full path
                    Spring.Echo(string.format("  [%d] %s", i, filename))
                end
            end
        end
    end
    
    -- Also try searching for voice-related files
    local seenFiles = {}
    for _, file in ipairs(soundFiles) do
        seenFiles[file] = true
    end
    
    local voicePatterns = {"*voice*", "*command*", "*beep*", "*click*", "*alert*", "*notify*"}
    for _, pattern in ipairs(voicePatterns) do
        for _, ext in ipairs(extensions) do
            local searchPattern = pattern .. ext:gsub("*", "")
            local files = VFS.DirList("sounds", searchPattern, VFS.RAW_FIRST)
            if not files or #files == 0 then
                files = VFS.DirList("Sounds", searchPattern, VFS.RAW_FIRST)
            end
            if files and #files > 0 then
                Spring.Echo(string.format("[Queen Death Display] Found %d files matching '%s':", #files, searchPattern))
                for i, file in ipairs(files) do
                    local filename = file:match("([^/\\]+)$") or file
                    if not seenFiles[file] then  -- Avoid duplicates
                        seenFiles[file] = true
                        table.insert(soundFiles, file)
                        Spring.Echo(string.format("  [%d] %s", #soundFiles, filename))
                    end
                end
            end
        end
    end
    
    Spring.Echo(string.format("[Queen Death Display] === Total sound files found: %d ===", #soundFiles))
    
    -- Write to log file if available
    if logFile then
        logFile:write("\n=== Available Sound Files ===\n")
        logFile:write("(VFS paths - use these with Spring.PlaySoundFile)\n\n")
        for i, file in ipairs(soundFiles) do
            local filename = file:match("([^/\\]+)$") or file
            logFile:write(string.format("%d. %s\n", i, file))
            logFile:write(string.format("   Filename: %s\n", filename))
        end
        logFile:write("\n=============================\n")
        logFile:write("To use a sound file, call: Spring.PlaySoundFile(\"path\", volume)\n")
        logFile:write("Example: Spring.PlaySoundFile(\"sounds/voice/attack.wav\", 1.0)\n")
        logFile:write("=============================\n\n")
        logFile:flush()
    end
    
    return soundFiles
end

function widget:Initialize()
    Spring.Echo("[Queen Death Display] Widget initialized")
    -- Initialize panel position (in bottom-up coordinates like LayoutPlannerPlus)
    local vsx, vsy = gl.GetViewSizes()
    -- Center vertically on left side (middle of screen)
    panelY = vsy / 2  -- Bottom-up: Y increases upward from bottom, so vsy/2 is middle
    -- Initialize log file
    initLogFile()
    
    -- Play test sound to confirm widget is working
    -- Try common Spring RTS sound files
    local soundFiles = {
        "beep4",
        "beep",
        "buttonclick",
        "click1",
    }
    local soundPlayed = false
    for _, soundName in ipairs(soundFiles) do
        if PlaySoundFile(soundName, 0.5) then
            soundPlayed = true
            Spring.Echo("[Queen Death Display] Test sound played: " .. soundName)
            break
        end
    end
    if not soundPlayed then
        Spring.Echo("[Queen Death Display] Could not play test sound (no sound files found)")
    end
    
    -- Add a test notification to confirm widget is working
    local now = GetGameSeconds()
    table.insert(deathMessages, {
        time = now,
        pingText = "Queen Death Display - Widget Active",
        valuesText = {"Test notification - Widget is working!"},
        killerName = nil,
        killerCount = 0,
        totalQueens = nil,
        killedQueens = 0,
        remaining = nil,
        dismissed = false,
        messageType = "system"
    })
    
    -- Log test notification
    logNotification("system", "Widget initialized and ready", {"Test notification displayed"})
    
    Spring.Echo("[Queen Death Display] Test notification displayed - Widget is working!")
    
    -- List available sound files (run once on startup)
    Spring.Echo("[Queen Death Display] Listing available sound files...")
    listAvailableSounds()
end

function widget:Shutdown()
    if logFile then
        logFile:write("\n========================================\n")
        logFile:write("Ended: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n")
        logFile:close()
        logFile = nil
    end
end

-- No shortcuts needed, use gl directly

-- Get player name for a team
local function getKillerName(teamID)
    if not teamID or teamID < 0 then
        return nil
    end
    local players = GetPlayerList(teamID) or {}
    if #players >= 1 then
        local name = select(1, GetPlayerInfo(players[1]))
        if name and name ~= "" then
            return name
        end
    end
    return "Team " .. tostring(teamID)
end

-- Format metal income (e.g., 1K, 1.5M)
local function formatMetalIncome(amount)
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

-- Get queen totals
local function getQueenTotals()
    local rulesTotal = GetGameRulesParam("raptorQueenCount")
    local rulesKilled = GetGameRulesParam("raptorQueensKilled")
    local modOpts = GetModOptions()
    local optTotal = nil
    if modOpts and modOpts.raptor_queen_count then
        optTotal = tonumber(modOpts.raptor_queen_count)
    end
    
    local totalQueens = rulesTotal or optTotal
    local killedQueens = rulesKilled or 0
    local remaining = nil
    if totalQueens and totalQueens > 0 then
        remaining = totalQueens - killedQueens
    end
    
    return totalQueens, killedQueens, remaining
end

-- Get timer information
local function getTimerInfo()
    local now = GetGameSeconds()
    
    -- Grace period (no rush timer)
    local gracePeriod = GetGameRulesParam("raptorGracePeriod")
    local graceRemaining = nil
    if gracePeriod then
        graceRemaining = math.max(0, gracePeriod - now)
    end
    
    -- Queen arrival ETA
    local anger = GetGameRulesParam("raptorQueenAnger")
    local angerGainBase = GetGameRulesParam("RaptorQueenAngerGain_Base") or 0
    local angerGainAggression = GetGameRulesParam("RaptorQueenAngerGain_Aggression") or 0
    local angerGainEco = GetGameRulesParam("RaptorQueenAngerGain_Eco") or 0
    local queenETA = nil
    
    -- Only calculate ETA if grace period has ended and anger < 100
    if gracePeriod and now > gracePeriod and anger and anger < 100 then
        local totalGainRate = angerGainBase + angerGainAggression + angerGainEco
        if totalGainRate > 0 then
            local angerRemaining = 100 - anger
            queenETA = angerRemaining / totalGainRate
        end
    end
    
    -- Remaining queens
    local _, _, remaining = getQueenTotals()
    
    -- Check if all queens are defeated
    if remaining and remaining == 0 and not leaderboardShown then
        showLeaderboard = true
        leaderboardShown = true
    end
    
    return graceRemaining, queenETA, remaining
end

-- Build kill leaderboard from teamKills
local function buildKillLeaderboard()
    local leaderboard = {}
    
    -- Convert teamKills to leaderboard entries
    for teamID, kills in pairs(teamKills) do
        if kills > 0 then
            local playerName = getKillerName(teamID)
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

-- Add a death message to display
local function addDeathMessage(killerName, killerCount, totalQueens, killedQueens, remaining)
    local now = GetGameSeconds()
    
    -- Build the ping text - Format: "Queen Killed by PlayerName #2 (18 remaining)"
    -- Killer will always be available, so always show it
    local pingText = string.format("Queen Killed by %s #%d", killerName or "Unknown", killerCount or 0)
    
    -- ALWAYS add remaining info (this is the main requirement!)
    if remaining and remaining >= 0 then
        if remaining > 0 then
            pingText = pingText .. string.format(" (%d remaining)", remaining)
        else
            pingText = pingText .. " (ALL DEFEATED!)"
        end
    end
    
    -- Debug: verify ping text has all required info
    Spring.Echo(string.format("[Queen Death] PING TEXT: '%s'", pingText))
    
    -- Build detailed values text for display (commented out - main ping text is sufficient)
    local valuesText = {}
    -- table.insert(valuesText, string.format("Killer: %s", killerName or "Unknown"))
    -- if killerCount > 0 then
    --     table.insert(valuesText, string.format("Player Kills: %d", killerCount))
    -- end
    -- if totalQueens then
    --     table.insert(valuesText, string.format("Total Queens: %d", totalQueens))
    -- end
    -- if killedQueens then
    --     table.insert(valuesText, string.format("Queens Killed: %d", killedQueens))
    -- end
    -- if remaining then
    --     table.insert(valuesText, string.format("Queens Remaining: %d", remaining))
    -- end
    
    -- Remove placeholder message if this is the first real notification
    if not hasRealNotification then
        hasRealNotification = true
        -- Remove any system placeholder messages
        for i = #deathMessages, 1, -1 do
            if deathMessages[i].messageType == "system" then
                table.remove(deathMessages, i)
            end
        end
    end
    
    -- Add to messages list
    table.insert(deathMessages, {
        time = now,
        pingText = pingText,
        valuesText = valuesText,
        killerName = killerName,
        killerCount = killerCount,
        totalQueens = totalQueens,
        killedQueens = killedQueens,
        remaining = remaining,
        dismissed = false,
        messageType = "queen_death"
    })
    
    -- Log to file
    logNotification("queen_death", pingText, valuesText)
    
    -- Limit message count
    if #deathMessages > MAX_MESSAGES then
        table.remove(deathMessages, 1)
    end
    
    return pingText
end

function widget:UnitDestroyed(unitID, unitDefID, unitTeam, attackerID, attackerDefID, attackerTeam)
    local unitDef = UnitDefs[unitDefID]
    if not unitDef then return end

    if raptorQueenDefIDs[unitDefID] then
        -- Get position - should work even in spectator mode when unit is destroyed
        local x, y, z = GetUnitPosition(unitID)
        
        -- Determine killer name and per-team kill count
        -- Debug: log attacker info
        Spring.Echo(string.format("[Queen Death] DEBUG: attackerTeam=%s, attackerID=%s, unitTeam=%s", 
            tostring(attackerTeam), tostring(attackerID), tostring(unitTeam)))
        
        local killerName = getKillerName(attackerTeam)
        if killerName and attackerTeam and attackerTeam >= 0 then
            teamKills[attackerTeam] = (teamKills[attackerTeam] or 0) + 1
        end
        local killerCount = (attackerTeam and teamKills[attackerTeam]) or 0
        
        -- Debug: log killer info
        Spring.Echo(string.format("[Queen Death] DEBUG: killerName=%s, killerCount=%d", 
            tostring(killerName), killerCount))

        -- Get queen totals
        local totalQueens, killedQueens, remaining = getQueenTotals()
        
        -- Create ping text and add to display
        local pingText = addDeathMessage(killerName, killerCount, totalQueens, killedQueens, remaining)
        
        -- Debug output
        Spring.Echo("[Queen Death] " .. pingText)
        if x and y and z then
            Spring.Echo("[Queen Death] Position: " .. tostring(x) .. ", " .. tostring(y) .. ", " .. tostring(z))
        else
            Spring.Echo("[Queen Death] WARNING: No position available for unit " .. tostring(unitID))
        end
        
        -- Ping on map - THIS IS THE MAIN REQUIREMENT!
        -- Second parameter: false = local only, true = visible to all players
        -- Always use true so all players can see queen death pings
        if x and y and z then
            -- Verify ping text has required info before creating ping
            if not pingText or pingText == "" then
                Spring.Echo("[Queen Death] ERROR: pingText is empty!")
                pingText = "Queen Killed"  -- Fallback
            end
            -- Ensure remaining count is in ping text (MAIN REQUIREMENT!)
            if not string.find(pingText, "remaining") and not string.find(pingText, "DEFEATED") then
                Spring.Echo("[Queen Death] WARNING: pingText missing remaining count! Adding it...")
                if remaining and remaining >= 0 then
                    if remaining > 0 then
                        pingText = pingText .. string.format(" (%d remaining)", remaining)
                    else
                        pingText = pingText .. " (ALL DEFEATED!)"
                    end
                end
            end
            MarkerAddPoint(x, y, z, pingText, true)
            Spring.Echo(string.format("[Queen Death] Map ping created: '%s' at (%s, %s)", pingText, tostring(x), tostring(z)))
        else
            Spring.Echo("[Queen Death] WARNING: Could not create map ping - no position")
        end
    end
end

function widget:DrawScreen()
    gl.Color(1, 1, 1, 1)
    gl.Blending(true)
    gl.DepthTest(false)
    
    local vsx, vsy = gl.GetViewSizes()
    local now = GetGameSeconds()
    
    -- Only show placeholder if we haven't had any real notifications yet
    if not hasRealNotification and #deathMessages == 0 then
        table.insert(deathMessages, {
            time = now,
            pingText = "Queen Death Display Active",
            valuesText = {"Waiting for queen death..."},
            killerName = nil,
            killerCount = 0,
            totalQueens = nil,
            killedQueens = 0,
            remaining = nil,
            dismissed = false,
            messageType = "system"
        })
    end
    
    -- Get timer info
    local graceRemaining, queenETA, remainingQueens = getTimerInfo()
    
    -- Check if we should show leaderboard
    if showLeaderboard and remainingQueens == 0 then
        -- Leaderboard will be drawn below the main panel
    end
    
    -- Update panel Y if screen size changed (bottom-up coordinates)
    if not panelY or panelY < 50 then
        panelY = vsy / 2  -- Center vertically on left side
    end
    
    -- Display panel (positioned by dragging) - wider to fit large text
    local panelW = 450  -- Increased width for large timer text
    local lineHeight = 20
    local padding = 10
    
    -- Calculate panel height (include header + timer section)
    local headerHeight = 20
    local timerTopPadding = 30  -- Extra space between header and timers
    local timerSectionHeight = 0
    if graceRemaining or queenETA or remainingQueens then
        timerSectionHeight = padding  -- No "=== TIMERS ===" label anymore
        if graceRemaining and graceRemaining > 0 then
            timerSectionHeight = timerSectionHeight + 50  -- Large text (44px) + spacing
        end
        if queenETA then
            timerSectionHeight = timerSectionHeight + 50 + 40  -- Large text (44px) + spacing + extra 40px
        end
        if remainingQueens then
            timerSectionHeight = timerSectionHeight + 50 + 40  -- Large text (44px) + spacing + extra 40px
        end
    end
    
    local totalHeight = headerHeight + padding * 2 + timerTopPadding + timerSectionHeight
    for i = 1, #deathMessages do
        totalHeight = totalHeight + lineHeight * (1 + #deathMessages[i].valuesText) + 5
    end
    
    -- Draw background (convert panelY from bottom-up to gl.Rect coordinates)
    gl.Color(0, 0, 0, 0.7)
    gl.Rect(panelX, panelY - totalHeight, panelX + panelW, panelY)
    
    -- Draw border
    gl.Color(1, 0.5, 0, 1)
    gl.Rect(panelX, panelY - totalHeight, panelX + panelW, panelY - totalHeight + 2)
    gl.Rect(panelX, panelY - 2, panelX + panelW, panelY)
    gl.Rect(panelX, panelY - totalHeight, panelX + 2, panelY)
    gl.Rect(panelX + panelW - 2, panelY - totalHeight, panelX + panelW, panelY)
    
    -- Draw header section at very top
    local headerHeight = 20
    gl.Color(0.1, 0.1, 0.1, 0.95)
    gl.Rect(panelX + 2, panelY - headerHeight, panelX + panelW - 2, panelY)
    gl.Color(1, 0.7, 0.2, 1)
    gl.Text("Queen Death Display", panelX + padding, panelY - 15, 12, "")  -- Moved down 15 pixels
    
    -- Draw timer section below header (start after header + extra padding to move timers down)
    local timerTopPadding = 30  -- Extra space between header and timers
    local currentY = panelY - headerHeight - padding - timerTopPadding
    if timerSectionHeight > 0 then
        gl.Color(0.2, 0.2, 0.2, 0.8)
        gl.Rect(panelX + 2, currentY - timerSectionHeight + padding, panelX + panelW - 2, currentY)
        
        -- Remove "=== TIMERS ===" label to avoid overlap with large numbers
        -- Start directly with the timer values
        
        if graceRemaining and graceRemaining > 0 then
            -- Large text for No Rush (4x size = 44px) - just the time value
            gl.Color(0.5, 1, 0.5, 1)
            gl.Text(formatTime(graceRemaining), panelX + padding + 10, currentY, 44, "o")
            currentY = currentY - 50  -- Extra spacing for large text
        end
        
        if queenETA then
            -- Large text for Queens Arrive (4x size = 44px) - just the time value
            -- Add 40 pixels spacing before this one
            currentY = currentY - 40
            gl.Color(1, 0.8, 0, 1)
            gl.Text(formatTime(queenETA), panelX + padding + 10, currentY, 44, "o")
            currentY = currentY - 50  -- Extra spacing for large text
        elseif remainingQueens then
            -- Large text for Queens Remaining (4x size = 44px) - just the count
            -- Add 40 pixels spacing before this one (like queen arrival)
            currentY = currentY - 40
            gl.Color(1, 0.5, 0.5, 1)
            if remainingQueens > 0 then
                gl.Text(tostring(remainingQueens), panelX + padding + 10, currentY, 44, "o")
            else
                gl.Text("ALL DEFEATED!", panelX + padding + 10, currentY, 44, "o")
            end
            currentY = currentY - 50  -- Extra spacing for large text
        end
        
        currentY = currentY - 5  -- Spacing before death messages
    end
    
    -- Draw messages (newest at top)
    local dismissButtonSize = 16
    local dismissButtonX = panelX + padding  -- Start of line (left side)
    local textStartX = dismissButtonX + dismissButtonSize + 5  -- Text starts after button
    
    for i = #deathMessages, 1, -1 do
        local msg = deathMessages[i]
        if not msg.dismissed then
            local alpha = 1.0  -- Keep fully visible at all times
            local msgStartY = currentY
            
            -- Draw dismiss button at start of line (only for notifications, not system messages)
            if msg.messageType ~= "system" then
                -- Align button with text: text is 14px (size 14), button is 16px
                -- Text baseline is at currentY, text extends upward to currentY + ~14
                -- Position button so its center aligns with text center (text center at currentY + 7)
                -- Button center should be at currentY + 7, so button bottom at currentY - 1
                -- Move button 10 pixels higher for better alignment
                local textHeight = 14
                local buttonY = msgStartY - dismissButtonSize + (dismissButtonSize - textHeight) / 2 + 10  -- Center-align with text, moved higher
                
                -- Button background
                gl.Color(0.6, 0.2, 0.2, 0.9)
                gl.Rect(dismissButtonX, buttonY, dismissButtonX + dismissButtonSize, buttonY + dismissButtonSize)
                
                -- Button border
                gl.Color(0.8, 0.3, 0.3, 1)
                gl.LineWidth(1)
                gl.BeginEnd(GL.LINE_LOOP, function()
                    gl.Vertex(dismissButtonX, buttonY)
                    gl.Vertex(dismissButtonX + dismissButtonSize, buttonY)
                    gl.Vertex(dismissButtonX + dismissButtonSize, buttonY + dismissButtonSize)
                    gl.Vertex(dismissButtonX, buttonY + dismissButtonSize)
                end)
                
                -- X symbol
                gl.Color(1, 1, 1, 1)
                gl.LineWidth(2)
                gl.BeginEnd(GL.LINES, function()
                    gl.Vertex(dismissButtonX + 4, buttonY + 4)
                    gl.Vertex(dismissButtonX + dismissButtonSize - 4, buttonY + dismissButtonSize - 4)
                    gl.Vertex(dismissButtonX + dismissButtonSize - 4, buttonY + 4)
                    gl.Vertex(dismissButtonX + 4, buttonY + dismissButtonSize - 4)
                end)
            end
            
            -- Main ping text (larger, bold) - starts after button
            gl.Color(1, 0.8, 0, alpha)
            gl.Text(msg.pingText, textStartX, currentY, 14, "o")
            currentY = currentY - lineHeight - 2
            
            -- Values (smaller, white)
            gl.Color(1, 1, 1, alpha * 0.8)
            for _, valueLine in ipairs(msg.valuesText) do
                gl.Text(valueLine, textStartX + 10, currentY, 11, "n")
                currentY = currentY - lineHeight
            end
            
            currentY = currentY - 5  -- Spacing between messages
        end
    end
    
    gl.Color(1, 1, 1, 1)
    
    -- Draw leaderboard if all queens are defeated
    if showLeaderboard then
        local leaderboard = buildKillLeaderboard()
        if #leaderboard > 0 then
            -- Leaderboard panel (centered on screen)
            local lbW = 400
            local lbH = 100 + (#leaderboard * 25)  -- Header + entries
            local lbX = (vsx - lbW) / 2
            local lbY = vsy / 2 + lbH / 2  -- Center vertically (bottom-up coords)
            
            -- Background
            gl.Color(0, 0, 0, 0.9)
            gl.Rect(lbX, lbY - lbH, lbX + lbW, lbY)
            
            -- Border
            gl.Color(1, 0.8, 0, 1)
            gl.Rect(lbX, lbY - lbH, lbX + lbW, lbY - lbH + 3)
            gl.Rect(lbX, lbY - 3, lbX + lbW, lbY)
            gl.Rect(lbX, lbY - lbH, lbX + 3, lbY)
            gl.Rect(lbX + lbW - 3, lbY - lbH, lbX + lbW, lbY)
            
            -- Header
            gl.Color(1, 0.8, 0, 1)
            gl.Text("Queen Kill Leaderboard", lbX + lbW / 2, lbY - 20, 16, "oc")
            
            -- Table header
            gl.Color(1, 1, 1, 0.8)
            gl.Text("Rank", lbX + 20, lbY - 45, 12, "o")
            gl.Text("Player", lbX + 100, lbY - 45, 12, "o")
            gl.Text("Kills", lbX + lbW - 50, lbY - 45, 12, "or")
            
            -- Leaderboard entries
            local entryY = lbY - 70
            for i, entry in ipairs(leaderboard) do
                -- Rank
                local rankColor = {1, 1, 1, 0.9}
                if i == 1 then
                    rankColor = {1, 0.8, 0, 1}  -- Gold for #1
                elseif i == 2 then
                    rankColor = {0.8, 0.8, 0.8, 1}  -- Silver for #2
                elseif i == 3 then
                    rankColor = {0.7, 0.5, 0.3, 1}  -- Bronze for #3
                end
                
                gl.Color(rankColor[1], rankColor[2], rankColor[3], rankColor[4])
                gl.Text(tostring(i) .. ".", lbX + 20, entryY, 12, "o")
                
                -- Player name
                gl.Color(1, 1, 1, 0.9)
                gl.Text(entry.name, lbX + 100, entryY, 12, "o")
                
                -- Kill count
                gl.Color(1, 0.8, 0, 1)
                gl.Text(tostring(entry.kills), lbX + lbW - 50, entryY, 12, "or")
                
                entryY = entryY - 25
            end
        end
    end
end

function widget:MousePress(mx, my, button)
    if button ~= 1 then return false end  -- Only left mouse button
    
    -- Calculate panel bounds (using same logic as DrawScreen)
    local panelW = 450
    local lineHeight = 20
    local padding = 10
    local now = GetGameSeconds()
    local graceRemaining, queenETA, remainingQueens = getTimerInfo()
    
    -- Calculate panel height (same as DrawScreen - include header)
    local headerHeight = 20
    local timerTopPadding = 30  -- Extra space between header and timers
    local timerSectionHeight = 0
    if graceRemaining or queenETA or remainingQueens then
        timerSectionHeight = padding  -- No "=== TIMERS ===" label anymore
        if graceRemaining and graceRemaining > 0 then
            timerSectionHeight = timerSectionHeight + 50  -- Large text (44px) + spacing
        end
        if queenETA then
            timerSectionHeight = timerSectionHeight + 50 + 40  -- Large text (44px) + spacing + extra 40px
        end
        if remainingQueens then
            timerSectionHeight = timerSectionHeight + 50 + 40  -- Large text (44px) + spacing + extra 40px
        end
    end
    
    local totalHeight = headerHeight + padding * 2 + timerTopPadding + timerSectionHeight
    for i = 1, #deathMessages do
        totalHeight = totalHeight + lineHeight * (1 + #deathMessages[i].valuesText) + 5
    end
    
    -- Check if click is within panel bounds (panelY is in bottom-up coordinates)
    -- panelY is the TOP of the panel in bottom-up coords
    local panelTop = panelY
    local panelBottom = panelY - totalHeight
    
    -- First, check for dismiss button clicks (before panel dragging)
    if mx >= panelX and mx <= panelX + panelW and
       my >= panelBottom and my <= panelTop then
        
        -- Check each message's dismiss button
        -- Use EXACT same calculation as DrawScreen
        local dismissButtonSize = 16
        local dismissButtonX = panelX + padding
        local timerTopPadding = 30  -- Extra space between header and timers
        local currentY = panelY - headerHeight - padding - timerTopPadding
        
        -- Skip timer section (exact same as DrawScreen)
        if timerSectionHeight > 0 then
            if graceRemaining and graceRemaining > 0 then
                currentY = currentY - 50
            end
            if queenETA then
                currentY = currentY - 40 - 50
            elseif remainingQueens then
                currentY = currentY - 40 - 50
            end
            currentY = currentY - 5
        end
        
        -- Check messages (newest at top, same order as DrawScreen)
        for i = #deathMessages, 1, -1 do
            local msg = deathMessages[i]
            if not msg.dismissed then
                local msgStartY = currentY
                
                -- Only check dismiss button for non-system messages
                if msg.messageType ~= "system" then
                    -- EXACT same calculation as DrawScreen line 474
                    local textHeight = 14
                    local buttonY = msgStartY - dismissButtonSize + (dismissButtonSize - textHeight) / 2 + 10
                    
                    -- Check if click is on this button (with small tolerance for easier clicking)
                    if mx >= dismissButtonX - 2 and mx <= dismissButtonX + dismissButtonSize + 2 and
                       my >= buttonY - 2 and my <= buttonY + dismissButtonSize + 2 then
                        -- Dismiss this message
                        msg.dismissed = true
                        return true  -- Consume the click - don't allow dragging
                    end
                end
                
                -- Move to next message position (exact same as DrawScreen)
                currentY = currentY - lineHeight - 2  -- Main text
                for _ = 1, #msg.valuesText do
                    currentY = currentY - lineHeight  -- Value lines
                end
                currentY = currentY - 5  -- Spacing
            else
                -- Already dismissed - still need to account for its space
                currentY = currentY - lineHeight - 2
                for _ = 1, #msg.valuesText do
                    currentY = currentY - lineHeight
                end
                currentY = currentY - 5
            end
        end
        
        -- If we get here, click was in panel but not on a button - allow dragging
        -- But only if not clicking on header area (header should be draggable)
        if my < panelY - headerHeight then
            -- Click is below header, allow dragging
            panelDragging = true
            panelDragDX = mx - panelX
            panelDragDY = my - panelY  -- Both in bottom-up coordinates
            return true
        else
            -- Click is in header area, always allow dragging
            panelDragging = true
            panelDragDX = mx - panelX
            panelDragDY = my - panelY
            return true
        end
    end
    
    return false
end

function widget:MouseMove(mx, my, dx, dy, button)
    if not panelDragging then return false end
    
    local vsx, vsy = gl.GetViewSizes()
    
    -- Update panel position (like LayoutPlannerPlus - both in bottom-up coordinates)
    panelX = mx - panelDragDX
    panelY = my - panelDragDY
    
    -- Keep panel on screen (calculate totalHeight first - include header)
    local panelW = 450
    local lineHeight = 20
    local padding = 10
    local headerHeight = 20
    local now = GetGameSeconds()
    local graceRemaining, queenETA, remainingQueens = getTimerInfo()
    
    local timerTopPadding = 30  -- Extra space between header and timers
    local timerSectionHeight = 0
    if graceRemaining or queenETA or remainingQueens then
        timerSectionHeight = padding  -- No "=== TIMERS ===" label anymore
        if graceRemaining and graceRemaining > 0 then
            timerSectionHeight = timerSectionHeight + 50
        end
        if queenETA then
            timerSectionHeight = timerSectionHeight + 50 + 40  -- Extra 40px spacing
        end
        if remainingQueens then
            timerSectionHeight = timerSectionHeight + 50
        end
    end
    local totalHeight = headerHeight + padding * 2 + timerTopPadding + timerSectionHeight
    for i = 1, #deathMessages do
        totalHeight = totalHeight + lineHeight * (1 + #deathMessages[i].valuesText) + 5
    end
    
    -- Allow dragging fully to screen edges, with small safety margin
    if panelX < 0 then panelX = 0 end
    if panelX + panelW > vsx then panelX = vsx - panelW end
    if panelY > vsy - 5 then panelY = vsy - 5 end            -- near very top
    if panelY < totalHeight + 5 then panelY = totalHeight + 5 end  -- near very bottom
    
    return true
end

function widget:MouseRelease(mx, my, button)
    if button ~= 1 then return false end
    
    if panelDragging then
        panelDragging = false
        return true
    end
    
    return false
end

-- Add a metal income notification
local function addMetalIncomeNotification(income, threshold)
    local now = GetGameSeconds()
    local formattedIncome = formatMetalIncome(income)
    local formattedThreshold = formatMetalIncome(threshold)
    
    local pingText = string.format("Metal Income: %s/s (Reached %s/s)", formattedIncome, formattedThreshold)
    
    -- Remove placeholder message if this is the first real notification
    if not hasRealNotification then
        hasRealNotification = true
        -- Remove any system placeholder messages
        for i = #deathMessages, 1, -1 do
            if deathMessages[i].messageType == "system" then
                table.remove(deathMessages, i)
            end
        end
    end
    
    -- Build detailed values text for display (commented out - main ping text is sufficient)
    local valuesText = {}
    -- table.insert(valuesText, string.format("Current Income: %s/s", formattedIncome))
    -- table.insert(valuesText, string.format("Threshold: %s/s", formattedThreshold))
    
    table.insert(deathMessages, {
        time = now,
        pingText = pingText,
        valuesText = valuesText,
        killerName = nil,
        killerCount = 0,
        totalQueens = nil,
        killedQueens = 0,
        remaining = nil,
        dismissed = false,
        messageType = "metal_income"
    })
    
    -- Limit message count
    if #deathMessages > MAX_MESSAGES then
        table.remove(deathMessages, 1)
    end
    
    Spring.Echo("[Queen Death Display] " .. pingText)
    
    -- Log to file
    logNotification("metal_income", pingText, valuesText)
    
    -- Text-to-speech notification
    local ttsText = string.format("Metal income reached %s per second", formattedThreshold)
    speakText(ttsText)
end

-- Get the team ID to track (handles spectator mode)
local function getTrackedTeamID()
    local myTeamID = GetMyTeamID()
    if not myTeamID or myTeamID < 0 then
        return nil
    end
    
    -- Check if we're spectating
    local isSpectating = GetSpectatingState()
    if isSpectating then
        -- In spectator mode, find the first player team (excluding raptors/gaia)
        local allTeams = GetTeamList()
        local gaiaTeamID = GetGaiaTeamID()
        
        for i = 1, #allTeams do
            local teamID = allTeams[i]
            -- Skip spectator team, gaia, and raptors
            if teamID ~= myTeamID and teamID ~= gaiaTeamID then
                -- Check if this team has players (not just AI)
                local players = GetPlayerList(teamID)
                if players and #players > 0 then
                    return teamID
                end
            end
        end
        -- Fallback: return nil if no player team found
        return nil
    else
        -- Not spectating, use our own team
        return myTeamID
    end
end

-- Check metal income and trigger notifications
local function checkMetalIncome()
    local teamID = getTrackedTeamID()
    if not teamID or teamID < 0 then
        return
    end
    
    -- Update tracked team if it changed (e.g., switched spectating target)
    if trackedTeamID ~= teamID then
        trackedTeamID = teamID
        -- Reset tracking for new team
        lastMetalAmount[teamID] = nil
        lastMetalCheckTime[teamID] = nil
        -- Reset triggered thresholds for new team
        metalIncomeTriggered[teamID] = {}
    end
    
    -- GetTeamResources returns: current, storage, pull, income, expense, share, sent, received
    -- We want the 4th return value: income (metal per second)
    local metal, storage, pull, income = GetTeamResources(teamID, "metal")
    
    if not income or income < 0 then
        return
    end
    
    -- Use the income value directly from GetTeamResources (this is the actual income per second)
    local incomeRate = income
    
    -- Initialize tracking for this team (no longer need to track metal amounts or time)
    if not metalIncomeTriggered[teamID] then
        metalIncomeTriggered[teamID] = {}
    end
    
    -- Check thresholds (per team)
    local triggered = metalIncomeTriggered[teamID] or {}
    for _, threshold in ipairs(metalIncomeThresholds) do
        if incomeRate >= threshold and not triggered[threshold] then
            triggered[threshold] = true
            addMetalIncomeNotification(incomeRate, threshold)
        end
    end
    metalIncomeTriggered[teamID] = triggered
end

function widget:GameFrame(frame)
    -- Check metal income roughly once per second (every 30 frames at 30fps)
    if frame % 30 == 0 then
        checkMetalIncome()
    end
end

