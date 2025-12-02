function widget:GetInfo()
  return {
    name    = "LayoutPlannerPlus",
    desc    = "Modern layout editor + library with named saves, thumbnails, and intuitive tools",
    author  = "Custom",
    date    = "2025-12-02",
    license = "MIT",
    layer   = 0,
    enabled = true
  }
end

--------------------------------------------------------------------------------
-- Constants & basics (match original LayoutPlanner where useful)
--------------------------------------------------------------------------------

local Spring = Spring
local gl     = gl
local GL     = GL

local BU_SIZE     = 16         -- 1 BU = 16 game units
local HALF_BU     = BU_SIZE/2
local SQUARE_SIZE = 3 * BU_SIZE
local CHUNK_SIZE  = 4 * SQUARE_SIZE

local LAYOUT_DIR  = "LuaUI/Widgets/LayoutPlannerPlus/"

--------------------------------------------------------------------------------
-- Layout data
--------------------------------------------------------------------------------

local currentLayout = {
  buildings = {
    [1]  = {},
    [2]  = {},
    [3]  = {},
    [4]  = {},
    [6]  = {},
    [12] = {},
  },
  lines = {}
}

-- Kept for compatibility with existing layout files (buildings), but
-- not exposed in the UI anymore – LayoutPlannerPlus is line-focused.
local buildingTypes = {
  { name = "Small",  size = 2 },
  { name = "Square", size = 3 },
  { name = "Big",    size = 4 },
  { name = "Large",  size = 6 },
  { name = "Chunk",  size = 12 },
}

local currentSizeIndex = 2      -- unused in Plus UI (line-only), kept for compatibility

--------------------------------------------------------------------------------
-- State: drawing & UI
--------------------------------------------------------------------------------

local drawingMode      = false
local drawingLinesMode = false

-- Line drawing
local lineStart        = nil    -- for free lines
local removeDragStart  = nil    -- for right-drag removal box

local altMode          = false
local ctrlMode         = false

-- Remember drawing state when opening load popup
local wasDrawingBeforeLoad = false

-- Save dialog
local showSaveDialog   = false
local saveNameText     = ""

-- Line snap modes: 0=none, 1=intersections, 2=midpoints, 3=thirds
local lineSnapMode     = 1      -- default to intersections

-- Library / saved layouts
local savedLayouts     = {}     -- { { name, tags, filename, data }, ... }
local filteredLayouts  = {}
local selectedIndex    = nil    -- index into filteredLayouts
local selectedData     = nil    -- layout table of selected
local searchText       = ""

-- Layout transformation state (for selected layout preview/placement)
local layoutRotation   = 0      -- rotation angle in degrees (0, 90, 180, 270)
local layoutInverted  = false  -- horizontal inversion (flip x)

--------------------------------------------------------------------------------
-- Windows: main + load popup
--------------------------------------------------------------------------------

-- Main window (draggable)
local mainX, mainY     = 40, 200
local mainDragging     = false
local mainDragDX, mainDragDY = 0, 0
local MAIN_TITLE_H     = 24
local MAIN_WIDTH       = 360
local MAIN_PADDING     = 10   -- padding around elements

-- Load popup (draggable)
local loadPopupVisible = false
local loadX, loadY     = 200, 220
local loadDragging     = false
local loadDragDX, loadDragDY = 0, 0
local LOAD_TITLE_H     = 24
local LOAD_WIDTH       = 460
local LOAD_HEIGHT      = 260

--------------------------------------------------------------------------------
-- Coordinate helpers
--------------------------------------------------------------------------------

local function WorldToBU(x, z)
  return math.floor(x / BU_SIZE), math.floor(z / BU_SIZE)
end

local function BUToWorld(bx, bz)
  return bx * BU_SIZE, bz * BU_SIZE
end

-- Snap BU coordinates based on snap mode
local function SnapBU(bx, bz, mode)
  if mode == 0 then
    -- Off: no snapping
    return bx, bz
  elseif mode == 1 then
    -- "Intersect": snap to 3 × Third = 3 BU = 48 game units
    local step = 3
    local sx = math.floor(bx / step + 0.5) * step
    local sz = math.floor(bz / step + 0.5) * step
    return sx, sz
  elseif mode == 2 then
    -- "Mid": snap to 1.5 × Third = 1.5 BU = 24 game units
    -- Convert to game units, snap, then back to BU
    local xWorld = bx * BU_SIZE
    local zWorld = bz * BU_SIZE
    local stepIGU = 16 * 1.5  -- 24 game units
    local sxWorld = math.floor(xWorld / stepIGU + 0.5) * stepIGU
    local szWorld = math.floor(zWorld / stepIGU + 0.5) * stepIGU
    return sxWorld / BU_SIZE, szWorld / BU_SIZE
  elseif mode == 3 then
    -- "Thirds": use simple 1‑BU spacing (same integer grid as cross layout)
    return math.floor(bx + 0.5), math.floor(bz + 0.5)
  end
  -- fallback: if mode is invalid, just return original
  return bx, bz
end

--------------------------------------------------------------------------------
-- Layout transformation helpers
--------------------------------------------------------------------------------

-- Transform a BU coordinate (x, z) based on rotation and inversion
-- rotation: 0, 90, 180, or 270 degrees
-- inverted: if true, flip about Y axis (mirror left/right, negate x)
local function TransformBU(x, z, rotation, inverted)
  local tx, tz = x, z
  -- Apply inversion first (flip about Y axis = mirror left/right)
  -- This makes inversion independent of rotation
  if inverted then
    tx = -tx
  end
  -- Then apply rotation (clockwise)
  if rotation == 90 then
    tx, tz = -tz, tx
  elseif rotation == 180 then
    tx, tz = -tx, -tz
  elseif rotation == 270 then
    tx, tz = tz, -tx
  end
  return tx, tz
end

--------------------------------------------------------------------------------
-- Layout helpers
--------------------------------------------------------------------------------

local function ClearCurrentLayout()
  for size, group in pairs(currentLayout.buildings) do
    currentLayout.buildings[size] = {}
  end
  currentLayout.lines = {}
  Spring.Echo("[LayoutPlus] Cleared current layout")
end

local function AddBuilding(bx, bz, size)
  -- kept for compatibility, but not used in Plus (line-focused)
  local group = currentLayout.buildings[size]
  if not group then return end
  group[#group + 1] = { bx, bz }
end

local function ToggleBuilding(bx, bz, size)
  -- disabled in Plus: we focus on line drawing only
  return
end

local function AddLineBU(x1, z1, x2, z2)
  if x1 == x2 and z1 == z2 then return end
  if x2 < x1 or (x2 == x1 and z2 < z1) then
    x1, z1, x2, z2 = x2, z2, x1, z1
  end
  currentLayout.lines[#currentLayout.lines + 1] = { x1, z1, x2, z2 }
end

--------------------------------------------------------------------------------
-- Save / load: file format & IO
--------------------------------------------------------------------------------

local function EnsureLayoutDir()
  -- attempt to write a tiny test and remove it
  local f = io.open(LAYOUT_DIR .. ".test", "w")
  if f then
    f:write("ok")
    f:close()
    os.remove(LAYOUT_DIR .. ".test")
  end
end

local function ComputeBounds(layout)
  local minX, maxX = math.huge, -math.huge
  local minZ, maxZ = math.huge, -math.huge

  for size, group in pairs(layout.buildings or {}) do
    for _, pos in ipairs(group) do
      local x, z = pos[1], pos[2]
      minX = math.min(minX, x)
      maxX = math.max(maxX, x + size - 1)
      minZ = math.min(minZ, z)
      maxZ = math.max(maxZ, z + size - 1)
    end
  end

  for _, line in ipairs(layout.lines or {}) do
    local x1, z1, x2, z2 = line[1], line[2], line[3], line[4]
    minX = math.min(minX, x1, x2)
    maxX = math.max(maxX, x1, x2)
    minZ = math.min(minZ, z1, z2)
    maxZ = math.max(maxZ, z1, z2)
  end

  if minX == math.huge then
    return nil
  end

  return minX, maxX, minZ, maxZ
end

local function SaveLayoutAs(name, tags)
  if not ComputeBounds(currentLayout) then
    Spring.Echo("[LayoutPlus] Nothing to save")
    return
  end
  name = name or "layout"
  local safeName = name:gsub("[^%w_%-]", "_")
  if safeName == "" then safeName = "layout" end
  local filename = LAYOUT_DIR .. safeName .. ".txt"

  -- avoid overwriting by appending a number if exists
  local counter = 1
  local base = safeName
  while true do
    local f = io.open(filename, "r")
    if not f then break end
    f:close()
    safeName = base .. "_" .. counter
    filename = LAYOUT_DIR .. safeName .. ".txt"
    counter = counter + 1
  end

  local minX, maxX, minZ, maxZ = ComputeBounds(currentLayout)
  local width  = maxX - minX + 1
  local height = maxZ - minZ + 1

  local function serializeLayout()
    local result = {}
    local indent = 0

    local function ind() return string.rep("  ", indent) end
    local function line(s) result[#result+1] = ind() .. s end

    line("layout = {")
    indent = indent + 1

    -- buildings
    line("buildings = {")
    indent = indent + 1
    for size, group in pairs(currentLayout.buildings) do
      line("[" .. size .. "] = {")
      indent = indent + 1
      for _, pos in ipairs(group) do
        local x = pos[1] - minX
        local z = pos[2] - minZ
        line(string.format("{%d, %d},", x, z))
      end
      indent = indent - 1
      line("},")
    end
    indent = indent - 1
    line("},") -- end buildings

    -- lines
    line("lines = {")
    indent = indent + 1
    for _, ln in ipairs(currentLayout.lines) do
      local x1, z1, x2, z2 = ln[1]-minX, ln[2]-minZ, ln[3]-minX, ln[4]-minZ
      line(string.format("{%d, %d, %d, %d},", x1, z1, x2, z2))
    end
    indent = indent - 1
    line("}")

    indent = indent - 1
    line("}") -- end layout

    return table.concat(result, "\n")
  end

  local f = io.open(filename, "w")
  if not f then
    Spring.Echo("[LayoutPlus] Could not open " .. filename .. " for write")
    return
  end

  f:write("return {\n")
  f:write("  name = " .. string.format("%q", name) .. ",\n")
  if tags and #tags > 0 then
    f:write("  tags = {")
    for i, t in ipairs(tags) do
      if i > 1 then f:write(", ") end
      f:write(string.format("%q", t))
    end
    f:write("},\n")
  end
  f:write("  width = " .. width .. ",\n")
  f:write("  height = " .. height .. ",\n")
  f:write("  maxX = " .. maxX .. ",\n")
  f:write("  maxZ = " .. maxZ .. ",\n")
  f:write("  minSize = 1,\n")
  f:write("  " .. serializeLayout() .. "\n")
  f:write("}\n")
  f:close()

  Spring.Echo("[LayoutPlus] Saved layout as " .. filename)
end

local function CopyEmptyLayout()
  local copy = {
    buildings = {
      [1]  = {},
      [2]  = {},
      [3]  = {},
      [4]  = {},
      [6]  = {},
      [12] = {},
    },
    lines = {}
  }
  return copy
end

local function LoadLayoutData(raw)
  -- raw: table returned from layout file (may be old or new)
  local layout = CopyEmptyLayout()
  if not raw or type(raw) ~= "table" or type(raw.layout) ~= "table" then
    return layout
  end

  local l = raw.layout

  -- buildings
  if type(l.buildings) == "table" then
    for size, group in pairs(l.buildings) do
      if layout.buildings[size] then
        for _, pos in ipairs(group) do
          layout.buildings[size][#layout.buildings[size]+1] = { pos[1], pos[2] }
        end
      end
    end
  end

  -- lines
  if type(l.lines) == "table" then
    for _, ln in ipairs(l.lines) do
      if #ln == 4 then
        layout.lines[#layout.lines+1] = { ln[1], ln[2], ln[3], ln[4] }
      end
    end
  end

  return layout
end

local function RefreshSavedLayouts()
  savedLayouts = {}

  if VFS and VFS.DirList then
    -- 1) New-format layouts in LayoutPlannerPlus folder
    local files = VFS.DirList(LAYOUT_DIR, "*.txt", VFS.RAW_FIRST)
    for _, full in ipairs(files or {}) do
      local short = full:match("([^/\\]+)$") or full
      local chunk, err = loadfile(full)
      if chunk then
        local ok, raw = pcall(chunk)
        if ok and type(raw) == "table" then
          local name = raw.name
          if type(name) ~= "string" or name == "" then
            name = short:gsub("%.txt$", ""):gsub("_", " ")
          end
          local tags = raw.tags or {}
          local layout = LoadLayoutData(raw)
          savedLayouts[#savedLayouts+1] = {
            name     = name,
            tags     = tags,
            filename = full,
            data     = layout,
          }
        end
      else
        Spring.Echo("[LayoutPlus] loadfile error: " .. tostring(err))
      end
    end

    -- 2) Legacy layouts in main Widgets folder: layout_*.txt
    local legacy = VFS.DirList("LuaUI/Widgets/", "layout_*.txt", VFS.RAW_FIRST)
    for _, full in ipairs(legacy or {}) do
      -- Skip if already in savedLayouts list
      local already = false
      for _, it in ipairs(savedLayouts) do
        if it.filename == full then
          already = true
          break
        end
      end
      if not already then
        local short = full:match("([^/\\]+)$") or full
        local chunk, err = loadfile(full)
        if chunk then
          local ok, raw = pcall(chunk)
          if ok and type(raw) == "table" then
            local baseName = short:gsub("%.txt$", ""):gsub("_", " ")
            local name = (raw.name and raw.name ~= "") and raw.name or (baseName .. " (legacy)")
            local tags = raw.tags or {}
            local layout = LoadLayoutData(raw)
            savedLayouts[#savedLayouts+1] = {
              name     = name,
              tags     = tags,
              filename = full,
              data     = layout,
            }
          end
        else
          Spring.Echo("[LayoutPlus] legacy loadfile error: " .. tostring(err))
        end
      end
    end
  end

  -- initial filtered list is full list
  filteredLayouts = savedLayouts
end

local function ApplySearchFilter()
  if searchText == "" then
    filteredLayouts = savedLayouts
    return
  end
  local query = searchText:lower()
  local out = {}
  for _, item in ipairs(savedLayouts) do
    local n = (item.name or ""):lower()
    local hit = n:find(query, 1, true)
    if not hit and item.tags then
      for _, t in ipairs(item.tags) do
        if t:lower():find(query, 1, true) then
          hit = true
          break
        end
      end
    end
    if hit then
      out[#out+1] = item
    end
  end
  filteredLayouts = out
end

--------------------------------------------------------------------------------
-- Thumbnail rendering for selected layout
--------------------------------------------------------------------------------

local function DrawThumbnailSelected(x0, y0, size)
  if not selectedData then
    return
  end

  local layout = selectedData
  local minX, maxX, minZ, maxZ = ComputeBounds(layout)
  if not minX then return end

  local w = maxX - minX
  local h = maxZ - minZ
  if w <= 0 or h <= 0 then return end

  local sx = (size - 16) / w
  local sz = (size - 16) / h
  local scale = math.min(sx, sz)

  local cx = (minX + maxX)/2
  local cz = (minZ + maxZ)/2

  gl.Color(0, 0, 0, 0.7)
  gl.Rect(x0, y0, x0 + size, y0 + size)

  gl.Color(0.5, 0.5, 0.5, 1)
  gl.LineWidth(1.5)
  gl.BeginEnd(GL.LINE_LOOP, function()
    gl.Vertex(x0,        y0)
    gl.Vertex(x0+size,   y0)
    gl.Vertex(x0+size,   y0+size)
    gl.Vertex(x0,        y0+size)
  end)

  -- draw buildings as small squares
  for sizeBU, group in pairs(layout.buildings) do
    for _, pos in ipairs(group) do
      local bx, bz = pos[1], pos[2]
      local lx = x0 + size/2 + (bx - cx) * scale
      local ly = y0 + size/2 + (bz - cz) * scale
      local half = (sizeBU * 0.4) * scale
      gl.Color(0.2, 0.8, 0.2, 0.9)
      gl.Rect(lx - half, ly - half, lx + half, ly + half)
    end
  end

  -- lines overlay
  gl.Color(1, 1, 0, 1)
  gl.LineWidth(1.5)
  gl.BeginEnd(GL.LINES, function()
    for _, ln in ipairs(layout.lines) do
      local x1 = x0 + size/2 + (ln[1] - cx) * scale
      local y1 = y0 + size/2 + (ln[2] - cz) * scale
      local x2 = x0 + size/2 + (ln[3] - cx) * scale
      local y2 = y0 + size/2 + (ln[4] - cz) * scale
      gl.Vertex(x1, y1)
      gl.Vertex(x2, y2)
    end
  end)
end

--------------------------------------------------------------------------------
-- Drawing tools (world)
--------------------------------------------------------------------------------

-- Remove nearest line to BU point
local function RemoveNearestLine(bx, bz, maxDist)
  maxDist = maxDist or 10
  local bestIdx = nil
  local bestDistSq = maxDist * maxDist
  for i, ln in ipairs(currentLayout.lines) do
    local x1, z1, x2, z2 = ln[1], ln[2], ln[3], ln[4]
    local dx, dz = x2 - x1, z2 - z1
    local lenSq = dx*dx + dz*dz
    local px, pz = bx, bz
    local t = 0
    if lenSq > 0 then
      t = ((px-x1)*dx + (pz-z1)*dz) / lenSq
      if t < 0 then t = 0 elseif t > 1 then t = 1 end
    end
    local projX = x1 + t*dx
    local projZ = z1 + t*dz
    local ddx, ddz = px - projX, pz - projZ
    local dSq = ddx*ddx + ddz*ddz
    if dSq <= bestDistSq then
      bestDistSq = dSq
      bestIdx = i
    end
  end
  if bestIdx then
    table.remove(currentLayout.lines, bestIdx)
    return true
  end
  return false
end

--------------------------------------------------------------------------------
-- Mouse handling
--------------------------------------------------------------------------------

-- Save dialog: draw + hit-test
local function DrawSaveDialog()
  if not showSaveDialog then return end

  local vsx, vsy = gl.GetViewSizes()
  local dialogWidth = 420
  local dialogHeight = 110
  local dialogX = (vsx - dialogWidth) / 2
  local dialogY = (vsy - dialogHeight) / 2

  -- Background
  gl.Color(0.1, 0.1, 0.1, 0.95)
  gl.Rect(dialogX, dialogY, dialogX + dialogWidth, dialogY + dialogHeight)

  -- Border
  gl.Color(0.5, 0.5, 0.5, 1.0)
  gl.LineWidth(2)
  gl.BeginEnd(GL.LINE_LOOP, function()
    gl.Vertex(dialogX, dialogY)
    gl.Vertex(dialogX + dialogWidth, dialogY)
    gl.Vertex(dialogX + dialogWidth, dialogY + dialogHeight)
    gl.Vertex(dialogX, dialogY + dialogHeight)
  end)

  -- Text
  gl.Color(1, 1, 1, 1)
  gl.Text("Save layout as:", dialogX + 10, dialogY + 78, 14, "")

  -- Input box
  gl.Color(0.2, 0.2, 0.2, 1.0)
  gl.Rect(dialogX + 10, dialogY + 48, dialogX + dialogWidth - 10, dialogY + 68)

  gl.Color(1, 1, 1, 1)
  local displayText = saveNameText
  if #displayText == 0 then
    displayText = "e.g. corner001 or wall02"
    gl.Color(0.5, 0.5, 0.5, 1.0)
  end
  gl.Text(displayText, dialogX + 14, dialogY + 52, 13, "")

  -- Buttons
  local btnY = dialogY + 14
  local btnWidth = 80
  local btnHeight = 24

  -- OK button
  gl.Color(0.2, 0.6, 0.2, 1.0)
  gl.Rect(dialogX + 10, btnY, dialogX + 10 + btnWidth, btnY + btnHeight)
  gl.Color(1, 1, 1, 1)
  gl.Text("OK", dialogX + 10 + 26, btnY + 6, 13, "")

  -- Cancel button
  gl.Color(0.6, 0.2, 0.2, 1.0)
  gl.Rect(dialogX + dialogWidth - 10 - btnWidth, btnY, dialogX + dialogWidth - 10, btnY + btnHeight)
  gl.Color(1, 1, 1, 1)
  gl.Text("Cancel", dialogX + dialogWidth - 10 - 48, btnY + 6, 13, "")
end

local function HitTestSaveDialog(mx, my)
  if not showSaveDialog then return nil end

  local vsx, vsy = gl.GetViewSizes()
  local dialogWidth = 420
  local dialogHeight = 110
  local dialogX = (vsx - dialogWidth) / 2
  local dialogY = (vsy - dialogHeight) / 2

  local btnY = dialogY + 14
  local btnWidth = 80
  local btnHeight = 24

  -- OK button
  if mx >= dialogX + 10 and mx <= dialogX + 10 + btnWidth and
     my >= btnY and my <= btnY + btnHeight then
    return "ok"
  end

  -- Cancel button
  if mx >= dialogX + dialogWidth - 10 - btnWidth and mx <= dialogX + dialogWidth - 10 and
     my >= btnY and my <= btnY + btnHeight then
    return "cancel"
  end

  return nil
end

local function HitInMain(mx, my)
  return mx >= mainX and mx <= mainX + MAIN_WIDTH and
         my >= mainY and my <= mainY + 180
end

local function HitInLoadPopup(mx, my)
  if not loadPopupVisible then return false end
  return mx >= loadX and mx <= loadX + LOAD_WIDTH and
         my >= loadY and my <= loadY + LOAD_HEIGHT
end

-- Simple hit regions inside main window
local function MainButtonHit(mx, my, bx, by, bw, bh)
  local lx, ly = mx - mainX, my - mainY
  return lx >= bx and lx <= bx + bw and ly >= by and ly <= by + bh
end

-- Button layout in main window
local BTN_W, BTN_H = 80, 24

local function MainButtonsLayout()
  local y = MAIN_TITLE_H + 10
  return {
    draw   = { x = 10,            y = y },
    clear  = { x = 10 + BTN_W+8,  y = y },
    save   = { x = 10 + 2*(BTN_W+8), y = y },
    load   = { x = 10 + 3*(BTN_W+8), y = y },
    render = { x = 10,            y = y + BTN_H + 8 },
  }
end

local function LoadPopupRegions()
  -- relative coords inside popup
  -- Close button moved to top-right corner, not in title bar
  return {
    searchBox = { x = 10, y = LOAD_HEIGHT - LOAD_TITLE_H - 30, w = 180, h = 20 },
    listBox   = { x = 10, y = 10, w = 200, h = LOAD_HEIGHT - LOAD_TITLE_H - 50 },
    thumbBox  = { x = 220, y = 50, w = 200, h = 200 },
    btnLoad   = { x = 220, y = 10, w = 60,  h = 24 },
    btnDel    = { x = 285, y = 10, w = 60,  h = 24 },
    btnDup    = { x = 350, y = 10, w = 60,  h = 24 },
    btnClose  = { x = LOAD_WIDTH - 70, y = 2, w = 60, h = 20 }  -- Top-right, not in title bar
  }
end

function widget:MousePress(mx, my, button)
  -- Save dialog clicks
  if showSaveDialog then
    local hit = HitTestSaveDialog(mx, my)
    if hit == "ok" then
      if saveNameText ~= "" then
        SaveLayoutAs(saveNameText, {})
        RefreshSavedLayouts()
        ApplySearchFilter()
      end
      showSaveDialog = false
      saveNameText = ""
      return true
    elseif hit == "cancel" then
      showSaveDialog = false
      saveNameText = ""
      return true
    end
    return true -- consume clicks while dialog open
  end
  -- Handle load popup first
  if loadPopupVisible then
    local relX = mx - loadX
    local relY = my - loadY
    local r = LoadPopupRegions()

    -- drag popup by title bar
    if button == 1 and relX >= 0 and relX <= LOAD_WIDTH and
       relY >= LOAD_HEIGHT - LOAD_TITLE_H and relY <= LOAD_HEIGHT then
      loadDragging = true
      loadDragDX, loadDragDY = mx - loadX, my - loadY
      return true
    end

    -- close button
    if button == 1 and
       relX >= r.btnClose.x and relX <= r.btnClose.x + r.btnClose.w and
       relY >= r.btnClose.y and relY <= r.btnClose.y + r.btnClose.h then
      loadPopupVisible = false
      -- restore drawing state when popup is closed without placement
      drawingMode = wasDrawingBeforeLoad
      return true
    end

    -- search box focus (we'll just always treat keyboard as updating search when popup visible)
    -- list click
    if button == 1 and
       relX >= r.listBox.x and relX <= r.listBox.x + r.listBox.w and
       relY >= r.listBox.y and relY <= r.listBox.y + r.listBox.h then
      local idx = #filteredLayouts
      if idx > 0 then
        -- rough row calc
        local rowH = 18
        local localY = relY - r.listBox.y
        local row = math.floor(localY / rowH) + 1
        if row >= 1 and row <= idx then
          selectedIndex = row
          selectedData  = filteredLayouts[row].data
          -- Reset transformation when selecting a new layout
          layoutRotation = 0
          layoutInverted = false
        end
      end
      return true
    end

    -- buttons Load/Delete/Duplicate
    if button == 1 then
      if relX >= r.btnLoad.x and relX <= r.btnLoad.x + r.btnLoad.w and
         relY >= r.btnLoad.y and relY <= r.btnLoad.y + r.btnLoad.h then
        -- select layout; popup closes, preview will be visible via selectedData
        if selectedIndex and filteredLayouts[selectedIndex] then
          loadPopupVisible = false
          -- keep drawing off until placement completes
        end
        return true
      end
      if relX >= r.btnDel.x and relX <= r.btnDel.x + r.btnDel.w and
         relY >= r.btnDel.y and relY <= r.btnDel.y + r.btnDel.h then
        if selectedIndex and filteredLayouts[selectedIndex] then
          local item = filteredLayouts[selectedIndex]
          if item.filename then
            os.remove(item.filename)
          end
          RefreshSavedLayouts()
          ApplySearchFilter()
          selectedIndex = nil
          selectedData  = nil
          layoutRotation = 0
          layoutInverted = false
        end
        return true
      end
      if relX >= r.btnDup.x and relX <= r.btnDup.x + r.btnDup.w and
         relY >= r.btnDup.y and relY <= r.btnDup.y + r.btnDup.h then
        if selectedIndex and filteredLayouts[selectedIndex] then
          local item = filteredLayouts[selectedIndex]
          if item and item.filename then
            local f = io.open(item.filename, "r")
            if f then
              local text = f:read("*all")
              f:close()
              -- find new filename
              local base = item.filename:gsub("%.txt$", "")
              local n = 1
              local newName
              while true do
                newName = base .. "_copy" .. n .. ".txt"
                local t = io.open(newName, "r")
                if not t then break end
                t:close()
                n = n + 1
              end
              local nf = io.open(newName, "w")
              if nf then
                nf:write(text)
                nf:close()
                RefreshSavedLayouts()
                ApplySearchFilter()
              end
            end
          end
        end
        return true
      end
    end

    -- while popup is open, block clicks from reaching world/drawing logic
    return true
  end

  -- main window buttons
  local btns = MainButtonsLayout()
  if button == 1 and HitInMain(mx, my) then
    if MainButtonHit(mx, my, btns.draw.x, btns.draw.y, BTN_W, BTN_H) then
      -- While load popup is open or a layout is attached to the mouse,
      -- do NOT allow toggling draw mode.
      if loadPopupVisible or selectedData then
        Spring.Echo("[LayoutPlus] Finish or cancel layout placement before toggling Draw")
        return true
      end
      drawingMode = not drawingMode
      Spring.Echo("[LayoutPlus] Drawing: " .. (drawingMode and "ON" or "OFF"))
      return true
    end
    if MainButtonHit(mx, my, btns.clear.x, btns.clear.y, BTN_W, BTN_H) then
      ClearCurrentLayout()
      return true
    end
    if MainButtonHit(mx, my, btns.save.x, btns.save.y, BTN_W, BTN_H) then
      -- open save name dialog
      showSaveDialog = true
      saveNameText = ""
      return true
    end
    if MainButtonHit(mx, my, btns.load.x, btns.load.y, BTN_W, BTN_H) then
      if #savedLayouts > 0 then
        -- remember drawing state, and turn drawing off while loading
        wasDrawingBeforeLoad = drawingMode
        drawingMode = false
        loadPopupVisible = true
        RefreshSavedLayouts()
        ApplySearchFilter()
      else
        Spring.Echo("[LayoutPlus] No saved layouts found")
      end
      return true
    end
    if MainButtonHit(mx, my, btns.render.x, btns.render.y, BTN_W, BTN_H) then
      -- render currentLayout as markers (buildings + lines)
      Spring.Echo("[LayoutPlus] Render button clicked")
      local lineCount = #currentLayout.lines
      local buildingCount = 0
      for size, group in pairs(currentLayout.buildings) do
        buildingCount = buildingCount + #group
      end
      Spring.Echo("[LayoutPlus] Rendering: " .. lineCount .. " lines, " .. buildingCount .. " buildings")
      -- Render buildings as edge lines
      for size, group in pairs(currentLayout.buildings) do
        for _, pos in ipairs(group) do
          local bx, bz = pos[1], pos[2]
          local x1, z1 = BUToWorld(bx, bz)
          local x2, z2 = BUToWorld(bx + size, bz)
          local x3, z3 = BUToWorld(bx + size, bz + size)
          local x4, z4 = BUToWorld(bx, bz + size)
          local y = Spring.GetGroundHeight((x1+x3)/2, (z1+z3)/2)
          -- Draw 4 edges of building
          Spring.MarkerAddLine(x1, y, z1, x2, y, z2)
          Spring.MarkerAddLine(x2, y, z2, x3, y, z3)
          Spring.MarkerAddLine(x3, y, z3, x4, y, z4)
          Spring.MarkerAddLine(x4, y, z4, x1, y, z1)
        end
      end
      -- Render lines
      for _, ln in ipairs(currentLayout.lines) do
        local x1, z1 = BUToWorld(ln[1], ln[2])
        local x2, z2 = BUToWorld(ln[3], ln[4])
        local y = Spring.GetGroundHeight((x1+x2)/2, (z1+z2)/2)
        Spring.MarkerAddLine(x1, y, z1, x2, y, z2)
      end
      Spring.Echo("[LayoutPlus] Rendered current layout as markers")
      return true
    end
  end

  -- snap mode buttons (inside main)
  if button == 1 and HitInMain(mx, my) then
    local lx, ly = mx - mainX, my - mainY
    local snapY = MAIN_TITLE_H + 10 + BTN_H + 8 + BTN_H + 10
    if ly >= snapY + 2 and ly <= snapY + 18 then
      local x = 80
      for i = 0, 3 do
        local w = 60
        if lx >= x and lx <= x + w then
          lineSnapMode = i
          local labels = {"Off", "Intersect", "Mid", "Third"}
          local steps = {"none", "3 BU (48 IGU)", "1.5 BU (24 IGU)", "1 BU (16 IGU)"}
          Spring.Echo("[LayoutPlus] Line snap: " .. labels[i+1] .. " (mode " .. i .. ", step: " .. steps[i+1] .. ")")
          return true
        end
        x = x + w + 4
      end
    end
  end

  -- main window drag (only title bar or empty edges, after button handling)
  if button == 1 and HitInMain(mx, my) then
    local lx, ly = mx - mainX, my - mainY
    -- main window height: two button rows + snap row + padding
    local contentH = MAIN_TITLE_H + 10 + BTN_H + 8 + BTN_H + 10 + 20 + 5
    local h        = contentH + MAIN_PADDING * 2
    local onTitleBar = ly >= h - MAIN_TITLE_H and ly <= h
    local edgeMargin = 5
    local onEdge = (lx <= edgeMargin or lx >= MAIN_WIDTH - edgeMargin or
                    ly <= edgeMargin or ly >= h - edgeMargin)
    if onTitleBar or onEdge then
      mainDragging = true
      mainDragDX, mainDragDY = mx - mainX, my - mainY
      return true
    end
  end

  -- placement of selected layout (when Draw: OFF)
  if not drawingMode and selectedData and button == 1 then
    local _, pos = Spring.TraceScreenRay(mx, my, true)
    if pos then
      local bx, bz = WorldToBU(pos[1], pos[3])
      local layout = selectedData
      local minX, maxX, minZ, maxZ = ComputeBounds(layout)
      if minX then
        local cx = (minX + maxX)/2
        local cz = (minZ + maxZ)/2
        -- copy buildings as line edges (with transformation)
        for size, group in pairs(layout.buildings) do
          for _, posBU in ipairs(group) do
            -- Transform relative to center
            local relX1, relZ1 = TransformBU(posBU[1] - cx, posBU[2] - cz, layoutRotation, layoutInverted)
            local relX2, relZ2 = TransformBU(posBU[1] - cx + size, posBU[2] - cz, layoutRotation, layoutInverted)
            local relX3, relZ3 = TransformBU(posBU[1] - cx + size, posBU[2] - cz + size, layoutRotation, layoutInverted)
            local relX4, relZ4 = TransformBU(posBU[1] - cx, posBU[2] - cz + size, layoutRotation, layoutInverted)
            -- Translate to cursor position (center of layout at cursor)
            local sx1, sz1 = relX1 + bx, relZ1 + bz
            local sx2, sz2 = relX2 + bx, relZ2 + bz
            local sx3, sz3 = relX3 + bx, relZ3 + bz
            local sx4, sz4 = relX4 + bx, relZ4 + bz
            AddLineBU(sx1, sz1, sx2, sz2)
            AddLineBU(sx2, sz2, sx3, sz3)
            AddLineBU(sx3, sz3, sx4, sz4)
            AddLineBU(sx4, sz4, sx1, sz1)
          end
        end
        -- copy layout lines (with transformation)
        for _, ln in ipairs(layout.lines) do
          -- Transform relative to center
          local relX1, relZ1 = TransformBU(ln[1] - cx, ln[2] - cz, layoutRotation, layoutInverted)
          local relX2, relZ2 = TransformBU(ln[3] - cx, ln[4] - cz, layoutRotation, layoutInverted)
          -- Translate to cursor position (center of layout at cursor)
          local sx1, sz1 = relX1 + bx, relZ1 + bz
          local sx2, sz2 = relX2 + bx, relZ2 + bz
          AddLineBU(sx1, sz1, sx2, sz2)
        end
        Spring.Echo("[LayoutPlus] Placed layout at cursor")
        -- stop following the mouse after placement and restore drawing state
        selectedData  = nil
        selectedIndex = nil
        drawingMode   = wasDrawingBeforeLoad
        layoutRotation = 0
        layoutInverted = false
        return true
      end
    end
  end

  -- drawing on map
  if not drawingMode then
    return false
  end

  local _, pos = Spring.TraceScreenRay(mx, my, true)
  if not pos then
    return false
  end

  local bx, bz = WorldToBU(pos[1], pos[3])

  if button == 1 then
    -- start line drawing
    lineStart = { bx = bx, bz = bz }
    return true
  elseif button == 3 then
    -- start removal drag (click or box)
    removeDragStart = { bx = bx, bz = bz }
    return true
  end

  return false
end

function widget:MouseMove(mx, my, dx, dy, button)
  if mainDragging then
    mainX, mainY = mx - mainDragDX, my - mainDragDY
    return
  end
  if loadDragging then
    loadX, loadY = mx - loadDragDX, my - loadDragDY
    return
  end
end

function widget:MouseRelease(mx, my, button)
  if button == 1 then
    if mainDragging then
      mainDragging = false
      return true
    end
    if loadDragging then
      loadDragging = false
      return true
    end
  end

  local _, pos = Spring.TraceScreenRay(mx, my, true)
  if not pos then
    lineStart = nil
    removeDragStart = nil
    return false
  end

  local bx, bz = WorldToBU(pos[1], pos[3])

  if button == 1 then
    -- drawing mode: finish line
    if not drawingMode then
      lineStart = nil
      removeDragStart = nil
      return false
    end

    if lineStart then
      -- free line with snap
      local sx1, sz1 = SnapBU(lineStart.bx, lineStart.bz, lineSnapMode)
      local sx2, sz2 = SnapBU(bx, bz, lineSnapMode)
      AddLineBU(sx1, sz1, sx2, sz2)
      lineStart = nil
      return true
    end
  elseif button == 3 and removeDragStart then
    -- right-drag removal: if small movement, treat as click; else box-remove
    local sx, sz = removeDragStart.bx, removeDragStart.bz
    local dx, dz = math.abs(bx - sx), math.abs(bz - sz)
    if dx <= 1 and dz <= 1 then
      -- click: remove nearest line
      if not RemoveNearestLine(bx, bz, 10) then
        Spring.Echo("[LayoutPlus] No line near click")
      end
    else
      -- box selection: remove lines whose midpoint is inside box
      local minX, maxX = math.min(sx, bx), math.max(sx, bx)
      local minZ, maxZ = math.min(sz, bz), math.max(sz, bz)
      for i = #currentLayout.lines, 1, -1 do
        local ln = currentLayout.lines[i]
        local mxl = (ln[1] + ln[3]) / 2
        local mzl = (ln[2] + ln[4]) / 2
        if mxl >= minX and mxl <= maxX and mzl >= minZ and mzl <= maxZ then
          table.remove(currentLayout.lines, i)
        end
      end
      Spring.Echo("[LayoutPlus] Removed lines in box")
    end
    removeDragStart = nil
    return true
  end

  return false
end

--------------------------------------------------------------------------------
-- Keyboard
--------------------------------------------------------------------------------

function widget:KeyPress(key, mods, isRepeat)
  if showSaveDialog then
    -- handle save name input
    if key == 8 then -- backspace
      saveNameText = saveNameText:sub(1, -2)
      return true
    elseif key == 27 then -- ESC
      showSaveDialog = false
      saveNameText = ""
      return true
    elseif key == 13 then -- ENTER
      if saveNameText ~= "" then
        SaveLayoutAs(saveNameText, {})
        RefreshSavedLayouts()
        ApplySearchFilter()
      end
      showSaveDialog = false
      saveNameText = ""
      return true
    elseif key >= 32 and key <= 126 then
      saveNameText = saveNameText .. string.char(key)
      return true
    end
    return true
  end

  if loadPopupVisible then
    -- ESC closes load popup and restores drawing state
    if key == 27 then -- ESC
      loadPopupVisible = false
      drawingMode = wasDrawingBeforeLoad
      return true
    end
    -- simple search input: letters/backspace
    if key == 8 then -- backspace
      searchText = searchText:sub(1, -2)
      ApplySearchFilter()
      return true
    elseif key >= 32 and key <= 126 then
      searchText = searchText .. string.char(key)
      ApplySearchFilter()
      return true
    end
  end

  -- ESC while a layout is preview-following the mouse cancels that preview
  if key == 27 and selectedData then
    selectedData  = nil
    selectedIndex = nil
    drawingMode   = wasDrawingBeforeLoad
    layoutRotation = 0
    layoutInverted = false
    return true
  end

  -- Rotation and inversion keys (only when layout is selected)
  if selectedData then
    if key == 114 then -- 'r' key
      layoutRotation = (layoutRotation + 90) % 360
      Spring.Echo("[LayoutPlus] Rotation: " .. layoutRotation .. "°")
      return true
    elseif key == 105 then -- 'i' key
      layoutInverted = not layoutInverted
      Spring.Echo("[LayoutPlus] Inverted: " .. (layoutInverted and "Yes" or "No"))
      return true
    end
  end

  if key == 306 then -- CTRL
    ctrlMode = true
  elseif key == 308 then -- ALT
    altMode = true
  end

  return false
end

function widget:KeyRelease(key, mods)
  if key == 306 then
    ctrlMode = false
  elseif key == 308 then
    altMode = false
  end
end

--------------------------------------------------------------------------------
-- DrawScreen: main window + popup
--------------------------------------------------------------------------------

function widget:DrawScreen()
  gl.Color(1, 1, 1, 1)
  gl.Blending(true)
  gl.DepthTest(false)

  -- main window (fixed content height + padding)
  local contentH = MAIN_TITLE_H + 10 + BTN_H + 8 + BTN_H + 10 + 20 + 5
  local h        = contentH + MAIN_PADDING * 2
  gl.Color(0, 0, 0, 0.7)
  gl.Rect(mainX, mainY, mainX + MAIN_WIDTH, mainY + h)

  gl.Color(0.1, 0.1, 0.1, 0.95)
  gl.Rect(mainX, mainY + h - MAIN_TITLE_H, mainX + MAIN_WIDTH, mainY + h)

  gl.Color(1, 0.7, 0.2, 1)
  gl.Text("LayoutPlannerPlus", mainX + 8, mainY + h - MAIN_TITLE_H + 4, 14, "")

  local btns = MainButtonsLayout()
  -- draw buttons
  for id, pos in pairs(btns) do
    local label, col
    if id == "draw" then
      label = drawingMode and "Draw: ON" or "Draw: OFF"
      col = drawingMode and {0.2, 0.8, 0.2, 0.9} or {0.5, 0.5, 0.5, 0.9}
    elseif id == "clear" then
      label = "Clear"
      col = {0.8, 0.2, 0.2, 0.9}
    elseif id == "save" then
      label = "Save"
      col = {0.15, 0.6, 0.25, 0.9}
    elseif id == "load" then
      label = "Load"
      if #savedLayouts == 0 then
        col = {0.3, 0.3, 0.3, 0.5}  -- Grey and semi-transparent when disabled
      else
        col = {0.3, 0.4, 1.0, 0.9}
      end
    elseif id == "render" then
      label = "Render"
      col = {0.4, 0.3, 0.8, 0.9}
    end
    gl.Color(col[1], col[2], col[3], col[4])
    gl.Rect(mainX + pos.x, mainY + pos.y, mainX + pos.x + BTN_W, mainY + pos.y + BTN_H)
    gl.Color(1,1,1,1)
    local tw = gl.GetTextWidth(label) * 12
    local tx = mainX + pos.x + (BTN_W - tw)/2
    local ty = mainY + pos.y + 6
    gl.Text(label, tx, ty, 12, "")
  end

  -- Line snap mode selector (only control row below main buttons)
  local snapY = mainY + MAIN_TITLE_H + 10 + BTN_H + 8 + BTN_H + 10
  gl.Color(0.2,0.2,0.2,0.9)
  gl.Rect(mainX + 10, snapY, mainX + MAIN_WIDTH - 10, snapY + 20)
  gl.Color(1,1,1,1)
  gl.Text("Line Snap:", mainX + 12, snapY + 4, 10, "")
  local snapLabels = {"Off", "Intersect", "Mid", "Third"}
  x = mainX + 80
  for i = 0, 3 do
    local w = 60
    local col = (i == lineSnapMode) and {0.3,0.6,0.9,0.9} or {0.15,0.15,0.15,0.9}
    gl.Color(col[1], col[2], col[3], col[4])
    gl.Rect(x, snapY + 2, x + w, snapY + 18)
    gl.Color(1,1,1,1)
    gl.Text(snapLabels[i+1], x+4, snapY + 5, 10, "")
    x = x + w + 4
  end

  -- hint text
  gl.Color(1,1,1,0.8)
  gl.Text("LMB Lines, RMB remove", mainX + 10, mainY + 10, 11, "")

  -- load popup
  if loadPopupVisible then
    gl.Color(0,0,0,0.8)
    gl.Rect(loadX, loadY, loadX + LOAD_WIDTH, loadY + LOAD_HEIGHT)

    gl.Color(0.1,0.1,0.1,0.95)
    gl.Rect(loadX, loadY + LOAD_HEIGHT - LOAD_TITLE_H, loadX + LOAD_WIDTH, loadY + LOAD_HEIGHT)

    gl.Color(1,0.7,0.2,1)
    gl.Text("Load Layout", loadX + 8, loadY + LOAD_HEIGHT - LOAD_TITLE_H + 4, 14, "")

    local r = LoadPopupRegions()

    -- search box
    gl.Color(0.15,0.15,0.15,0.9)
    gl.Rect(loadX + r.searchBox.x, loadY + r.searchBox.y,
            loadX + r.searchBox.x + r.searchBox.w, loadY + r.searchBox.y + r.searchBox.h)
    gl.Color(0.9,0.9,0.9,1)
    gl.Text(searchText ~= "" and searchText or "Search...", loadX + r.searchBox.x + 4, loadY + r.searchBox.y + 4, 11, "")

    -- list box
    gl.Color(0.1,0.1,0.1,0.9)
    gl.Rect(loadX + r.listBox.x, loadY + r.listBox.y,
            loadX + r.listBox.x + r.listBox.w, loadY + r.listBox.y + r.listBox.h)
    local rowH = 18
    for i, item in ipairs(filteredLayouts) do
      local iy = loadY + r.listBox.y + (i-1)*rowH
      if iy + rowH > loadY + r.listBox.y + r.listBox.h then
        break
      end
      local sel = (selectedIndex == i)
      gl.Color(sel and 0.3 or 0.2, sel and 0.5 or 0.2, sel and 0.8 or 0.2, 0.9)
      gl.Rect(loadX + r.listBox.x + 2, iy+2, loadX + r.listBox.x + r.listBox.w - 2, iy + rowH)
      gl.Color(1,1,1,1)
      gl.Text(item.name or "?", loadX + r.listBox.x + 6, iy + 4, 11, "")
    end

    -- buttons (Load/Delete/Duplicate/Close)
    local function drawBtn(b, label)
      gl.Color(0.25,0.25,0.25,0.9)
      gl.Rect(loadX + b.x, loadY + b.y, loadX + b.x + b.w, loadY + b.y + b.h)
      gl.Color(1,1,1,1)
      local tw = gl.GetTextWidth(label) * 11
      local tx = loadX + b.x + (b.w - tw)/2
      local ty = loadY + b.y + 4
      gl.Text(label, tx, ty, 11, "")
    end
    drawBtn(r.btnLoad,  "Load")
    drawBtn(r.btnDel,   "Delete")
    drawBtn(r.btnDup,   "Copy")
    drawBtn(r.btnClose, "Close")

    -- thumbnail
    if selectedData then
      DrawThumbnailSelected(loadX + r.thumbBox.x, loadY + r.thumbBox.y, 200)
    else
      gl.Color(0.1,0.1,0.1,0.9)
      gl.Rect(loadX + r.thumbBox.x, loadY + r.thumbBox.y,
              loadX + r.thumbBox.x + r.thumbBox.w, loadY + r.thumbBox.y + r.thumbBox.h)
      gl.Color(0.8,0.8,0.8,1)
      gl.Text("No layout selected", loadX + r.thumbBox.x + 20, loadY + r.thumbBox.y + 90, 12, "")
    end
  end

  -- save dialog
  DrawSaveDialog()
end

--------------------------------------------------------------------------------
-- DrawWorld: preview & layout
--------------------------------------------------------------------------------

function widget:DrawWorld()
  gl.DepthTest(true)

  -- draw currentLayout buildings
  for size, group in pairs(currentLayout.buildings) do
    for _, pos in ipairs(group) do
      local bx, bz = pos[1], pos[2]
      local wx, wz = BUToWorld(bx, bz)
      local wy = Spring.GetGroundHeight(wx, wz)
      gl.Color(0,1,0,0.3)
      gl.BeginEnd(GL.QUADS, function()
        gl.Vertex(wx,                 wy + 5, wz)
        gl.Vertex(wx + BU_SIZE*size, wy + 5, wz)
        gl.Vertex(wx + BU_SIZE*size, wy + 5, wz + BU_SIZE*size)
        gl.Vertex(wx,                 wy + 5, wz + BU_SIZE*size)
      end)
    end
  end

  -- draw currentLayout lines
  gl.Color(0,1,0,0.7)
  gl.LineWidth(2)
  gl.BeginEnd(GL.LINES, function()
    for _, ln in ipairs(currentLayout.lines) do
      local x1, z1 = BUToWorld(ln[1], ln[2])
      local x2, z2 = BUToWorld(ln[3], ln[4])
      local y1 = Spring.GetGroundHeight(x1, z1) + 5
      local y2 = Spring.GetGroundHeight(x2, z2) + 5
      gl.Vertex(x1, y1, z1)
      gl.Vertex(x2, y2, z2)
    end
  end)

  -- preview line being drawn (with snap)
  if lineStart and drawingMode then
    local mx, my = Spring.GetMouseState()
    local _, pos = Spring.TraceScreenRay(mx, my, true)
    if pos then
      local bx, bz = WorldToBU(pos[1], pos[3])
      local sx1, sz1 = SnapBU(lineStart.bx, lineStart.bz, lineSnapMode)
      local sx2, sz2 = SnapBU(bx, bz, lineSnapMode)
      local x1, z1 = BUToWorld(sx1, sz1)
      local x2, z2 = BUToWorld(sx2, sz2)
      local y1 = Spring.GetGroundHeight(x1, z1) + 6
      local y2 = Spring.GetGroundHeight(x2, z2) + 6
      gl.Color(1,1,0,0.8)
      gl.LineWidth(2)
      gl.BeginEnd(GL.LINES, function()
        gl.Vertex(x1, y1, z1)
        gl.Vertex(x2, y2, z2)
      end)
    end
  end

  -- preview of selected layout at cursor (lines + building edges)
  if selectedData and not loadPopupVisible then
    local mx, my = Spring.GetMouseState()
    local _, pos = Spring.TraceScreenRay(mx, my, true)
    if pos then
      local bx, bz = WorldToBU(pos[1], pos[3])
      local layout = selectedData
      local minX, maxX, minZ, maxZ = ComputeBounds(layout)
      if minX then
        local cx = (minX + maxX)/2
        local cz = (minZ + maxZ)/2
        gl.Color(1,1,0,0.5)
        gl.LineWidth(2)
        gl.BeginEnd(GL.LINES, function()
          -- building edges
          for size, group in pairs(layout.buildings) do
            for _, posBU in ipairs(group) do
              -- Transform relative to center
              local relX1, relZ1 = TransformBU(posBU[1] - cx, posBU[2] - cz, layoutRotation, layoutInverted)
              local relX2, relZ2 = TransformBU(posBU[1] - cx + size, posBU[2] - cz, layoutRotation, layoutInverted)
              local relX3, relZ3 = TransformBU(posBU[1] - cx + size, posBU[2] - cz + size, layoutRotation, layoutInverted)
              local relX4, relZ4 = TransformBU(posBU[1] - cx, posBU[2] - cz + size, layoutRotation, layoutInverted)
              -- Translate to cursor position (center of layout at cursor)
              local sx1, sz1 = relX1 + bx, relZ1 + bz
              local sx2, sz2 = relX2 + bx, relZ2 + bz
              local sx3, sz3 = relX3 + bx, relZ3 + bz
              local sx4, sz4 = relX4 + bx, relZ4 + bz
              local wx1, wz1 = BUToWorld(sx1, sz1)
              local wx2, wz2 = BUToWorld(sx2, sz2)
              local wx3, wz3 = BUToWorld(sx3, sz3)
              local wx4, wz4 = BUToWorld(sx4, sz4)
              local y = Spring.GetGroundHeight((wx1+wx3)/2, (wz1+wz3)/2) + 8
              gl.Vertex(wx1, y, wz1); gl.Vertex(wx2, y, wz2)
              gl.Vertex(wx2, y, wz2); gl.Vertex(wx3, y, wz3)
              gl.Vertex(wx3, y, wz3); gl.Vertex(wx4, y, wz4)
              gl.Vertex(wx4, y, wz4); gl.Vertex(wx1, y, wz1)
            end
          end
          -- layout lines
          for _, ln in ipairs(layout.lines) do
            -- Transform relative to center
            local relX1, relZ1 = TransformBU(ln[1] - cx, ln[2] - cz, layoutRotation, layoutInverted)
            local relX2, relZ2 = TransformBU(ln[3] - cx, ln[4] - cz, layoutRotation, layoutInverted)
            -- Translate to cursor position (center of layout at cursor)
            local sx1, sz1 = relX1 + bx, relZ1 + bz
            local sx2, sz2 = relX2 + bx, relZ2 + bz
            local wx1, wz1 = BUToWorld(sx1, sz1)
            local wx2, wz2 = BUToWorld(sx2, sz2)
            local y1 = Spring.GetGroundHeight(wx1, wz1) + 8
            local y2 = Spring.GetGroundHeight(wx2, wz2) + 8
            gl.Vertex(wx1, y1, wz1)
            gl.Vertex(wx2, y2, wz2)
          end
        end)
      end
    end
  end

  gl.DepthTest(false)
end

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------

function widget:Initialize()
  EnsureLayoutDir()
  RefreshSavedLayouts()
  ApplySearchFilter()
  Spring.Echo("[LayoutPlus] LayoutPlannerPlus initialized, found " .. tostring(#savedLayouts) .. " layouts")
  Spring.Echo("[LayoutPlus] To save with name: /luaui layoutplus_save <name>")
end

--------------------------------------------------------------------------------
-- Console command helper to save with a name
--------------------------------------------------------------------------------

function widget:TextCommand(cmd)
  local name = cmd:match("^layoutplus_save%s+(.+)$")
  if name then
    SaveLayoutAs(name, {})
    RefreshSavedLayouts()
    ApplySearchFilter()
    return true
  end
end


