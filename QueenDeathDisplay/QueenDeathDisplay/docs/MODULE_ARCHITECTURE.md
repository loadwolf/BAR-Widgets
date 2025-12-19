# Module Architecture Review

## Module Dependency Graph

```
Main Widget (queen_death_display_api.lua)
│
├── Config (config.lua)
│   └── No dependencies (pure data)
│
├── DataManager (data_manager.lua)
│   └── No dependencies (encapsulated state)
│
├── Utils (utils.lua)
│   └── No dependencies (uses Spring directly)
│
├── Logger (logger.lua)
│   └── No dependencies (uses Spring directly)
│
├── JSONExport (json_export.lua)
│   └── No dependencies (uses Spring directly)
│
├── TimerManager (timer_manager.lua)
│   └── Optional: HarmonyRaptor (external)
│   └── Uses Spring directly
│
├── QueenTracker (queen_tracker.lua)
│   ├── Depends on: DataManager, Logger, Utils, TimerManager
│   └── Uses Spring directly
│
├── MetalTracker (metal_tracker.lua)
│   ├── Depends on: DataManager, Logger, Utils, Config
│   └── Uses Spring directly
│
└── AggressionTracker (aggression_tracker.lua)
    ├── Depends on: DataManager, Utils, Config
    ├── Optional: HarmonyRaptor (external)
    └── Uses Spring directly
```

## Module Responsibilities

### Core Modules (No Dependencies)
- **Config**: Configuration constants and settings
- **DataManager**: Centralized state management (single source of truth)
- **Utils**: Pure utility functions (formatting, player name lookup)
- **Logger**: File logging functionality
- **JSONExport**: JSON serialization and file writing

### Feature Modules (Have Dependencies)
- **TimerManager**: Game timer calculations (grace period, queen ETA)
- **QueenTracker**: Queen death tracking, leaderboard generation
- **MetalTracker**: Metal income threshold tracking
- **AggressionTracker**: Player aggression (eco attraction) tracking

## Initialization Order

1. **Load all modules** (via VFS.Include)
2. **Initialize DataManager** (with queen def IDs)
3. **Initialize Logger** (with log directory)
4. **Initialize TimerManager** (with HarmonyRaptor)
5. **Initialize Trackers** (with their dependencies):
   - QueenTracker (DataManager, Logger, Utils, TimerManager)
   - MetalTracker (DataManager, Logger, Utils, Config)
   - AggressionTracker (DataManager, Utils, Config, HarmonyRaptor)

## Design Patterns Used

### 1. Dependency Injection
All modules receive their dependencies through `init()` functions:
```lua
QueenTracker.init(DataManager, Logger, Utils, TimerManager)
```
**Pros**: 
- Clear dependencies
- Easy to test
- Loose coupling

**Cons**: 
- None identified

### 2. Single Responsibility Principle
Each module has one clear purpose:
- Config: Configuration only
- DataManager: State management only
- Utils: Utility functions only
- etc.

### 3. Encapsulation
- DataManager encapsulates all state
- Modules don't directly access each other's internals
- State is accessed through getter/setter functions

## Issues Found

### 1. ❌ CRITICAL: Missing Spring prefix in queen_tracker.lua
**Location**: `queen_tracker.lua:45`
```lua
local now = GetGameSeconds()  -- WRONG: Should be Spring.GetGameSeconds()
```
**Impact**: Will cause runtime error
**Fix**: Use `Spring.GetGameSeconds()`

### 2. ⚠️ Inconsistent Spring API Access
Some modules access Spring directly (good), but there's no standard pattern:
- Most modules: `Spring.GetGameSeconds()`
- Some modules: Direct access is fine, but could be more consistent

### 3. ✅ No Circular Dependencies
All dependencies flow in one direction (good!)

### 4. ✅ Proper Module Isolation
Modules don't access each other's internals directly (good!)

### 5. ⚠️ External Dependency (HarmonyRaptor)
- TimerManager and AggressionTracker depend on HarmonyRaptor
- This is optional and handled gracefully
- **Recommendation**: Keep as-is (good error handling)

## Recommendations

### High Priority
1. **Fix GetGameSeconds() bug** in queen_tracker.lua
2. **Add nil checks** for all module function calls (already done in main widget)

### Medium Priority
1. **Consider creating a Spring wrapper module** if Spring API access becomes more complex
2. **Document module interfaces** (what functions each module exports)

### Low Priority
1. **Add module versioning** if modules evolve independently
2. **Consider lazy loading** for modules that aren't always needed

## Module Communication Patterns

### Pattern 1: Direct Function Calls
```lua
-- Main widget calls module functions
QueenTracker.onUnitDestroyed(...)
```

### Pattern 2: State Access via DataManager
```lua
-- Modules read/write state through DataManager
DataManager.addKill(teamID)
local kills = DataManager.getKillCount(teamID)
```

### Pattern 3: Dependency Injection
```lua
-- Modules receive dependencies at init
QueenTracker.init(DataManager, Logger, Utils, TimerManager)
```

## Testing Considerations

### Easy to Test
- Config: Pure data
- Utils: Pure functions
- JSONExport: Pure functions (with Spring.CreateDir mock)

### Requires Mocking
- Logger: Needs Spring and file I/O
- DataManager: Needs initialization
- Trackers: Need all dependencies

## Extensibility

### Adding a New Tracker
1. Create new module file
2. Follow same pattern (init function, return module table)
3. Add to main widget's module loading
4. Initialize with dependencies

### Adding New State
1. Add to DataManager.state
2. Add getter/setter functions
3. Update any modules that need access

## Overall Assessment

✅ **Strengths**:
- Clear separation of concerns
- No circular dependencies
- Good encapsulation
- Dependency injection pattern
- Graceful handling of optional dependencies

⚠️ **Areas for Improvement**:
- Fix GetGameSeconds() bug
- Consider Spring API wrapper for consistency
- Add module interface documentation

**Grade: A-** (Excellent modularity, one critical bug to fix)

