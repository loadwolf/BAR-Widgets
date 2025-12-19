-- Logger module - Handles all file logging
local Logger = {}
local logFiles = {}
local logDir = nil

function Logger.init(baseDir)
    logDir = baseDir
    Spring.CreateDir(logDir)
    
    -- Create date-based subfolder (yyyy-mm-dd format)
    local dateStr = os.date("%Y-%m-%d")
    local dateFolder = logDir .. dateStr .. "/"
    Spring.CreateDir(dateFolder)
    
    local timestamp = os.date("%Y%m%d_%H%M%S")
    
    -- Queen death log file
    local queenDeathFilename = dateFolder .. "queen_deaths_" .. timestamp .. ".log"
    logFiles.queenDeath = io.open(queenDeathFilename, "w")
    if logFiles.queenDeath then
        logFiles.queenDeath:write("Queen Death Display - Queen Death Log\n")
        logFiles.queenDeath:write("Started: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n")
        logFiles.queenDeath:write("========================================\n")
        Spring.Echo("[Queen Death Display API] Queen death logging to: " .. queenDeathFilename)
    else
        Spring.Echo("[Queen Death Display API] WARNING: Could not open queen death log file: " .. queenDeathFilename)
    end
    
    -- REMOVED: Metal income log file (metal income milestone notifications disabled)
end

function Logger.getDateFolder()
    if not logDir then return "" end
    local dateStr = os.date("%Y-%m-%d")
    return logDir .. dateStr .. "/"
end

function Logger.log(messageType, pingText, valuesText, gameTime, formatTime)
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local gameTimeFormatted = formatTime and formatTime(gameTime) or tostring(gameTime or 0)
    
    local logEntry = string.format("[%s] Game Time: %s | %s\n", timestamp, gameTimeFormatted, pingText)
    
    -- Write to appropriate log file based on message type
    if messageType == "queen_death" then
        if logFiles.queenDeath then
            logFiles.queenDeath:write(logEntry)
            logFiles.queenDeath:flush()
        end
    elseif messageType == "metal_income" then
        -- REMOVED: Metal income milestone notifications disabled
        -- No longer logging metal income milestones
    elseif messageType == "system" then
        -- System messages go to queen death log
        if logFiles.queenDeath then
            logFiles.queenDeath:write(logEntry)
            logFiles.queenDeath:flush()
        end
    end
end

function Logger.shutdown()
    if logFiles.queenDeath then
        logFiles.queenDeath:write("\n========================================\n")
        logFiles.queenDeath:write("Ended: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n")
        logFiles.queenDeath:close()
        logFiles.queenDeath = nil
    end
    -- REMOVED: Metal income log file shutdown (no longer created)
end

return Logger

