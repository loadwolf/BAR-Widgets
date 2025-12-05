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
local MAX_MESSAGES = 5

-- Logging
local LOG_DIR = "LuaUI/Widgets/QueenDeathDisplay/"
local logFile = nil

-- Metal income tracking
local metalIncomeThresholds = {100, 200, 500, 1000, 2000, 5000, 10000, 20000, 50000, 100000, 200000, 500000, 1000000, 2000000,5000000,10000000,50000000,100000000, }  -- Metal per second thresholds
local metalIncomeTriggered = {}  -- Track which thresholds have been triggered
local lastMetalCheck = 0
local lastMetalAmount = 0
local lastMetalCheckTime = 0

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

function widget:Initialize()
    Spring.Echo("[Queen Death Display] Widget initialized")
    -- Initialize panel position (in bottom-up coordinates like LayoutPlannerPlus)
    local vsx, vsy = gl.GetViewSizes()
    -- Center vertically on left side (middle of screen)
    panelY = vsy / 2  -- Bottom-up: Y increases upward from bottom, so vsy/2 is middle
    -- Initialize log file
    initLogFile()
    -- Add a test message to verify drawing works
    local now = GetGameSeconds()
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
    
    return graceRemaining, queenETA, remaining
end

-- Add a death message to display
local function addDeathMessage(killerName, killerCount, totalQueens, killedQueens, remaining)
    local now = GetGameSeconds()
    
    -- Build the ping text
    local pingText
    if killerName then
        if killerCount > 0 then
            pingText = string.format("Queen Killed by %s #%d", killerName, killerCount)
        else
            pingText = string.format("Queen Killed by %s", killerName)
        end
    else
        pingText = "Queen Killed"
    end
    
    -- Add remaining info
    if remaining and remaining > 0 then
        pingText = pingText .. string.format(" (%d remaining)", remaining)
    elseif remaining == 0 then
        pingText = pingText .. " (ALL DEFEATED!)"
    end
    
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
        local x, y, z = GetUnitPosition(unitID)
        if x and y and z then
            -- Determine killer name and per-team kill count
            local killerName = getKillerName(attackerTeam)
            if killerName and attackerTeam and attackerTeam >= 0 then
                teamKills[attackerTeam] = (teamKills[attackerTeam] or 0) + 1
            end
            local killerCount = (attackerTeam and teamKills[attackerTeam]) or 0

            -- Get queen totals
            local totalQueens, killedQueens, remaining = getQueenTotals()
            
            -- Create ping text and add to display
            local pingText = addDeathMessage(killerName, killerCount, totalQueens, killedQueens, remaining)
            
            -- Debug output
            Spring.Echo("[Queen Death] " .. pingText)
            Spring.Echo("[Queen Death] Messages count: " .. #deathMessages)
            
            -- Ping on map
            MarkerAddPoint(x, y, z, pingText, false)
        end
    end
end

function widget:DrawScreen()
    gl.Color(1, 1, 1, 1)
    gl.Blending(true)
    gl.DepthTest(false)
    
    local vsx, vsy = gl.GetViewSizes()
    local now = GetGameSeconds()
    
    -- Always keep panel visible.
    -- If for some reason there are no messages, recreate a minimal status message.
    if #deathMessages == 0 then
        table.insert(deathMessages, {
            time = now,
            pingText = "Queen Death Display Active",
            valuesText = {"Waiting for queen death..."},
            killerName = nil,
            killerCount = 0,
            totalQueens = nil,
            killedQueens = 0,
            remaining = nil
        })
    end
    
    -- Get timer info
    local graceRemaining, queenETA, remainingQueens = getTimerInfo()
    
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
    
    local totalHeight = headerHeight + padding * 2 + timerSectionHeight
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
    
    -- Draw timer section below header (start after header + padding)
    local currentY = panelY - headerHeight - padding
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
                local buttonY = msgStartY - dismissButtonSize  -- Aligned with first line of text
                
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
    
    local totalHeight = headerHeight + padding * 2 + timerSectionHeight
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
        local dismissButtonSize = 16
        local dismissButtonX = panelX + padding  -- Same as DrawScreen
        local currentY = panelY - headerHeight - padding
        
        -- Skip timer section
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
            if not msg.dismissed and msg.messageType ~= "system" then
                local msgStartY = currentY
                local buttonY = msgStartY - dismissButtonSize  -- Same calculation as DrawScreen
                
                -- Check if click is on this button
                if mx >= dismissButtonX and mx <= dismissButtonX + dismissButtonSize and
                   my >= buttonY and my <= buttonY + dismissButtonSize then
                    -- Dismiss this message
                    msg.dismissed = true
                    return true  -- Consume the click
                end
                
                -- Move to next message position
                currentY = currentY - lineHeight - 2  -- Main text
                for _ = 1, #msg.valuesText do
                    currentY = currentY - lineHeight  -- Value lines
                end
                currentY = currentY - 5  -- Spacing
            else
                -- System message or already dismissed - still need to account for its space
                currentY = currentY - lineHeight - 2
                for _ = 1, #msg.valuesText do
                    currentY = currentY - lineHeight
                end
                currentY = currentY - 5
            end
        end
        
        -- If we get here, click was in panel but not on a button - allow dragging
        panelDragging = true
        panelDragDX = mx - panelX
        panelDragDY = my - panelY  -- Both in bottom-up coordinates
        return true
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
    local totalHeight = headerHeight + padding * 2 + timerSectionHeight
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
end

-- Check metal income and trigger notifications
local function checkMetalIncome()
    local myTeamID = GetMyTeamID()
    if not myTeamID or myTeamID < 0 then
        return
    end
    
    local now = GetGameSeconds()
    local metal, _ = GetTeamResources(myTeamID, "metal")
    
    if not metal then
        return
    end
    
    -- Initialize tracking
    if lastMetalCheckTime == 0 then
        lastMetalAmount = metal
        lastMetalCheckTime = now
        return
    end
    
    -- Calculate income rate (check every 2 seconds for accuracy)
    local timeDiff = now - lastMetalCheckTime
    if timeDiff < 2.0 then
        return
    end
    
    local metalDiff = metal - lastMetalAmount
    local incomeRate = metalDiff / timeDiff
    
    -- Update tracking
    lastMetalAmount = metal
    lastMetalCheckTime = now
    
    -- Check thresholds
    for _, threshold in ipairs(metalIncomeThresholds) do
        if incomeRate >= threshold and not metalIncomeTriggered[threshold] then
            metalIncomeTriggered[threshold] = true
            addMetalIncomeNotification(incomeRate, threshold)
        end
    end
end

function widget:GameFrame(frame)
    -- Check metal income roughly once per second (every 30 frames at 30fps)
    if frame % 30 == 0 then
        checkMetalIncome()
    end
end

