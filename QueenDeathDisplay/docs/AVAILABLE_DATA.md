# Available Data & Variables for Web Interface

This document lists all variables and data that can be accessed and potentially displayed on the Queen Death Display web interface.

## Currently Exported Data

### 1. Timers & Queen Information
- **`timers.graceRemaining`** - Time remaining in grace period (seconds)
- **`timers.queenETA`** - Estimated time until queen spawns (seconds)
- **`queens.total`** - Total number of queens in the game
- **`queens.killed`** - Number of queens killed
- **`queens.remaining`** - Number of queens remaining

### 2. Resources (Tracked Team)
- **`resources.metal.current`** - Current metal amount
- **`resources.metal.storage`** - Maximum metal storage capacity
- **`resources.metal.income`** - Metal income per second
- **`resources.energy.current`** - Current energy amount
- **`resources.energy.storage`** - Maximum energy storage capacity
- **`resources.energy.income`** - Energy income per second
- **`resources.buildPower`** - Total build power (sum of all builder units' buildSpeed)

### 3. Player Aggression (Eco Attraction)
- **`playerAggression[]`** - Array of player aggression data:
  - `name` - Player name
  - `teamID` - Team ID
  - `ecoValue` - Raw eco attraction value
  - `percentage` - Percentage of total eco attraction
  - `multiplier` - Threat multiplier
  - `threatLevel` - "low", "medium", or "high"
  - `isMe` - Boolean if this is the current player

### 4. Leaderboard
- **`leaderboard[]`** - Array of kill leaderboard entries:
  - `name` - Player name
  - `kills` - Number of queen kills
  - `teamID` - Team ID

### 5. Death Messages & Notifications
- **`deathMessages[]`** - Array of recent notifications:
  - `time` - Timestamp
  - `pingText` - Message text
  - `killerName` - Name of killer (for queen deaths)
  - `killerCount` - Total kills by this player
  - `messageType` - "queen_death" or "metal_income"
  - `remaining` - Queens remaining (for queen deaths)

### 6. Metal Income Tracking
- **`metalIncome.trackedTeamID`** - Currently tracked team ID
- **`metalIncome.lastAmount`** - Last recorded metal income rate

### 7. Spectator Info
- **`spectator.isSpectating`** - Boolean if in spectator mode
- **`spectator.myTeamID`** - Current player's team ID

### 8. Timestamps
- **`timestamp`** - Current game time (seconds)
- **`timestampISO`** - ISO formatted timestamp
- **`gameTime`** - Current game time (seconds)

---

## Available But Not Currently Exported

### A. Additional Resource Data (via Spring.GetTeamResources)
- **Metal:**
  - `pull` - Metal pull (consumption rate)
  - `expense` - Metal expense rate
  - `share` - Metal sharing
  - `sent` - Metal sent to allies
  - `received` - Metal received from allies

- **Energy:**
  - `pull` - Energy pull (consumption rate)
  - `expense` - Energy expense rate
  - `share` - Energy sharing
  - `sent` - Energy sent to allies
  - `received` - Energy received from allies

### B. Game Rules Parameters (via Spring.GetGameRulesParam)
- **`raptorDifficulty`** - Current difficulty level
- **`raptorGracePeriod`** - Grace period duration
- **`raptorQueenAnger`** - Current queen anger (0-100)
- **`raptorTechAnger`** - Tech anger level
- **`RaptorQueenAngerGain_Base`** - Base anger gain rate
- **`RaptorQueenAngerGain_Aggression`** - Aggression anger gain rate
- **`RaptorQueenAngerGain_Eco`** - Eco anger gain rate
- **`raptorQueenHealth`** - Queen health value
- **`raptorQueensKilled`** - Total queens killed (game rule)
- **`raptorQueenTime`** - Queen spawn time

### C. HarmonyRaptor Game Info (via HarmonyRaptor.getGameInfo)
- **`difficulty`** - Game difficulty
- **`stage`** - Current stage: "grace", "main", or "boss"
- **`gracePeriodRemaining`** - Time remaining in grace period
- **`queenHatchProgress`** - Queen hatch progress (0-100%)
- **`angerTech`** - Tech anger level
- **`angerGainBase`** - Base anger gain
- **`angerGainEco`** - Eco anger gain
- **`angerGainAggression`** - Aggression anger gain
- **`angerGainTotal`** - Total anger gain rate
- **`queenHealth`** - Queen health
- **`queenCount`** - Total queen count
- **`queenCountKilled`** - Queens killed
- **`nukeThreatLevel`** - "none", "warning", or "critical"

### D. Team & Player Information
- **All Teams:**
  - `Spring.GetTeamList()` - List of all team IDs
  - `Spring.GetTeamInfo(teamID)` - Team information
  - `Spring.GetTeamLuaAI(teamID)` - Team AI type
  - `Spring.GetTeamColor(teamID)` - Team color

- **Players:**
  - `Spring.GetPlayerList(teamID)` - Players on a team
  - `Spring.GetPlayerInfo(playerID)` - Player name, active, spectator status
  - `Spring.GetAIInfo(teamID)` - AI information for a team

- **My Team:**
  - `Spring.GetMyTeamID()` - Current player's team ID
  - `Spring.GetMyAllyTeamID()` - Current player's ally team ID

### E. Unit Information
- **Unit Lists:**
  - `Spring.GetTeamUnits(teamID)` - All units on a team
  - `Spring.GetAllUnits()` - All units in the game
  - `Spring.GetSelectedUnits()` - Currently selected units

- **Unit Properties:**
  - `Spring.GetUnitDefID(unitID)` - Unit definition ID
  - `Spring.GetUnitTeam(unitID)` - Unit's team ID
  - `Spring.GetUnitPosition(unitID)` - Unit position (x, y, z)
  - `Spring.GetUnitHealth(unitID)` - Unit health, max health, paralyze, capture, build
  - `Spring.GetUnitVelocity(unitID)` - Unit velocity
  - `Spring.GetUnitHeading(unitID)` - Unit heading/direction
  - `Spring.GetUnitExperience(unitID)` - Unit experience level
  - `Spring.GetUnitCommands(unitID)` - Unit's current commands
  - `Spring.GetUnitStates(unitID)` - Unit states (active, cloaked, etc.)

- **Unit Types:**
  - `UnitDefs[unitDefID].name` - Unit name
  - `UnitDefs[unitDefID].isBuilder` - Is a builder unit
  - `UnitDefs[unitDefID].buildSpeed` - Build speed
  - `UnitDefs[unitDefID].buildOptions` - What it can build
  - `UnitDefs[unitDefID].metalCost` - Metal cost
  - `UnitDefs[unitDefID].energyCost` - Energy cost
  - `UnitDefs[unitDefID].metalMake` - Metal production
  - `UnitDefs[unitDefID].energyMake` - Energy production
  - `UnitDefs[unitDefID].metalUse` - Metal consumption
  - `UnitDefs[unitDefID].energyUse` - Energy consumption
  - `UnitDefs[unitDefID].maxHealth` - Maximum health
  - `UnitDefs[unitDefID].speed` - Movement speed
  - `UnitDefs[unitDefID].weapons` - Weapon definitions

### F. Unit Statistics (Per Team)
- **Unit Counts:**
  - Total units
  - Builders
  - Factories
  - Defenses
  - Economy units (metal extractors, energy generators)
  - Combat units

- **Unit Health Totals:**
  - Total health
  - Average health percentage
  - Units under construction

### G. Game State
- **Time:**
  - `Spring.GetGameSeconds()` - Current game time in seconds
  - `Spring.GetGameFrame()` - Current game frame number
  - `Spring.GetFPS()` - Current FPS

- **Map:**
  - `Spring.GetMapName()` - Map name
  - `Spring.GetMapDrawMode()` - Map draw mode
  - `Spring.GetMapDimensions()` - Map size

- **Mod Options:**
  - `Spring.GetModOptions()` - All mod options
  - `modOptions.raptor_queen_count` - Queen count setting
  - `modOptions.raptor_difficulty` - Difficulty setting

### H. Camera & View
- **View:**
  - `Spring.GetViewGeometry()` - Viewport size (vsx, vsy)
  - `Spring.GetCameraState()` - Camera position and rotation
  - `Spring.GetCameraPosition()` - Camera position
  - `Spring.GetCameraDirection()` - Camera direction
  - `Spring.GetCameraFOV()` - Field of view

### I. DataManager Internal State
- **`DataManager.getTeamKills()`** - Full team kills table `{teamID = killCount}`
- **`DataManager.getDeathMessages()`** - All death messages
- **`DataManager.getPlayerEcoAttractionsRaw()`** - Raw eco values `{teamID = ecoValue}`
- **`DataManager.getPlayerTeams()`** - List of player team IDs
- **`DataManager.getMetalIncomeTriggered()`** - Metal income thresholds triggered
- **`DataManager.getLastMetalCheckTime()`** - Last metal check timestamps

### J. Additional Calculated Metrics
- **Resource Efficiency:**
  - Metal income per builder
  - Energy income per generator
  - Resource storage percentage
  - Resource pull vs income ratio

- **Unit Efficiency:**
  - Build power per builder
  - Average unit health
  - Units per team
  - Unit type distribution

- **Game Progress:**
  - Time in current stage
  - Anger gain rate breakdown
  - Progress to next queen spawn
  - Queen health percentage (if spawned)

---

## Spring API Functions Reference

### Resource Functions
- `Spring.GetTeamResources(teamID, "metal")` - Returns: current, storage, pull, income, expense, share, sent, received
- `Spring.GetTeamResources(teamID, "energy")` - Returns: current, storage, pull, income, expense, share, sent, received

### Unit Functions
- `Spring.GetTeamUnits(teamID)` - Returns array of unit IDs
- `Spring.GetAllUnits()` - Returns array of all unit IDs
- `Spring.GetUnitDefID(unitID)` - Returns unit definition ID
- `Spring.GetUnitTeam(unitID)` - Returns team ID
- `Spring.GetUnitPosition(unitID)` - Returns x, y, z coordinates
- `Spring.GetUnitHealth(unitID)` - Returns health, maxHealth, paralyze, capture, build
- `Spring.GetUnitVelocity(unitID)` - Returns vx, vy, vz velocity
- `Spring.GetUnitExperience(unitID)` - Returns experience level

### Team & Player Functions
- `Spring.GetTeamList()` - Returns array of all team IDs
- `Spring.GetPlayerList(teamID)` - Returns array of player IDs on team
- `Spring.GetPlayerInfo(playerID)` - Returns name, active, spectator, teamID, allyTeamID
- `Spring.GetMyTeamID()` - Returns current player's team ID
- `Spring.GetMyAllyTeamID()` - Returns current player's ally team ID
- `Spring.GetGaiaTeamID()` - Returns Gaia/neutral team ID

### Game State Functions
- `Spring.GetGameSeconds()` - Returns current game time in seconds
- `Spring.GetGameFrame()` - Returns current game frame number
- `Spring.GetGameRulesParam(key)` - Returns game rule parameter value
- `Spring.GetModOptions()` - Returns table of mod options
- `Spring.GetSpectatingState()` - Returns boolean if spectating

### Timer Functions
- `Spring.GetTimer()` - Returns timer value
- `Spring.DiffTimers(timer1, timer2)` - Returns difference between timers

---

## Example: Adding New Data to Export

To add new data to the export, modify `queen_death_display_api.lua` in the `exportData()` function:

```lua
-- Example: Add unit count
local teamUnits = Spring.GetTeamUnits(trackedTeamID)
local unitCount = #teamUnits

-- Add to dataToExport
local dataToExport = {
    -- ... existing fields ...
    unitStats = {
        totalUnits = unitCount,
        -- ... more stats ...
    },
}
```

Then update the web interface JavaScript to display it in `index.html`.

---

## Notes

- All resource values are in game units (metal/energy per second)
- Timestamps are in game seconds (not real-world time)
- Team IDs are integers (0-based)
- Unit IDs are integers
- Some data requires HarmonyRaptor module to be available
- Spectator mode may limit access to certain team-specific data
- Data updates every 100ms by default (resources update every 2.5 seconds)

