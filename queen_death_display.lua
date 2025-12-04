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
local deathMessages = {}  -- Table of {time, text, values}
local MESSAGE_DURATION = 10  -- seconds (no longer used to hide, panel is always visible)
local MAX_MESSAGES = 5

-- Panel position (draggable)
local panelX = 20
local panelY = nil  -- Will be set in Initialize based on screen size
local panelDragging = false
local dragOffsetX = 0
local dragOffsetY = 0

function widget:Initialize()
    Spring.Echo("[Queen Death Display] Widget initialized")
    -- Initialize panel position
    local vsx, vsy = gl.GetViewSizes()
    panelY = vsy - 100
    -- Add a test message to verify drawing works
    local now = Spring.GetGameSeconds()
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

-- Spring shortcuts
local GetPlayerList = Spring.GetPlayerList
local GetPlayerInfo = Spring.GetPlayerInfo
local GetGameRulesParam = Spring.GetGameRulesParam
local GetModOptions = Spring.GetModOptions
local GetGameSeconds = Spring.GetGameSeconds
local GetUnitPosition = Spring.GetUnitPosition
local MarkerAddPoint = Spring.MarkerAddPoint

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
    
    -- Build detailed values text for display
    local valuesText = {}
    table.insert(valuesText, string.format("Killer: %s", killerName or "Unknown"))
    if killerCount > 0 then
        table.insert(valuesText, string.format("Player Kills: %d", killerCount))
    end
    if totalQueens then
        table.insert(valuesText, string.format("Total Queens: %d", totalQueens))
    end
    if killedQueens then
        table.insert(valuesText, string.format("Queens Killed: %d", killedQueens))
    end
    if remaining then
        table.insert(valuesText, string.format("Queens Remaining: %d", remaining))
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
        remaining = remaining
    })
    
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
    
    -- Update panel Y if screen size changed
    if not panelY or panelY > vsy then
        panelY = vsy - 100
    end
    
    -- Display panel (positioned by dragging)
    local panelW = 350
    local lineHeight = 20
    local padding = 10
    
    -- Calculate panel height (include timer section at top)
    local timerSectionHeight = 0
    if graceRemaining or queenETA or remainingQueens then
        timerSectionHeight = lineHeight + padding  -- Header
        if graceRemaining and graceRemaining > 0 then
            timerSectionHeight = timerSectionHeight + 50  -- Large text (44px) + spacing
        end
        if queenETA then
            timerSectionHeight = timerSectionHeight + lineHeight  -- Normal size
        end
        if remainingQueens then
            timerSectionHeight = timerSectionHeight + 50  -- Large text (44px) + spacing
        end
    end
    
    local totalHeight = padding * 2 + timerSectionHeight
    for i = 1, #deathMessages do
        totalHeight = totalHeight + lineHeight * (1 + #deathMessages[i].valuesText) + 5
    end
    
    -- Draw background
    gl.Color(0, 0, 0, 0.7)
    gl.Rect(panelX, panelY - totalHeight, panelX + panelW, panelY)
    
    -- Draw border
    gl.Color(1, 0.5, 0, 1)
    gl.Rect(panelX, panelY - totalHeight, panelX + panelW, panelY - totalHeight + 2)
    gl.Rect(panelX, panelY - 2, panelX + panelW, panelY)
    gl.Rect(panelX, panelY - totalHeight, panelX + 2, panelY)
    gl.Rect(panelX + panelW - 2, panelY - totalHeight, panelX + panelW, panelY)
    
    -- Draw timer section at top
    local currentY = panelY - padding
    if timerSectionHeight > 0 then
        gl.Color(0.2, 0.2, 0.2, 0.8)
        gl.Rect(panelX + 2, currentY - timerSectionHeight + padding, panelX + panelW - 2, currentY)
        
        gl.Color(1, 1, 0.5, 1)
        gl.Text("=== TIMERS ===", panelX + padding, currentY, 12, "o")
        currentY = currentY - lineHeight
        
        if graceRemaining and graceRemaining > 0 then
            -- Large text for No Rush (4x size = 44px) - just the time value
            gl.Color(0.5, 1, 0.5, 1)
            gl.Text(formatTime(graceRemaining), panelX + padding + 10, currentY, 44, "o")
            currentY = currentY - 50  -- Extra spacing for large text
        end
        
        if queenETA then
            gl.Color(1, 0.8, 0, 1)
            gl.Text("Queens Arrive: " .. formatTime(queenETA), panelX + padding + 10, currentY, 11, "n")
            currentY = currentY - lineHeight
        elseif remainingQueens then
            -- Large text for Queens Remaining (4x size = 44px) - just the count
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
    for i = #deathMessages, 1, -1 do
        local msg = deathMessages[i]
        local alpha = 1.0  -- Keep fully visible at all times
        
        -- Main ping text (larger, bold)
        gl.Color(1, 0.8, 0, alpha)
        gl.Text(msg.pingText, panelX + padding, currentY, 14, "o")
        currentY = currentY - lineHeight - 2
        
        -- Values (smaller, white)
        gl.Color(1, 1, 1, alpha * 0.8)
        for _, valueLine in ipairs(msg.valuesText) do
            gl.Text(valueLine, panelX + padding + 10, currentY, 11, "n")
            currentY = currentY - lineHeight
        end
        
        currentY = currentY - 5  -- Spacing between messages
    end
    
    gl.Color(1, 1, 1, 1)
end

function widget:MousePress(x, y, button)
    if button ~= 1 then return false end  -- Only left mouse button
    
    local vsx, vsy = gl.GetViewSizes()
    local mx, my = Spring.GetMouseState()
    -- Convert mouse coordinates (Spring uses bottom-up, we use top-down)
    my = vsy - my
    
    -- Calculate panel bounds
    local panelW = 350
    local lineHeight = 20
    local padding = 10
    local now = GetGameSeconds()
    local graceRemaining, queenETA, remainingQueens = getTimerInfo()
    
    -- Calculate panel height
    local timerSectionHeight = 0
    if graceRemaining or queenETA or remainingQueens then
        timerSectionHeight = lineHeight + padding  -- Header
        if graceRemaining and graceRemaining > 0 then
            timerSectionHeight = timerSectionHeight + 50  -- Large text (44px) + spacing
        end
        if queenETA then
            timerSectionHeight = timerSectionHeight + lineHeight  -- Normal size
        end
        if remainingQueens then
            timerSectionHeight = timerSectionHeight + 50  -- Large text (44px) + spacing
        end
    end
    
    local totalHeight = padding * 2 + timerSectionHeight
    for i = 1, #deathMessages do
        totalHeight = totalHeight + lineHeight * (1 + #deathMessages[i].valuesText) + 5
    end
    
    local panelLeft = panelX
    local panelRight = panelX + panelW
    local panelTop = panelY
    local panelBottom = panelY - totalHeight
    
    -- Check if click is within panel bounds
    if mx >= panelLeft and mx <= panelRight and my <= panelTop and my >= panelBottom then
        panelDragging = true
        dragOffsetX = mx - panelX
        dragOffsetY = my - panelY
        return true
    end
    
    return false
end

function widget:MouseMove(x, y, dx, dy, button)
    if not panelDragging then return false end
    
    local vsx, vsy = gl.GetViewSizes()
    local mx, my = Spring.GetMouseState()
    my = vsy - my
    
    -- Update panel position
    panelX = mx - dragOffsetX
    panelY = my - dragOffsetY
    
    -- Keep panel on screen
    local panelW = 350
    if panelX < 0 then panelX = 0 end
    if panelX + panelW > vsx then panelX = vsx - panelW end
    if panelY > vsy then panelY = vsy - 50 end
    if panelY < 50 then panelY = 50 end
    
    return true
end

function widget:MouseRelease(x, y, button)
    if button ~= 1 then return false end
    
    if panelDragging then
        panelDragging = false
        return true
    end
    
    return false
end

