-- JSON Export module - Handles JSON serialization and file writing
local JSONExport = {}

-- Helper: Convert Lua value to JSON string
function JSONExport.toJSON(value, indent)
    indent = indent or 0
    local indentStr = string.rep("  ", indent)
    local nextIndent = string.rep("  ", indent + 1)
    
    local t = type(value)
    
    if t == "nil" then
        return "null"
    elseif t == "boolean" then
        return value and "true" or "false"
    elseif t == "number" then
        if value ~= value then  -- NaN
            return "null"
        elseif value == math.huge or value == -math.huge then
            return "null"
        else
            return string.format("%.2f", value)
        end
    elseif t == "string" then
        -- Escape special characters
        value = string.gsub(value, "\\", "\\\\")
        value = string.gsub(value, "\"", "\\\"")
        value = string.gsub(value, "\n", "\\n")
        value = string.gsub(value, "\r", "\\r")
        value = string.gsub(value, "\t", "\\t")
        return "\"" .. value .. "\""
    elseif t == "table" then
        -- Check if it's an array (sequential numeric indices starting at 1)
        local isArray = true
        local maxIndex = 0
        local count = 0
        for k, v in pairs(value) do
            count = count + 1
            if type(k) ~= "number" or k < 1 or k ~= math.floor(k) then
                isArray = false
                break
            end
            if k > maxIndex then
                maxIndex = k
            end
        end
        
        if isArray and maxIndex == count then
            -- Array format
            local parts = {}
            for i = 1, maxIndex do
                table.insert(parts, JSONExport.toJSON(value[i], indent + 1))
            end
            if #parts == 0 then
                return "[]"
            end
            return "[\n" .. nextIndent .. table.concat(parts, ",\n" .. nextIndent) .. "\n" .. indentStr .. "]"
        else
            -- Object format
            local parts = {}
            for k, v in pairs(value) do
                local key = type(k) == "string" and k or "[" .. tostring(k) .. "]"
                table.insert(parts, nextIndent .. "\"" .. key .. "\": " .. JSONExport.toJSON(v, indent + 1))
            end
            if #parts == 0 then
                return "{}"
            end
            return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indentStr .. "}"
        end
    else
        return "\"" .. tostring(value) .. "\""
    end
end

-- Export data to JSON file
function JSONExport.export(data, filepath)
    local jsonStr = JSONExport.toJSON(data)
    
    local success, err = pcall(function()
        -- Extract directory path (handle both / and \ separators)
        local dirPath = string.match(filepath, "^(.*)[/\\]")
        if dirPath then
            Spring.CreateDir(dirPath)
        end
        local file = io.open(filepath, "w")
        if file then
            file:write(jsonStr)
            file:close()
        end
    end)
    
    if not success then
        Spring.Echo("[Queen Death Display API] Error writing JSON: " .. tostring(err))
    end
end

return JSONExport

