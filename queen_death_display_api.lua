function widget:GetInfo()
    return {
        name    = "Queen Death Display API",
        desc    = "Tracks queen deaths and metal income, exports to JSON for web interface",
        author  = "Auto",
        date    = "2025-12-08",
        version = "3.0",
        layer   = 0,
        enabled = true,
        handler = true,
    }
end

-- Module variables (will be loaded in Initialize)
local Config, Logger, JSONExport, DataManager, Utils, TimerManager, QueenTracker, MetalTracker, AggressionTracker
local HarmonyRaptor = nil
local harmonyRaptorAvailable = false
local harmonyRaptorError = nil
local modulesLoaded = false

-- Update tracking
local lastUpdateTime = 0
local frameCount = 0
local exportCount = 0  -- Track export count for debugging
local unitsScanned = false  -- Track if initial unit scan has been done

-- UI Button for opening web interface
local buttonVisible = true
local buttonX = 10
local buttonY = 0  -- Will be calculated to center vertically
local buttonWidth = 200
local buttonHeight = 30
local buttonHovered = false

-- Forward declare functions (defined later)
local exportData

-- Function to open web interface (with server start attempt)
local function openWebInterface(webUrl)
    if not webUrl then
        webUrl = Config and Config.WEB_URL or "http://localhost:8082"
    end
    
    -- Try to start the server if it's not running
    local serverScript = "LuaUI/Widgets/QueenDeathDisplay/api/start_server.bat"
    if VFS and VFS.FileExists and VFS.FileExists(serverScript) then
        -- Try to execute the batch file (may not work in all Spring versions)
        local success = pcall(function()
            -- Note: os.execute might not be available or might be restricted
            -- This is a best-effort attempt
            if os and os.execute then
                -- Get full path to batch file
                local fullPath = Spring.GetConfigString("LuaUI", "") .. serverScript
                -- Try to start server in background (Windows)
                os.execute('start "" "' .. fullPath .. '"')
            end
        end)
        
        if success then
            Spring.Echo("[Queen Death Display API] Attempting to start web server...")
            Spring.Echo("[Queen Death Display API] Please wait a few seconds, then try again.")
        end
    end
    
    -- Open the URL
    if Spring.OpenUrl then
        Spring.OpenUrl(webUrl)
        Spring.Echo(string.format("[Queen Death Display API] Opening web interface: %s", webUrl))
        Spring.Echo("[Queen Death Display API] If connection fails, start the server manually:")
        Spring.Echo("[Queen Death Display API]   Run: start_server.bat in QueenDeathDisplay/api/")
    else
        Spring.Echo(string.format("[Queen Death Display API] OpenUrl not available. Please open manually: %s", webUrl))
        Spring.Echo("[Queen Death Display API] Also make sure the web server is running:")
        Spring.Echo("[Queen Death Display API]   Run: start_server.bat in QueenDeathDisplay/api/")
    end
end

function widget:Initialize()
    -- Get Spring functions (now guaranteed to be available)
    local GetGameSeconds = Spring.GetGameSeconds
    local GetGameFrame = Spring.GetGameFrame
    local GetSpectatingState = Spring.GetSpectatingState
    local GetMyTeamID = Spring.GetMyTeamID
    
    Spring.Echo("[Queen Death Display API] Widget initialized (v3.0 - Modular)")
    
    -- Load modules (VFS should be available in Initialize)
    local loadModuleErrors = {}
    local function loadModule(name, path)
        if not VFS or not VFS.Include then
            loadModuleErrors[name] = "VFS not available"
            return nil
        end
        -- Check if file exists first (if VFS.FileExists is available)
        if VFS.FileExists then
            if not VFS.FileExists(path) then
                loadModuleErrors[name] = "File not found: " .. path
                Spring.Echo(string.format("[Queen Death Display API] ERROR: Module '%s' file not found: %s", name, path))
                return nil
            end
        end
        local success, result = pcall(function()
            return VFS.Include(path)
        end)
        if not success then
            local errMsg = tostring(result)
            loadModuleErrors[name] = errMsg
            Spring.Echo(string.format("[Queen Death Display API] ERROR: Failed to load module '%s': %s", name, errMsg))
            return nil
        end
        if not result then
            loadModuleErrors[name] = "Module returned nil"
            Spring.Echo(string.format("[Queen Death Display API] ERROR: Module '%s' returned nil", name))
            return nil
        end
        return result
    end
    
    -- Try loading modules with different path formats
    local basePath = 'LuaUI/Widgets/QueenDeathDisplay/modules/'
    Config = loadModule("Config", basePath .. 'config.lua')
    Logger = loadModule("Logger", basePath .. 'logger.lua')
    JSONExport = loadModule("JSONExport", basePath .. 'json_export.lua')
    DataManager = loadModule("DataManager", basePath .. 'data_manager.lua')
    Utils = loadModule("Utils", basePath .. 'utils.lua')
    TimerManager = loadModule("TimerManager", basePath .. 'timer_manager.lua')
    QueenTracker = loadModule("QueenTracker", basePath .. 'queen_tracker.lua')
    MetalTracker = loadModule("MetalTracker", basePath .. 'metal_tracker.lua')
    AggressionTracker = loadModule("AggressionTracker", basePath .. 'aggression_tracker.lua')
    
    -- Debug: Check if VFS can see the files
    if VFS and VFS.FileExists then
        Spring.Echo("[Queen Death Display API] DEBUG: Checking if module files exist...")
        Spring.Echo(string.format("  Config exists: %s", tostring(VFS.FileExists(basePath .. 'config.lua'))))
        Spring.Echo(string.format("  Logger exists: %s", tostring(VFS.FileExists(basePath .. 'logger.lua'))))
    end
    modulesLoaded = Config and Logger and JSONExport and DataManager and Utils and TimerManager and QueenTracker and MetalTracker and AggressionTracker
    
    -- Try to load HarmonyRaptor
    if VFS and VFS.Include then
        local harmonyRaptorPath = 'LuaUI/Widgets/harmony/harmony-raptor.lua'
        
        -- Check if file exists first
        if VFS.FileExists then
            if VFS.FileExists(harmonyRaptorPath) then
                Spring.Echo(string.format("[Queen Death Display API] Found HarmonyRaptor at: %s", harmonyRaptorPath))
            else
                Spring.Echo(string.format("[Queen Death Display API] WARNING: HarmonyRaptor file not found at: %s", harmonyRaptorPath))
                Spring.Echo("[Queen Death Display API] Trying alternative paths...")
                
                -- Try alternative paths
                local alternativePaths = {
                    'LuaUI/Widgets/harmony-raptor.lua',
                    'LuaUI/Widgets/harmony/harmony_raptor.lua',
                }
                
                for _, altPath in ipairs(alternativePaths) do
                    if VFS.FileExists(altPath) then
                        Spring.Echo(string.format("[Queen Death Display API] Found HarmonyRaptor at alternative path: %s", altPath))
                        harmonyRaptorPath = altPath
                        break
                    end
                end
            end
        end
        
        -- Try to load it
        local success, hr = pcall(function()
            return VFS.Include(harmonyRaptorPath)
        end)
        if success and hr then
            HarmonyRaptor = hr
            harmonyRaptorAvailable = true
            Spring.Echo("[Queen Death Display API] HarmonyRaptor loaded successfully")
        else
            harmonyRaptorError = tostring(hr)
            Spring.Echo(string.format("[Queen Death Display API] ERROR: Failed to load HarmonyRaptor: %s", harmonyRaptorError))
        end
    else
        Spring.Echo("[Queen Death Display API] ERROR: VFS not available - cannot load HarmonyRaptor")
    end
    
    -- Report module loading status
    if next(loadModuleErrors) then
        Spring.Echo("[Queen Death Display API] Module loading errors:")
        for name, error in pairs(loadModuleErrors) do
            Spring.Echo("  - " .. name .. ": " .. error)
        end
    end
    
    -- Verify all modules are loaded
    if not modulesLoaded then
        Spring.Echo("[Queen Death Display API] FATAL: One or more modules failed to load. Widget disabled.")
        Spring.Echo("[Queen Death Display API] Check the errors above and verify module files exist.")
        return false
    end
    
    Spring.Echo("[Queen Death Display API] All modules loaded successfully")
    
    -- Report HarmonyRaptor loading status
    if harmonyRaptorAvailable and HarmonyRaptor then
        Spring.Echo("[Queen Death Display API] HarmonyRaptor loaded successfully")
    else
        Spring.Echo("[Queen Death Display API] ERROR: Failed to load HarmonyRaptor")
        if harmonyRaptorError then
            Spring.Echo("[Queen Death Display API] Error details: " .. harmonyRaptorError)
        end
    end
    
    -- Initialize queen def IDs (after modules are loaded and Spring is available)
    local raptorQueenDefIDs = {}
    if Config and Config.QUEEN_UNIT_NAMES then
        for _, name in ipairs(Config.QUEEN_UNIT_NAMES) do
            local def = UnitDefNames[name]
            if def then
                raptorQueenDefIDs[def.id] = true
            end
        end
    end
    
    -- Initialize data manager with queen def IDs
    DataManager.init(raptorQueenDefIDs)
    
    -- Initialize logger
    Logger.init(Config.LOG_DIR)
    
    -- Initialize timer manager
    TimerManager.init(HarmonyRaptor)
    
    -- Initialize trackers
    QueenTracker.init(DataManager, Logger, Utils, TimerManager)
    MetalTracker.init(DataManager, Logger, Utils, Config)
    AggressionTracker.init(DataManager, Utils, Config, HarmonyRaptor)
    
    -- Initialize HarmonyRaptor eco value cache if available
    if harmonyRaptorAvailable and HarmonyRaptor then
        HarmonyRaptor.initEcoValueCache()
        Spring.Echo("[Queen Death Display API] HarmonyRaptor initialized successfully")
    else
        Spring.Echo("[Queen Death Display API] WARNING: HarmonyRaptor not available - aggression tracking will not work")
    end
    
    -- Initialize player teams and eco tracking
    AggressionTracker.updatePlayerTeams()
    Spring.Echo(string.format("[Queen Death Display API] Found %d player teams", #DataManager.getPlayerTeams()))
    
    -- Initialize API directory
    Spring.CreateDir(Config.API_DIR)
    lastUpdateTime = GetGameSeconds() or 0
    
    -- Add initial system message
    local now = GetGameSeconds()
    DataManager.addDeathMessage({
        time = now,
        pingText = "Queen Death Display API - Widget Active",
        valuesText = {"Web interface available at http://localhost:8082"},
        killerName = nil,
        killerCount = 0,
        totalQueens = nil,
        killedQueens = 0,
        remaining = nil,
        dismissed = false,
        messageType = "system"
    })
    
    Logger.log("system", "Widget initialized and ready", {"Web interface available"}, now, Utils.formatTime)
    
    -- Do an initial data export to verify everything is working (only if game has started)
    local gameTime = GetGameSeconds()
    local currentFrame = GetGameFrame()
    if gameTime and gameTime > 0 then
        -- Game is running - export immediately and scan units if needed
        exportData()
        Spring.Echo("[Queen Death Display API] Initial data export completed")
        
        -- If enabled mid-game, scan existing units immediately
        if currentFrame and currentFrame > Config.UNIT_SCAN_DELAY then
            Spring.Echo("[Queen Death Display API] Widget enabled mid-game - scanning existing units...")
            if AggressionTracker then
                AggressionTracker.scanExistingUnits()
            end
            unitsScanned = true
            Spring.Echo("[Queen Death Display API] Unit scan complete")
        end
    else
        Spring.Echo("[Queen Death Display API] Widget ready - waiting for game to start")
    end
    
    -- Register commands (widgetHandler should be available as a global)
    local webUrl = Config and Config.WEB_URL or "http://localhost:8082"
    
    -- Try to register commands
    local commandsRegistered = false
    if widgetHandler and widgetHandler.actionHandler then
        -- Register command to open web interface
        widgetHandler.actionHandler:AddAction(self, "queendeath_open", function()
            openWebInterface(webUrl)
        end, nil, "p")
        Spring.Echo(string.format("[Queen Death Display API] Registered '/queendeath_open' command"))
        
        -- Register command to check aggression
        if AggressionTracker and DataManager then
            widgetHandler.actionHandler:AddAction(self, "queendeath_aggression", function()
                -- Use Spring.SendCommands to ensure output appears in console
                Spring.SendCommands("echo ========================================")
                Spring.SendCommands("echo COMMAND EXECUTED: /queendeath_aggression")
                Spring.SendCommands("echo ========================================")
                
                if not AggressionTracker or not DataManager then
                    Spring.SendCommands("echo ERROR: Modules not available")
                    return
                end
                
                Spring.SendCommands("echo === Player Aggression (Eco Attraction) ===")
                
                local aggression = AggressionTracker.getAggressionData()
                Spring.SendCommands(string.format("echo Player teams in list: %d", #DataManager.getPlayerTeams()))
                Spring.SendCommands(string.format("echo HarmonyRaptor available: %s", tostring(harmonyRaptorAvailable)))
                Spring.SendCommands(string.format("echo Units scanned: %s", tostring(unitsScanned)))
                
                local playerEcoAttractionsRaw = DataManager.getPlayerEcoAttractionsRaw()
                local totalEcoValue = 0
                Spring.SendCommands("echo --- All teams with eco values ---")
                for teamID, ecoValue in pairs(playerEcoAttractionsRaw) do
                    if ecoValue and ecoValue > 0 then
                        totalEcoValue = totalEcoValue + ecoValue
                        local playerName = Utils and Utils.getPlayerName(teamID) or "Unknown"
                        Spring.SendCommands(string.format("echo Team %d (%s): ecoValue=%.0f", teamID, playerName, ecoValue))
                    end
                end
                Spring.SendCommands(string.format("echo Total eco value: %.0f", totalEcoValue))
                
                if #aggression == 0 then
                    Spring.SendCommands("echo No players found or all values are 0")
                    Spring.SendCommands("echo --- Teams in playerTeams list ---")
                    for _, teamID in ipairs(DataManager.getPlayerTeams()) do
                        local ecoValue = playerEcoAttractionsRaw[teamID] or 0
                        local playerName = Utils and Utils.getPlayerName(teamID) or "Unknown"
                        Spring.SendCommands(string.format("echo Team %d (%s): ecoValue=%.0f", teamID, playerName, ecoValue))
                    end
                else
                    Spring.SendCommands(string.format("echo Found %d players with eco > 0:", #aggression))
                    for i, entry in ipairs(aggression) do
                        Spring.SendCommands(string.format("echo #%d: %s (Team %d) - Eco: %.0f, Percentage: %.1f%%, Multiplier: %.2fx [%s]", 
                            i, entry.name, entry.teamID, entry.ecoValue, entry.percentage, entry.multiplier, entry.threatLevel))
                    end
                end
            end, nil, "p")
            Spring.Echo("[Queen Death Display API] Registered '/queendeath_aggression' command")
            commandsRegistered = true
        else
            Spring.Echo("[Queen Death Display API] WARNING: Cannot register /queendeath_aggression - modules not loaded")
            if not AggressionTracker then
                Spring.Echo("  - AggressionTracker is nil")
            end
            if not DataManager then
                Spring.Echo("  - DataManager is nil")
            end
        end
    else
        Spring.Echo("[Queen Death Display API] ERROR: widgetHandler not available - commands cannot be registered")
        if not widgetHandler then
            Spring.Echo("  - widgetHandler global is nil")
        elseif not widgetHandler.actionHandler then
            Spring.Echo("  - widgetHandler.actionHandler is nil")
        end
    end
    
    if commandsRegistered then
        Spring.Echo(string.format("[Queen Death Display API] Use '/queendeath_open' to open web interface: %s", webUrl))
        Spring.Echo("[Queen Death Display API] Use '/queendeath_aggression' to check player aggression")
    end
end

function widget:UnitCreated(unitID, unitDefID, unitTeamID)
    if modulesLoaded and AggressionTracker then
        AggressionTracker.onUnitCreated(unitID, unitDefID, unitTeamID)
    end
end

function widget:UnitGiven(unitID, unitDefID, newTeamID, oldTeamID)
    if modulesLoaded and AggressionTracker then
        AggressionTracker.onUnitGiven(unitID, unitDefID, newTeamID, oldTeamID)
    end
end

function widget:UnitDestroyed(unitID, unitDefID, unitTeam, attackerID, attackerDefID, attackerTeam)
    if modulesLoaded then
        if AggressionTracker then
            AggressionTracker.onUnitDestroyed(unitID, unitDefID, unitTeam)
        end
        if QueenTracker then
            QueenTracker.onUnitDestroyed(unitID, unitDefID, unitTeam, attackerID, attackerDefID, attackerTeam)
        end
    end
end

function widget:Update()
    if not modulesLoaded or not Config then return end
    -- Use time-based updates for consistent frequency regardless of FPS
    local currentTime = Spring.GetGameSeconds()
    if currentTime and currentTime > 0 then
        if lastUpdateTime == 0 then
            lastUpdateTime = currentTime
            exportData()
        elseif (currentTime - lastUpdateTime >= Config.UPDATE_INTERVAL) then
            lastUpdateTime = currentTime
            exportData()
        end
    end
end

function widget:GameFrame(frame)
    if not modulesLoaded or not Config then return end
    -- Scan existing units once after initialization (or immediately if enabled mid-game)
    if (frame == Config.UNIT_SCAN_DELAY or (frame > Config.UNIT_SCAN_DELAY and not unitsScanned)) and AggressionTracker then
        Spring.Echo("[Queen Death Display API] Frame " .. frame .. ": Starting unit scan...")
        AggressionTracker.scanExistingUnits()
        unitsScanned = true
        Spring.Echo("[Queen Death Display API] Frame " .. frame .. ": Unit scan complete")
    end
    
    -- Update every N frames as backup
    frameCount = frameCount + 1
    if frameCount >= Config.FRAME_UPDATE_INTERVAL then
        frameCount = 0
        -- Only export if game has started
        local gameTime = Spring.GetGameSeconds()
        if gameTime and gameTime > 0 then
            exportData()
        end
        
        local currentTime = Spring.GetGameSeconds()
        if currentTime and currentTime > 0 then
            lastUpdateTime = currentTime
        end
    end
    
    -- Update player teams periodically
    if frame % Config.PLAYER_TEAMS_UPDATE_INTERVAL == 0 and AggressionTracker then
        AggressionTracker.updatePlayerTeams()
    end
    
    -- Update metal tracker
    if MetalTracker then
        MetalTracker.update(frame)
    end
end

function widget:DrawScreen()
    if not buttonVisible or not modulesLoaded or not Config then return end
    
    local vsx, vsy = Spring.GetViewGeometry()
    if not vsx or not vsy then return end
    
    -- Enable blending and disable depth test for screen drawing
    gl.Blending(true)
    gl.DepthTest(false)
    
    -- Position button in middle-left of screen
    local x = buttonX
    local y = (vsy - buttonHeight) / 2  -- Center vertically
    
    -- Draw button background
    if buttonHovered then
        gl.Color(0.2, 0.6, 0.9, 0.8)  -- Light blue when hovered
    else
        gl.Color(0.1, 0.3, 0.5, 0.7)  -- Dark blue normally
    end
    gl.Rect(x, y, x + buttonWidth, y + buttonHeight)
    
    -- Draw button border (simpler approach)
    gl.Color(0.3, 0.7, 1.0, 1.0)  -- Bright blue border
    gl.LineWidth(2.0)
    gl.BeginEnd(GL.LINE_LOOP, function()
        gl.Vertex(x, y, 0)
        gl.Vertex(x + buttonWidth, y, 0)
        gl.Vertex(x + buttonWidth, y + buttonHeight, 0)
        gl.Vertex(x, y + buttonHeight, 0)
    end)
    gl.LineWidth(1.0)
    
    -- Draw button text
    gl.Color(1.0, 1.0, 1.0, 1.0)  -- White text
    local text = "Open Web Interface"
    local fontSize = 14
    local textWidth = gl.GetTextWidth(text) * fontSize
    local textX = x + (buttonWidth - textWidth) / 2
    local textY = y + (buttonHeight - fontSize) / 2 + 2
    gl.Text(text, textX, textY, fontSize, "o")
    
    -- Reset color
    gl.Color(1.0, 1.0, 1.0, 1.0)
end

function widget:MousePress(mx, my, button)
    if not buttonVisible or not modulesLoaded or button ~= 1 then return false end
    
    local vsx, vsy = Spring.GetViewGeometry()
    if not vsx or not vsy then return false end
    
    local x = buttonX
    local y = (vsy - buttonHeight) / 2  -- Center vertically
    
    -- Check if click is within button bounds
    if mx >= x and mx <= x + buttonWidth and my >= y and my <= y + buttonHeight then
        local webUrl = Config and Config.WEB_URL or "http://localhost:8082"
        openWebInterface(webUrl)
        return true
    end
    
    return false
end

function widget:MouseMove(mx, my, dx, dy, button)
    if not buttonVisible or not modulesLoaded then return false end
    
    local vsx, vsy = Spring.GetViewGeometry()
    if not vsx or not vsy then return false end
    
    local x = buttonX
    local y = (vsy - buttonHeight) / 2  -- Center vertically
    
    -- Check if mouse is over button
    buttonHovered = (mx >= x and mx <= x + buttonWidth and my >= y and my <= y + buttonHeight)
    
    return false
end

function widget:Shutdown()
    -- Remove registered commands
    if widgetHandler and widgetHandler.actionHandler then
        widgetHandler.actionHandler:RemoveAction(self, "queendeath_open", "p")
        widgetHandler.actionHandler:RemoveAction(self, "queendeath_aggression", "p")
    end
    
    if Logger then
        Logger.shutdown()
    end
    
    -- Clean up API file
    if Config then
        local success, err = pcall(function()
            local file = io.open(Config.API_DIR .. "data.json", "w")
            if file then
                file:write("{}")
                file:close()
            end
        end)
    end
end

-- Export data to JSON file
function exportData()
    if not modulesLoaded or not Config or not JSONExport or not DataManager or not TimerManager or not QueenTracker or not AggressionTracker then
        -- Debug: Log why export is skipped
        if not modulesLoaded then
            Spring.Echo("[Queen Death Display API] DEBUG: exportData skipped - modules not loaded")
        elseif not Config then
            Spring.Echo("[Queen Death Display API] DEBUG: exportData skipped - Config not loaded")
        elseif not JSONExport then
            Spring.Echo("[Queen Death Display API] DEBUG: exportData skipped - JSONExport not loaded")
        end
        return
    end
    
    local now = Spring.GetGameSeconds()
    if not now or now <= 0 then
        -- Game not started yet - this is normal in menu/lobby
        return
    end
    
    -- Track export count (for debugging if needed, but don't spam console)
    exportCount = exportCount + 1
    
    -- Get timer info
    local graceRemaining, queenETA = TimerManager.getTimerInfo()
    local totalQueens, killedQueens, remaining = TimerManager.getQueenTotals()
    
    -- Get player aggression data
    local playerAggression = AggressionTracker.getAggressionData()
    
    -- Get state
    local teamKills = DataManager.getTeamKills()
    local deathMessages = DataManager.getDeathMessages()
    local trackedTeamID = DataManager.getTrackedTeamID()
    local lastMetalAmount = DataManager.getLastMetalAmount()
    
    -- Get current resources and build power for tracked team
    local resources = {
        metal = { current = 0, storage = 0, income = 0 },
        energy = { current = 0, storage = 0, income = 0 },
        buildPower = 0
    }
    
    if trackedTeamID and trackedTeamID >= 0 then
        -- Get metal resources: current, storage, pull, income, expense, share, sent, received
        local metal, metalStorage, metalPull, metalIncome = Spring.GetTeamResources(trackedTeamID, "metal")
        if metal then
            resources.metal.current = metal
            resources.metal.storage = metalStorage or 0
            resources.metal.income = metalIncome or 0
        end
        
        -- Get energy resources: current, storage, pull, income, expense, share, sent, received
        local energy, energyStorage, energyPull, energyIncome = Spring.GetTeamResources(trackedTeamID, "energy")
        if energy then
            resources.energy.current = energy
            resources.energy.storage = energyStorage or 0
            resources.energy.income = energyIncome or 0
        end
        
        -- Calculate build power (sum of buildSpeed from all builder units)
        local teamUnits = Spring.GetTeamUnits(trackedTeamID)
        local totalBuildPower = 0
        for _, unitID in ipairs(teamUnits) do
            local unitDefID = Spring.GetUnitDefID(unitID)
            if unitDefID then
                local unitDef = UnitDefs[unitDefID]
                if unitDef and unitDef.isBuilder and unitDef.buildSpeed then
                    totalBuildPower = totalBuildPower + (unitDef.buildSpeed or 0)
                end
            end
        end
        resources.buildPower = totalBuildPower
    end
    
    -- Build export structure
    local dataToExport = {
            timestamp = now,
            timestampISO = os.date("!%Y-%m-%dT%H:%M:%SZ", math.floor(now)),
            gameTime = now,
            timers = {
                graceRemaining = graceRemaining,
                queenETA = queenETA,
            },
            queens = {
                total = totalQueens,
                killed = killedQueens,
                remaining = remaining,
            },
            teamKills = teamKills,
            leaderboard = QueenTracker.buildLeaderboard(),
            deathMessages = {},
            metalIncome = {
                trackedTeamID = trackedTeamID,
                lastAmount = lastMetalAmount[trackedTeamID] or nil,
            },
            resources = resources,
            playerAggression = playerAggression,
            spectator = {
                isSpectating = Spring.GetSpectatingState(),
                myTeamID = Spring.GetMyTeamID(),
            },
        }
    
    -- Export death messages (last 20, non-dismissed, newest first)
    local count = 0
    for i = #deathMessages, 1, -1 do
        if count >= Config.MAX_MESSAGES then break end
        local msg = deathMessages[i]
        if not msg.dismissed then
            table.insert(dataToExport.deathMessages, {
                time = msg.time,
                pingText = msg.pingText,
                valuesText = msg.valuesText,
                killerName = msg.killerName,
                killerCount = msg.killerCount,
                totalQueens = msg.totalQueens,
                killedQueens = msg.killedQueens,
                remaining = msg.remaining,
                messageType = msg.messageType,
            })
            count = count + 1
        end
    end
    
    -- Export to JSON file
    local success, err = pcall(function()
        JSONExport.export(dataToExport, Config.API_DIR .. "data.json")
    end)
    if not success then
        Spring.Echo("[Queen Death Display API] ERROR: Failed to export data: " .. tostring(err))
    end
end
