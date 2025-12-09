# Queen Death Display - Real-Time Web Interface

This system provides a real-time web interface to monitor queen deaths, kill leaderboards, timers, and notifications from your Spring RTS game.

## Components

1. **`queen_death_display_api.lua`** - Lua widget that exports game data to JSON
2. **`web_server.py`** - Python web server that serves the data and HTML interface
3. **`index.html`** - Web interface that displays real-time data

## Setup

### 1. Enable the API Widget

The `queen_death_display_api.lua` widget should be placed in your `LuaUI/Widgets` directory alongside `queen_death_display.lua`. It will automatically be loaded if enabled.

The API widget:
- Reads data from the main `queen_death_display.lua` widget via a shared global table
- Exports data to `LuaUI/Widgets/QueenDeathDisplay/api/data.json` every second
- Requires the main widget to be running

### 2. Start the Web Server

1. Make sure you have Python 3 installed
2. Navigate to the `QueenDeathDisplay/api` directory
3. Run the web server:

```bash
python web_server.py
```

Or on Windows:
```bash
python web_server.py
```

The server will start on `http://localhost:8080`

### 3. Open the Web Interface

Open your web browser and navigate to:
```
http://localhost:8080
```

The interface will automatically refresh every second to show the latest game data.

## Features

### Real-Time Data Display

- **Timers**: No rush timer and queen arrival ETA
- **Queen Statistics**: Total, killed, and remaining queen counts
- **Kill Leaderboard**: Ranked list of players by queen kills
- **Recent Notifications**: Latest queen death and metal income notifications

### Data Updates

- Data is updated every second (1 second intervals)
- Connection status indicator shows if data is being received
- Timestamp shows when data was last updated

## File Structure

```
QueenDeathDisplay/
├── api/
│   ├── data.json          # Auto-generated JSON data file
│   ├── index.html         # Web interface
│   ├── web_server.py      # Python web server
│   └── README.md          # This file
└── ...
```

## Troubleshooting

### Widget Not Loading

- Make sure both `queen_death_display.lua` and `queen_death_display_api.lua` are in your `LuaUI/Widgets` directory
- Check the Spring console for error messages
- Verify both widgets are enabled in the F11 menu

### Web Server Not Starting

- Check that Python 3 is installed: `python --version`
- Make sure port 8080 is not already in use
- Check for error messages in the terminal

### No Data Showing

- Verify the game is running and the main widget is active
- Check that `data.json` is being created in the `api` directory
- Look at the browser console (F12) for JavaScript errors
- Check the connection status indicator (should be green "Connected")

### Data Not Updating

- The API widget updates data every 30 frames (~1 second)
- Make sure the game is running (not paused)
- Check that `data.json` file is being updated (check file modification time)

## Customization

### Change Port

Edit `web_server.py` and change the `PORT` variable:

```python
PORT = 8080  # Change to your preferred port
```

### Change Update Interval

Edit `queen_death_display_api.lua` and change `UPDATE_INTERVAL`:

```lua
local UPDATE_INTERVAL = 30  -- frames (30 = ~1 second at 30fps)
```

Or edit `index.html` and change the JavaScript update interval:

```javascript
const UPDATE_INTERVAL = 1000; // milliseconds
```

## Security Note

This web server is designed for local use only. It does not include authentication or security features. Do not expose it to the internet without proper security measures.

## Requirements

- Python 3.6 or higher
- Modern web browser (Chrome, Firefox, Edge, Safari)
- Spring RTS with both widgets enabled

