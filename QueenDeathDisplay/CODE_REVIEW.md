# Code Review: Extensibility and Modularity Analysis

## Current Structure Analysis

### Issues Identified

1. **Monolithic File (1200+ lines)**
   - All functionality in single file
   - Hard to navigate and maintain
   - Difficult to test individual components

2. **Mixed Concerns**
   - Data tracking (queen deaths, metal income, aggression)
   - Logging (file I/O)
   - JSON export
   - Event handling
   - All tightly coupled

3. **Global State Scattered**
   - `teamKills`, `deathMessages`, `metalIncomeTriggered`, `playerEcoAttractionsRaw`
   - No clear data model or state management
   - Hard to track dependencies

4. **Hard-coded Configuration**
   - Constants mixed with logic
   - No easy way to customize thresholds, intervals, etc.
   - Configuration not centralized

5. **Tight Coupling**
   - Functions directly access Spring API
   - No abstraction layer
   - Hard to mock for testing

6. **Limited Extensibility**
   - Adding new features requires modifying core file
   - No plugin/extension system
   - No clear interfaces for new trackers

## Recommended Modular Structure

```
QueenDeathDisplay/
├── api/
│   ├── data.json (generated)
│   ├── index.html
│   └── web_server.py
├── modules/
│   ├── config.lua          -- Configuration constants
│   ├── logger.lua          -- Logging functionality
│   ├── json_export.lua     -- JSON serialization
│   ├── queen_tracker.lua   -- Queen death tracking
│   ├── metal_tracker.lua   -- Metal income tracking
│   ├── aggression_tracker.lua -- Player aggression tracking
│   ├── timer_manager.lua   -- Timer calculations
│   └── data_manager.lua    -- Centralized state management
├── queen_death_display_api.lua (main widget)
└── CODE_REVIEW.md
```

## Proposed Refactoring

### 1. Configuration Module (`modules/config.lua`)
```lua
return {
    -- Paths
    API_DIR = "LuaUI/Widgets/QueenDeathDisplay/api/",
    LOG_DIR = "LuaUI/Widgets/QueenDeathDisplay/",
    
    -- Update intervals
    UPDATE_INTERVAL = 0.1,
    FRAME_UPDATE_INTERVAL = 3,
    
    -- Queen tracking
    QUEEN_UNIT_NAMES = {
        "raptor_queen_easy", "raptor_queen_veryeasy",
        "raptor_queen_hard", "raptor_queen_veryhard",
        "raptor_queen_epic", "raptor_queen_normal",
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
}
```

### 2. Data Manager (`modules/data_manager.lua`)
```lua
-- Centralized state management
local DataManager = {}
local state = {
    teamKills = {},
    deathMessages = {},
    metalIncomeTriggered = {},
    playerEcoAttractionsRaw = {},
    playerTeams = {},
    -- ... other state
}

function DataManager.getState()
    return state
end

function DataManager.reset()
    -- Clear all state
end

return DataManager
```

### 3. Tracker Modules (Separate concerns)
- `queen_tracker.lua`: Handles queen death events, kill counting
- `metal_tracker.lua`: Monitors metal income, triggers notifications
- `aggression_tracker.lua`: Tracks player eco values, calculates aggression

### 4. Logger Module (`modules/logger.lua`)
```lua
local Logger = {}
local logFiles = {}

function Logger.init(dateFolder)
    -- Initialize log files
end

function Logger.log(messageType, message)
    -- Write to appropriate log file
end

return Logger
```

### 5. JSON Export Module (`modules/json_export.lua`)
```lua
local JSONExport = {}

function JSONExport.toJSON(value, indent)
    -- JSON serialization
end

function JSONExport.export(data, filepath)
    -- Write JSON to file
end

return JSONExport
```

## Benefits of Refactoring

1. **Easier to Extend**
   - Add new trackers by creating new module
   - Clear interfaces between components
   - Configuration in one place

2. **Better Testability**
   - Modules can be tested independently
   - Mock dependencies easily
   - Clear input/output contracts

3. **Improved Maintainability**
   - Smaller, focused files
   - Clear separation of concerns
   - Easier to find and fix bugs

4. **Better Code Reuse**
   - Modules can be used by other widgets
   - Shared utilities extracted
   - Common patterns identified

5. **Easier Configuration**
   - All settings in config module
   - User can customize without touching logic
   - Environment-specific configs possible

## Migration Strategy

1. **Phase 1**: Extract configuration
   - Move all constants to `config.lua`
   - Update references

2. **Phase 2**: Extract utilities
   - Move formatting functions
   - Move JSON export
   - Move logging

3. **Phase 3**: Extract trackers
   - Create tracker modules
   - Move tracking logic
   - Update event handlers

4. **Phase 4**: Extract data management
   - Create data manager
   - Centralize state access
   - Add state validation

5. **Phase 5**: Clean up main file
   - Main file becomes orchestrator
   - Wire modules together
   - Minimal logic in main file

## Priority Recommendations

### High Priority
1. ✅ Extract configuration to separate module
2. ✅ Separate logging functionality
3. ✅ Extract JSON export utilities

### Medium Priority
4. ✅ Create tracker modules (queen, metal, aggression)
5. ✅ Centralize data management
6. ✅ Extract timer calculations

### Low Priority
7. ✅ Add plugin system for custom trackers
8. ✅ Add configuration file support
9. ✅ Add unit testing framework

## Example: Refactored Main File Structure

```lua
-- Main widget file (orchestrator)
local Config = require('modules/config')
local DataManager = require('modules/data_manager')
local QueenTracker = require('modules/queen_tracker')
local MetalTracker = require('modules/metal_tracker')
local AggressionTracker = require('modules/aggression_tracker')
local Logger = require('modules/logger')
local JSONExport = require('modules/json_export')

function widget:Initialize()
    -- Initialize modules
    DataManager.init()
    Logger.init(Config.LOG_DIR)
    QueenTracker.init(DataManager)
    MetalTracker.init(DataManager, Config)
    AggressionTracker.init(DataManager)
end

function widget:UnitDestroyed(...)
    QueenTracker.onUnitDestroyed(...)
end

function widget:GameFrame(frame)
    MetalTracker.update(frame)
    AggressionTracker.update(frame)
    JSONExport.export(DataManager.getState(), Config.API_FILE)
end
```

