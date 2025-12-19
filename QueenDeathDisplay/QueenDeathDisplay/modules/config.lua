-- Configuration module - All constants and settings
return {
    -- Paths
    API_DIR = "LuaUI/Widgets/QueenDeathDisplay/api/",
    LOG_DIR = "LuaUI/Widgets/QueenDeathDisplay/",
    
    -- Web interface URL
    WEB_URL = "http://localhost:8082",
    
    -- Update intervals
    UPDATE_INTERVAL = 0.1,  -- Update every 0.1 seconds (10 times per second)
    FRAME_UPDATE_INTERVAL = 3,  -- Also update every 3 frames as backup
    
    -- Queen tracking
    QUEEN_UNIT_NAMES = {
        "raptor_queen_easy", "raptor_queen_veryeasy",
        "raptor_queen_hard", "raptor_queen_veryhard",
        "raptor_queen_epic",
        "raptor_queen_normal",
    },
    
    -- Metal income thresholds
    METAL_INCOME_THRESHOLDS = {
        100, 200, 500, 1000,
        2000, 3000, 4000, 5000, 6000, 7000, 8000, 9000,
        10000, 15000, 20000, 30000, 40000,
        50000, 100000, 200000, 500000,
        1000000, 2000000, 5000000, 10000000, 50000000, 100000000
    },
    
    -- Display limits
    MAX_MESSAGES = 20,
    
    -- Aggression thresholds
    THREAT_HIGH = 1.7,
    THREAT_MEDIUM = 1.2,
    
    -- Metal income check interval (frames)
    METAL_CHECK_INTERVAL = 30,  -- Roughly once per second at 30fps
    
    -- Unit scan delay (frames)
    UNIT_SCAN_DELAY = 60,  -- ~2 seconds at 30fps
    
    -- Player teams update interval (frames)
    PLAYER_TEAMS_UPDATE_INTERVAL = 300,  -- Every 10 seconds at 30fps
}

