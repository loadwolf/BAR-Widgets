-- Timer Manager module - Handles timer calculations
local TimerManager = {}
local HarmonyRaptor = nil
local harmonyRaptorAvailable = false

function TimerManager.init(hr)
    HarmonyRaptor = hr
    harmonyRaptorAvailable = (hr ~= nil)
end

function TimerManager.getTimerInfo()
    local graceRemaining = nil
    local queenETA = nil
    
    -- Try to use HarmonyRaptor (same data source as raptor-panel)
    if harmonyRaptorAvailable and HarmonyRaptor then
        HarmonyRaptor.updateGameInfo()
        local info = HarmonyRaptor.getGameInfo()
        if info then
            graceRemaining = info.gracePeriodRemaining
            -- Get queen ETA from HarmonyRaptor if available
            local eta = HarmonyRaptor.getQueenETA()
            if eta then
                queenETA = eta
            end
        end
    end
    
    -- Fallback to manual calculation if HarmonyRaptor not available
    if not graceRemaining then
        local now = Spring.GetGameSeconds()
        local gracePeriod = Spring.GetGameRulesParam("raptorGracePeriod")
        if gracePeriod then
            graceRemaining = math.max(0, gracePeriod - now)
        end
    end
    
    -- Fallback for queen ETA if not from HarmonyRaptor
    if not queenETA then
        local now = Spring.GetGameSeconds()
        local gracePeriod = Spring.GetGameRulesParam("raptorGracePeriod")
        local anger = Spring.GetGameRulesParam("raptorQueenAnger")
        local angerGainBase = Spring.GetGameRulesParam("RaptorQueenAngerGain_Base") or 0
        local angerGainAggression = Spring.GetGameRulesParam("RaptorQueenAngerGain_Aggression") or 0
        local angerGainEco = Spring.GetGameRulesParam("RaptorQueenAngerGain_Eco") or 0
        
        if gracePeriod and now > gracePeriod and anger and anger < 100 then
            local totalGainRate = angerGainBase + angerGainAggression + angerGainEco
            if totalGainRate > 0 then
                local angerRemaining = 100 - anger
                queenETA = angerRemaining / totalGainRate
            end
        end
    end
    
    return graceRemaining, queenETA
end

function TimerManager.getQueenTotals()
    local rulesTotal = Spring.GetGameRulesParam("raptorQueenCount")
    local rulesKilled = Spring.GetGameRulesParam("raptorQueensKilled")
    local modOpts = Spring.GetModOptions()
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

return TimerManager

