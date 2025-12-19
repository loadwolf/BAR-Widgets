# LayoutPlannerPlus - Design Document

## Overview
A new widget that extends the functionality of LayoutPlanner.lua with a modern library-based approach to managing and placing layouts.

## Core Requirements

### Widget Location
- **Widget File**: `Custom/LayoutPlannerPlus.lua`
- **Save Folder**: `LuaUI/Widgets/LayoutPlannerPlus/`
- **Widget Name**: "LayoutPlannerPlus"

### File Naming & Storage
- **File Naming**: User-provided name becomes filename (sanitized)
  - Example: User enters "corner001" → saves as `corner001.txt`
  - Example: User enters "epic wall02" → saves as `epic_wall02.txt` (spaces → underscores)
- **Metadata Storage**: Store name inside each layout file (add `name` field to the return table)
- **Format Compatibility**: Support both old and new formats
  - **Read**: Can load old format (like `layout_1.txt`, `layout_5.txt`) and new format (with `name` field)
  - **Write**: Always saves in new format (with `name` field) for best compatibility

### Layout List UI
- **Display Type**: Scrollable list (show 5-10 items at a time, scroll up/down)
- **Location**: Popup window that appears when clicking "Load" button
- **Features**:
  - Shows all layouts in `LayoutPlannerPlus/` folder
  - Scrollable if more than visible items
  - Search/filter box at top to filter by name
  - Each list item shows: layout name
  - Selected item highlighted

### Thumbnail Preview
- **Location**: Inside the popup window (next to or below the list)
- **Size**: Medium (200x200 pixels)
- **Behavior**: Shows thumbnail of currently selected layout in the list
- **Content**: Scaled-down preview of the layout's buildings and lines

### Loading & Placement
- **Preview Behavior**: Immediately show preview at cursor (yellow/ghost lines) when layout is selected
- **Centering**: Center the layout's origin (0,0) on cursor (same as current LayoutPlanner behavior)
- **Action**: Click "Load" button in popup to confirm selection and close popup

### Additional Features
- **Delete Layout**: YES - Remove layout from list and delete file
- **Rename Layout**: NO
- **Duplicate Layout**: YES - Make a copy (append `_copy` to name)
- **Search/Filter**: YES - Filter list by name (case-insensitive substring match)
- **Categories/Tags**: YES - If possible (store tags in layout file, filter by tags)

### UI Style
- **Window Style**: Draggable window (like current LayoutPlanner)
- **Visual Style**: More modern/minimal
- **Main Widget**: Draggable window with buttons (Draw, Clear, Save, Load, Render)
- **Load Popup**: Separate draggable popup window with:
  - Search box at top
  - Scrollable layout list
  - Thumbnail preview area
  - Action buttons (Load, Delete, Duplicate, Close)

## Technical Implementation

### File Format
```lua
return {
  name = "corner001",           -- NEW: User-provided name
  tags = {"corner", "defense"},  -- NEW: Optional tags array
  width = 121,
  height = 97,
  maxX = 696,
  maxZ = 516,
  minSize = 12,
  layout = {
    buildings = {                -- Kept for compatibility with original LayoutPlanner
      [1] = {}, [2] = {}, [3] = {}, [4] = {}, [6] = {}, [12] = {}, -- optional
    },                           -- LayoutPlannerPlus itself is line-focused
    lines = {
      {x1, z1, x2, z2},
      ...
    }
  }
}
```

### Directory Listing
- Use `VFS.DirList("LuaUI/Widgets/LayoutPlannerPlus", "*.txt", VFS.RAW_FIRST)` to get all layout files
- Fallback: If VFS not available, scan sequentially (try files 1-1000)

### Thumbnail Generation
- Calculate bounding box of all buildings and lines
- Scale to fit 200x200 pixel area
- Draw using `gl` functions:
  - Buildings as colored rectangles
  - Lines as line segments
  - Maintain aspect ratio

### Search/Filter
- Keep in-memory list: `{name, tags, filename, layout_data}`
- Filter by:
  - Name (case-insensitive substring match)
  - Tags (if any tag matches search term)
- Update list display in real-time as user types

### Compatibility Handling
- **Loading old format**:
  - If `result.name` exists → use it
  - Otherwise → derive name from filename (remove `.txt`, replace underscores with spaces)
  - Example: `layout_1.txt` → "layout 1"
  - Example: `corner001.txt` → "corner001"
- **Saving**: Always include `name` field (and `tags` if provided)

## User Workflow

### Saving a Layout
1. User draws layout using **line tools** (left-drag to draw snapped lines, right-click/drag to remove).
2. Clicks **"Save"** button.
3. A **Save dialog** appears asking for layout name.
4. User enters name (e.g., "corner001") and confirms.
5. System sanitizes name and saves as `corner001.txt` in `LayoutPlannerPlus/` folder.
6. Layout file includes `name` (and optional `tags`) and becomes available in the Load list.

### Loading a Layout
1. User clicks "Load" button in main widget
2. Popup window appears showing list of all saved layouts
3. User can:
   - Type in search box to filter layouts
   - Scroll through list
   - Click on a layout to select it (shows thumbnail)
4. User clicks **"Load"** button in popup:
   - Popup closes.
   - A **yellow preview** of the layout appears at the cursor in the world.
5. With **Draw: OFF**, user left-clicks on the map to **place** the layout:
   - Buildings in the saved layout are converted to rectangular line contours.
   - Saved lines are copied into the current working layout as lines.

### Managing Layouts
- **Delete**: Select layout in popup, click "Delete" button, confirm
- **Duplicate**: Select layout in popup, click "Duplicate" button, new file created with `_copy` suffix
- **Search**: Type in search box to filter visible layouts

## Open Questions / Decisions (Updated)

1. **Drawing Tools**:  
   - DECISION: **Line-focused editor** – LayoutPlannerPlus primarily provides intuitive **line drawing/editing** tools (snapped line placement, box/point removal, clear, save), while still supporting building data for compatibility with existing layouts.

2. **Tags Implementation**:  
   - Initial implementation: **Simple** – store tags as an array in the file and filter by substring match in the search box.  
   - Future: possible tag picker UI and color coding (see Future Enhancements).

3. **Thumbnail Position in Popup**:  
   - Initial implementation: **Side-by-side** – list on the left, thumbnail on the right inside the same popup.

## Implementation Notes

### Lua Constraints
- **Directory Listing**: Use `VFS.DirList()` if available, otherwise sequential scan
- **File I/O**: Use `io.open()` for reading/writing
- **Thumbnails**: Draw using `gl` functions in `DrawScreen()` callback
- **Performance**: Only render thumbnail of selected item (not all items)

### Code Structure
- Main widget class with draggable window
- Separate popup window class for layout browser
- Layout manager class for file operations
- Thumbnail renderer utility
- Search/filter utility

## Future Enhancements (Not in Initial Version)
- Rename functionality
- Layout categories/folders
- Import from original LayoutPlanner slots
- Export to original LayoutPlanner format
- Layout statistics (building count, line count, etc.)
- Layout preview in 3D view

---

**Last Updated**: 2025-12-02
**Status**: In testing - Updated to reflect line-focused editor + library behavior

