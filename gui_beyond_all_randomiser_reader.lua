-- SPDX-License-Identifier: GPL-2.0-or-later
-- Randomiser Reader, a Beyond All Random build-menu inspector.

local widget = widget ---@type Widget

function widget:GetInfo()
	return {
		name = "Randomiser Reader",
		desc = "Catalogues randomised commander and build-menu options",
		author = "The_Connecter",
		license = "GNU GPL, v2 or later",
		layer = -1000,
		enabled = false,
	}
end

-- This reads the UnitDefs behind build cards. It preloads every commander menu,
-- then remembers any constructor or factory menu selected during this game. It
-- deliberately does not inspect units that have already been built, and it
-- does not attempt fragile screen-text parsing.
--
-- The randomiser must expose its tiers through UnitDefs[].customParams.rarity
-- (and optionally customParams.cursed) for the rarity highlighting to work.

local TYPE_FILTERS = { "ALL", "COMBAT", "BUILDER", "ECON", "DEFENCE", "AIR", "NAVAL", "OTHER" }
local RARITY_FILTERS = { "ALL", "GREAT", "CHANGED" }
local SORTS = { "RARITY", "RANGE", "DPS/M", "DPS", "HP/M", "NAME" }
local GREAT_RARITY_MIN = 4 -- Epic and above

local RARITY_NAMES = {
	[0] = "Common",
	[1] = "Uncommon",
	[2] = "Rare",
	[3] = "Exceptional",
	[4] = "Epic",
	[5] = "Exotic",
	[6] = "Legendary",
	[7] = "Mythical",
	[8] = "Miracle",
	[9] = "Divine",
	[10] = "Eternal",
	[11] = "Supreme",
	[12] = "Omega",
	[13] = "Unique",
	[14] = "Jackpot",
	[15] = "Immortal",
	[16] = "Absurd",
	[17] = "Godlike",
	[18] = "TooRNG",
	[19] = "Insanely Lucky",
	[20] = "Dope",
	[21] = "Admin",
	[22] = "GOD",
	[23] = "ERROR",
	[24] = "Super Saiyan",
	[25] = "Beyond",
	[26] = "MGGW",
	[27] = "AMBO",
	[28] = "Beyond All Reason",
}

local PANEL_W = 390
local HEADER_H = 30
local TOOLBAR_H = 28
local FOOTER_H = 16
local ROW_H = 72
local MAX_ROWS = 5
local PAD = 8

local panelX = 40
local panelY = 170
local panelH = HEADER_H + TOOLBAR_H + PAD * 2 + FOOTER_H + ROW_H * 4
local viewW, viewH = Spring.GetViewGeometry()
local hasSavedPosition = false
local typeFilterIndex = 1
local rarityFilterIndex = 1
local sortIndex = 1
local scrollOffset = 0
local rows = {}
local dragging = false
local dragOffsetX, dragOffsetY = 0, 0
local refreshTimer = 0
local refreshEvery = 0.5
local selectedBuilderCount = 0
local showingCachedBuildBar = false
local catalogueByDefID = {}
local commanderCatalogueLoaded = false

local function clamp(value, low, high)
	if value < low then return low end
	if value > high then return high end
	return value
end

local function inRect(x, y, left, bottom, width, height)
	return x >= left and x <= left + width and y >= bottom and y <= bottom + height
end

local function safeText(value)
	if value == nil then return "" end
	value = tostring(value):gsub("\n", " "):gsub("\r", " ")
	return value
end

local function firstLine(value)
	value = tostring(value or "")
	return safeText(value:match("^[^\n\r]+") or value)
end

local function trimText(value, maxChars)
	value = safeText(value)
	if #value > maxChars then
		return value:sub(1, maxChars - 3) .. "..."
	end
	return value
end

local function parseMk(text)
	local value = text:match("[Mm][Kk]%.?%s*(%d+)")
	return tonumber(value)
end

local function parseXpTag(text)
	-- Examples seen in the supplied screenshots: "XP x12" and "XP /3".
	-- These are retained as display hints and treated as a rough sort signal.
	local multiplier = text:match("[Xx][Pp]%s*[xX]%s*([%d%.]+)")
	if multiplier then
		return tonumber(multiplier), "x" .. multiplier
	end

	local divisor = text:match("[Xx][Pp]%s*/%s*([%d%.]+)")
	if divisor then
		local n = tonumber(divisor)
		if n and n > 0 then return 1 / n, "/" .. divisor end
	end

	return nil, nil
end

local function customParams(def)
	return def.customParams or def.customparams or {}
end

local function asEnabled(value)
	return value ~= nil
		and tostring(value) ~= ""
		and tostring(value) ~= "0"
		and tostring(value):lower() ~= "false"
end

local function formatNumber(value)
	value = tonumber(value) or 0
	if value >= 1000000 then return string.format("%.1fm", value / 1000000):gsub("%.0m", "m") end
	if value >= 1000 then return string.format("%.1fk", value / 1000):gsub("%.0k", "k") end
	return tostring(math.floor(value + 0.5))
end

local function factionFor(def)
	local params = customParams(def)
	local name = safeText(def.name):lower()
	local signature = table.concat({
		safeText(params.faction), safeText(params.side), safeText(params.subfolder), safeText(params.normaltex), name,
	}, " "):lower()
	if name:match("^arm") or signature:find("armada", 1, true) or signature:find("arm_", 1, true) then return "Armada" end
	if name:match("^cor") or signature:find("cortex", 1, true) or signature:find("cor_", 1, true) then return "Cortex" end
	if name:match("^leg") or signature:find("legion", 1, true) or signature:find("leg_", 1, true) then return "Legion" end
	return "Other"
end

local function techTierFor(def)
	local params = customParams(def)
	local level = tonumber(params.techlevel)
	if not level then
		local subfolder = safeText(params.subfolder):lower()
		if subfolder:find("/t3", 1, true) then level = 3
		elseif subfolder:find("/t2", 1, true) then level = 2
		elseif subfolder:find("/t1", 1, true) then level = 1 end
	end
	if not level then return "T?" end
	local display = string.format("%.1f", level):gsub("%.0$", "")
	return "T" .. display
end

local function displayDefName(def)
	return safeText(def.translatedHumanName or def.humanName or def.name or "Builder")
end

local function builderLabel(def)
	local params = customParams(def)
	local faction = factionFor(def)
	if asEnabled(params.iscommander) then
		local level = safeText(def.name):lower():match("comlvl(%d+)")
		return faction .. " Commander" .. (level and (" L" .. level) or "")
	end
	return trimText(displayDefName(def), 30) .. " (" .. faction .. ")"
end

local function weaponDefFor(slot)
	local reference = slot and (slot.weaponDef or slot.weaponDefID or slot.def)
	if type(reference) == "table" then return reference end
	if type(reference) == "string" and WeaponDefNames and WeaponDefNames[reference] then
		reference = WeaponDefNames[reference].id
	end
	if type(reference) == "number" and WeaponDefs then return WeaponDefs[reference] end
	return nil
end

local function dpsFor(def)
	local total = 0
	for _, slot in pairs(def.weapons or {}) do
		local weapon = weaponDefFor(slot)
		if weapon and not asEnabled(weapon.paralyzer) and not asEnabled(weapon.stockpile) and not asEnabled(weapon.isShield) then
			local damages = weapon.damages or weapon.damage or {}
			local damage = tonumber(weapon.damage) or tonumber(damages.default) or 0
			local burst = tonumber(weapon.salvoSize or weapon.burst) or 1
			local projectiles = tonumber(weapon.projectilesPerShot or weapon.projectiles) or 1
			local reload = tonumber(weapon.reload or weapon.reloadTime) or 1
			if damage > 0 and reload > 0 then
				total = total + (damage * burst * projectiles / reload)
			end
		end
	end
	return total
end

local function roleFor(def)
	local params = customParams(def)
	local group = safeText(params.unitgroup):lower()
	if def.canFly then return "AIR" end
	if group:find("builder", 1, true) or (def.buildSpeed or 0) > 0 then return "BUILDER" end
	if group:find("econom", 1, true) or group:find("energy", 1, true) or group:find("metal", 1, true)
		or (def.extractsMetal or 0) > 0 or (def.energyMake or 0) > 0 then return "ECON" end
	if (def.minWaterDepth or 0) > 0 then return "NAVAL" end
	if (def.maxWeaponRange or 0) > 0 then
		return (def.speed or 0) > 0 and "COMBAT" or "DEFENCE"
	end
	return "OTHER"
end

local function keyStatsFor(def, role)
	local parts = {
		role,
		factionFor(def),
		techTierFor(def),
		formatNumber(def.metalCost) .. "M",
		formatNumber(def.energyCost) .. "E",
	}
	return table.concat(parts, " | ")
end

local function combatStatsFor(def, dps)
	local parts = { "HP " .. formatNumber(def.health) }
	if (def.maxWeaponRange or 0) > 0 then
		parts[#parts + 1] = "R " .. formatNumber(def.maxWeaponRange)
	end
	if dps > 0 then
		parts[#parts + 1] = "DPS~ " .. formatNumber(dps)
		local metal = tonumber(def.metalCost) or 0
		if metal > 0 then parts[#parts + 1] = string.format("%.2f DPS/M", dps / metal) end
	end
	if (def.speed or 0) > 0 then
		parts[#parts + 1] = "S " .. formatNumber(def.speed)
	elseif (def.buildSpeed or 0) > 0 then
		parts[#parts + 1] = "BP " .. formatNumber(def.buildSpeed)
	end
	return table.concat(parts, " | ")
end

local function inspectBuildOption(defID)
	local def = UnitDefs[defID]
	if not def then return nil end

	-- Build cards do not yet have a UnitID. Their definition and tooltip are the
	-- authoritative data available before the player commits to building one.
	local tooltip = safeText(def.tooltip or def.description or "")
	local unitName = safeText(def.translatedHumanName or def.humanName or "")
	if unitName == "" then
		unitName = firstLine(tooltip)
	end
	if unitName == "" then
		unitName = safeText(def.name or "Unit")
	end

	-- Widgets normally see customParams; customparams is accepted for safety
	-- with variants of generated UnitDefs.
	local params = customParams(def)
	local rarity = tonumber(params.rarity) or 0
	local cursedValue = params.cursed
	local cursed = asEnabled(cursedValue)
	local rarityName = cursed and "Cursed" or (RARITY_NAMES[rarity] or (rarity > 0 and ("Tier " .. rarity) or "Common"))

	local mk = parseMk(tooltip)
	local xpTagValue, xpTagText = parseXpTag(tooltip)
	local score = cursed and -1000000 or (rarity * 1000 + math.max(0, (xpTagValue or 1) - 1) * 10)
	local changed = cursed or rarity > 0
	local great = not cursed and rarity >= GREAT_RARITY_MIN
	local role = roleFor(def)
	local dps = dpsFor(def)

	return {
		defID = defID,
		name = unitName,
		rarity = rarity,
		rarityName = rarityName,
		cursed = cursed,
		faction = factionFor(def),
		techTier = techTierFor(def),
		role = role,
		dps = dps,
		range = tonumber(def.maxWeaponRange) or 0,
		hpPerMetal = (tonumber(def.metalCost) or 0) > 0 and (tonumber(def.health) or 0) / tonumber(def.metalCost) or 0,
		keyStats = keyStatsFor(def, role),
		combatStats = combatStatsFor(def, dps),
		mk = mk,
		xpTagValue = xpTagValue,
		xpTagText = xpTagText,
		score = score,
		changed = changed,
		great = great,
	}
end

local function resolveBuildOptionDefID(key, value)
	local candidates = { value, key }
	for i = 1, #candidates do
		local candidate = candidates[i]
		if type(candidate) == "number" and UnitDefs[candidate] then
			return candidate
		end
		if type(candidate) == "string" then
			local numericID = tonumber(candidate)
			if numericID and UnitDefs[numericID] then return numericID end
			local namedDef = UnitDefNames and UnitDefNames[candidate]
			if namedDef and namedDef.id and UnitDefs[namedDef.id] then return namedDef.id end
		end
	end
	return nil
end

local function addBuildOptionsToCatalogue(builderDefID)
	local builderDef = UnitDefs[builderDefID]
	if not builderDef or not builderDef.buildOptions then return false end
	local foundOption = false
	for key, value in pairs(builderDef.buildOptions) do
		local optionDefID = resolveBuildOptionDefID(key, value)
		if optionDefID then
			foundOption = true
			local row = catalogueByDefID[optionDefID]
			if not row then
				row = inspectBuildOption(optionDefID)
				if row then
					row.builders = {}
					catalogueByDefID[optionDefID] = row
				end
			end
			if row then row.builders[builderDefID] = true end
		end
	end
	return foundOption
end

local function describeCatalogueBuilders(row)
	local commanders, labels = {}, {}
	for builderDefID in pairs(row.builders) do
		local builderDef = UnitDefs[builderDefID]
		if builderDef then
			if asEnabled(customParams(builderDef).iscommander) then
				commanders[factionFor(builderDef)] = true
			else
				labels[#labels + 1] = builderLabel(builderDef)
			end
		end
	end
	for faction in pairs(commanders) do labels[#labels + 1] = faction .. " Commander" end
	table.sort(labels)
	row.builderText = table.concat(labels, ", ")
	if row.builderText == "" then row.builderText = "known builder" end
end

local function refreshRows()
	-- The commander definitions exist before you select them. Preload all their
	-- build options once, then add any factory or constructor menu you inspect.
	if not commanderCatalogueLoaded then
		for builderDefID, builderDef in pairs(UnitDefs) do
			if asEnabled(customParams(builderDef).iscommander) then
				addBuildOptionsToCatalogue(builderDefID)
			end
		end
		commanderCatalogueLoaded = true
	end

	local currentBuilderCount = 0
	local selectedUnitIDs = Spring.GetSelectedUnits() or {}
	for i = 1, #selectedUnitIDs do
		local builderDefID = Spring.GetUnitDefID(selectedUnitIDs[i])
		if builderDefID and addBuildOptionsToCatalogue(builderDefID) then
			currentBuilderCount = currentBuilderCount + 1
		end
	end

	rows = {}
	for _, row in pairs(catalogueByDefID) do
		describeCatalogueBuilders(row)
		rows[#rows + 1] = row
	end
	selectedBuilderCount = currentBuilderCount
	showingCachedBuildBar = currentBuilderCount == 0
	local maxOffset = math.max(0, #rows - MAX_ROWS)
	scrollOffset = clamp(scrollOffset, 0, maxOffset)
end

local function visibleRows()
	local result = {}
	local typeFilter = TYPE_FILTERS[typeFilterIndex]
	local rarityFilter = RARITY_FILTERS[rarityFilterIndex]
	for i = 1, #rows do
		local row = rows[i]
		local matchingType = typeFilter == "ALL" or row.role == typeFilter
		local matchingRarity = rarityFilter == "ALL"
			or (rarityFilter == "GREAT" and row.great)
			or (rarityFilter == "CHANGED" and row.changed)
		if matchingType and matchingRarity then
			result[#result + 1] = row
		end
	end

	local sort = SORTS[sortIndex]
	table.sort(result, function(a, b)
		if sort == "NAME" then
			return a.name:lower() < b.name:lower()
		elseif sort == "RANGE" then
			if a.range ~= b.range then return a.range > b.range end
		elseif sort == "DPS/M" then
			local aValue = a.dps / math.max(1, tonumber(UnitDefs[a.defID].metalCost) or 1)
			local bValue = b.dps / math.max(1, tonumber(UnitDefs[b.defID].metalCost) or 1)
			if aValue ~= bValue then return aValue > bValue end
		elseif sort == "DPS" then
			if a.dps ~= b.dps then return a.dps > b.dps end
		elseif sort == "HP/M" then
			if a.hpPerMetal ~= b.hpPerMetal then return a.hpPerMetal > b.hpPerMetal end
		end
		if a.cursed ~= b.cursed then return not a.cursed end
		if a.rarity ~= b.rarity then return a.rarity > b.rarity end
		return a.name:lower() < b.name:lower()
	end)

	return result
end

local function rowStatsText(row)
	return row.keyStats
end

local function rowCombatText(row)
	return row.combatStats
end

local function rowBuildText(row)
	local parts = { "Can build: " .. row.builderText }
	if row.cursed then
		parts[#parts + 1] = "CURSED"
	else
		parts[#parts + 1] = row.rarityName .. " R" .. tostring(row.rarity)
	end
	if row.mk ~= nil then parts[#parts + 1] = "Mk." .. tostring(row.mk) end
	if row.xpTagText then parts[#parts + 1] = "XP " .. row.xpTagText end
	return table.concat(parts, " | ")
end

local function drawRect(x, y, width, height, r, g, b, a)
	gl.Color(r, g, b, a)
	gl.Rect(x, y, x + width, y + height)
end

local function drawText(text, x, y, size, r, g, b, a)
	gl.Color(r, g, b, a)
	gl.Text(text, x, y, size, "o")
end

local function clampPanel()
	viewW, viewH = Spring.GetViewGeometry()
	panelX = clamp(panelX, 0, math.max(0, viewW - PANEL_W))
	panelY = clamp(panelY, 0, math.max(0, viewH - panelH))
end

function widget:Initialize()
	viewW, viewH = Spring.GetViewGeometry()
	if not hasSavedPosition then
		panelX = math.max(20, viewW - PANEL_W - 24)
	end
	clampPanel()
	refreshRows()
end

function widget:ViewResize()
	clampPanel()
end

function widget:SelectionChanged()
	refreshRows()
end

function widget:Update(dt)
	refreshTimer = refreshTimer + (dt or 0)
	if refreshTimer >= refreshEvery then
		refreshTimer = 0
		refreshRows()
	end
end

function widget:DrawScreen()
	if Spring.IsGUIHidden and Spring.IsGUIHidden() then return end
	gl.Blending(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA)

	local shown = visibleRows()
	local visibleCount = math.min(MAX_ROWS, #shown)
	panelH = HEADER_H + TOOLBAR_H + PAD * 2 + FOOTER_H + math.max(1, visibleCount) * ROW_H
	scrollOffset = clamp(scrollOffset, 0, math.max(0, #shown - MAX_ROWS))
	clampPanel()

	local x, y = panelX, panelY
	drawRect(x, y, PANEL_W, panelH, 0.025, 0.035, 0.055, 0.94)
	drawRect(x, y + panelH - HEADER_H, PANEL_W, HEADER_H, 0.075, 0.12, 0.17, 0.98)
	drawRect(x, y + panelH - 2, PANEL_W, 2, 0.26, 0.53, 0.72, 1)
	drawText("RANDOMISER READER", x + 12, y + panelH - 21, 15, 0.88, 0.94, 1, 1)
	drawText("BUILD CATALOGUE", x + PANEL_W - 106, y + panelH - 20, 10, 0.59, 0.70, 0.79, 1)

	local toolbarY = y + panelH - HEADER_H - TOOLBAR_H
	local controlW = 118
	drawRect(x + PAD, toolbarY + 3, controlW, TOOLBAR_H - 6, 0.10, 0.15, 0.20, 1)
	drawRect(x + PAD + controlW + 4, toolbarY + 3, controlW, TOOLBAR_H - 6, 0.10, 0.15, 0.20, 1)
	drawRect(x + PAD + (controlW + 4) * 2, toolbarY + 3, PANEL_W - PAD * 2 - (controlW + 4) * 2, TOOLBAR_H - 6, 0.10, 0.15, 0.20, 1)
	drawText("TYPE: " .. TYPE_FILTERS[typeFilterIndex], x + PAD + 6, toolbarY + 11, 10, 0.76, 0.88, 0.96, 1)
	drawText("RARITY: " .. RARITY_FILTERS[rarityFilterIndex], x + PAD + controlW + 10, toolbarY + 11, 10, 0.76, 0.88, 0.96, 1)
	drawText("SORT: " .. SORTS[sortIndex], x + PAD + (controlW + 4) * 2 + 6, toolbarY + 11, 10, 0.76, 0.88, 0.96, 1)

	local bodyTop = toolbarY - FOOTER_H
	if #shown == 0 then
		local message = #rows == 0 and "No commander options found in this game" or "No build options match these filters"
		drawText(message, x + PAD + 4, y + panelH - HEADER_H - TOOLBAR_H - 28, 12, 0.72, 0.76, 0.80, 1)
		gl.Color(1, 1, 1, 1)
		return
	end

	for visibleIndex = 1, visibleCount do
		local index = visibleIndex + scrollOffset
		local row = shown[index]
		if row then
			local rowY = bodyTop - (visibleIndex * ROW_H)
			if row.cursed then
				drawRect(x + PAD, rowY + 2, PANEL_W - PAD * 2, ROW_H - 3, 0.18, 0.045, 0.055, 0.96)
				drawRect(x + PAD, rowY + 2, 4, ROW_H - 3, 0.93, 0.19, 0.25, 1)
			elseif row.great then
				drawRect(x + PAD, rowY + 2, PANEL_W - PAD * 2, ROW_H - 3, 0.19, 0.145, 0.045, 0.96)
				drawRect(x + PAD, rowY + 2, 4, ROW_H - 3, 0.96, 0.69, 0.18, 1)
			elseif row.changed then
				drawRect(x + PAD, rowY + 2, PANEL_W - PAD * 2, ROW_H - 3, 0.055, 0.115, 0.13, 0.94)
				drawRect(x + PAD, rowY + 2, 4, ROW_H - 3, 0.20, 0.76, 0.72, 1)
			else
				drawRect(x + PAD, rowY + 2, PANEL_W - PAD * 2, ROW_H - 3, 0.065, 0.075, 0.09, 0.92)
			end

			drawText(trimText(row.name, 48), x + PAD + 12, rowY + 53, 12, 0.94, 0.96, 0.98, 1)
			drawText(trimText(rowStatsText(row), 66), x + PAD + 12, rowY + 38, 10, 0.70, 0.80, 0.87, 1)
			drawText(trimText(rowCombatText(row), 66), x + PAD + 12, rowY + 24, 10, 0.70, 0.80, 0.87, 1)
			drawText(trimText(rowBuildText(row), 66), x + PAD + 12, rowY + 9, 10, 0.60, 0.70, 0.76, 1)

			local badge = row.cursed and "CURSED" or row.rarityName:upper()
			local badgeX = x + PANEL_W - math.min(100, #badge * 6 + 18)
			if row.cursed then
				drawText(badge, badgeX, rowY + 53, 10, 1, 0.32, 0.37, 1)
			elseif row.great then
				drawText(badge, badgeX, rowY + 53, 10, 1, 0.78, 0.27, 1)
			elseif row.changed then
				drawText(badge, badgeX, rowY + 53, 10, 0.28, 0.86, 0.78, 1)
			end
		end
	end

	local greatTypes, cursedTypes = 0, 0
	for i = 1, #rows do
		if rows[i].great then greatTypes = greatTypes + 1 end
		if rows[i].cursed then cursedTypes = cursedTypes + 1 end
	end
	local source = showingCachedBuildBar and "no builder selected" or (tostring(selectedBuilderCount) .. " live builders")
	local footer = string.format("%d remembered | %s | %d Epic+ | %d cursed", #rows, source, greatTypes, cursedTypes)
	drawText(trimText(footer, 69), x + PAD + 3, y + 5, 9, 0.54, 0.64, 0.70, 1)
	gl.Color(1, 1, 1, 1)
end

function widget:MousePress(x, y, button)
	if button ~= 1 or not inRect(x, y, panelX, panelY, PANEL_W, panelH) then return false end

	local headerBottom = panelY + panelH - HEADER_H
	if y >= headerBottom then
		dragging = true
		dragOffsetX = x - panelX
		dragOffsetY = y - panelY
		return true
	end

	local toolbarY = panelY + panelH - HEADER_H - TOOLBAR_H
	if y >= toolbarY and y <= toolbarY + TOOLBAR_H then
		local controlW = 118
		if x <= panelX + PAD + controlW then
			typeFilterIndex = (typeFilterIndex % #TYPE_FILTERS) + 1
			scrollOffset = 0
		elseif x <= panelX + PAD + (controlW + 4) * 2 then
			rarityFilterIndex = (rarityFilterIndex % #RARITY_FILTERS) + 1
			scrollOffset = 0
		else
			sortIndex = (sortIndex % #SORTS) + 1
		end
		return true
	end

	-- Build options have no UnitID yet, so rows are deliberately read-only.
	return true
end

function widget:MouseMove(x, y)
	if not dragging then return false end
	panelX = x - dragOffsetX
	panelY = y - dragOffsetY
	clampPanel()
	return true
end

function widget:MouseRelease()
	if not dragging then return false end
	dragging = false
	return true
end

function widget:MouseWheel(up, value)
	local mx, my = Spring.GetMouseState()
	if not inRect(mx, my, panelX, panelY, PANEL_W, panelH) then return false end
	local shown = visibleRows()
	local maxOffset = math.max(0, #shown - MAX_ROWS)
	local step = math.max(1, math.floor(value or 1))
	if up then
		scrollOffset = math.max(0, scrollOffset - step)
	else
		scrollOffset = math.min(maxOffset, scrollOffset + step)
	end
	return true
end

function widget:GetConfigData()
	return {
		panelX = panelX,
		panelY = panelY,
		typeFilterIndex = typeFilterIndex,
		rarityFilterIndex = rarityFilterIndex,
		sortIndex = sortIndex,
	}
end

function widget:SetConfigData(data)
	if type(data) ~= "table" then return end
	if tonumber(data.panelX) then panelX = tonumber(data.panelX) end
	if tonumber(data.panelY) then panelY = tonumber(data.panelY) end
	if tonumber(data.panelX) or tonumber(data.panelY) then hasSavedPosition = true end
	if tonumber(data.typeFilterIndex) then typeFilterIndex = clamp(math.floor(data.typeFilterIndex), 1, #TYPE_FILTERS) end
	if tonumber(data.rarityFilterIndex) then
		rarityFilterIndex = clamp(math.floor(data.rarityFilterIndex), 1, #RARITY_FILTERS)
	elseif tonumber(data.filterIndex) then
		rarityFilterIndex = clamp(math.floor(data.filterIndex), 1, #RARITY_FILTERS)
	end
	if tonumber(data.sortIndex) then sortIndex = clamp(math.floor(data.sortIndex), 1, #SORTS) end
end
