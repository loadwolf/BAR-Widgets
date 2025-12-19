import re
import glob
from collections import defaultdict

# Dictionary to track max kill count per player
player_kills = defaultdict(int)

# Pattern to match: "Queen Killed by <PlayerName> #<number>"
pattern = r'Queen Killed by (.+?) #(\d+)'

# Process all .log files
log_files = glob.glob('*.log')
if not log_files:
    print("No .log files found in the current directory.")
else:
    for log_file in log_files:
        print(f"Processing: {log_file}")
        try:
            with open(log_file, 'r', encoding='utf-8') as f:
                lines = f.readlines()
            
            for line in lines:
                match = re.search(pattern, line)
                if match:
                    player_name = match.group(1).strip()
                    kill_number = int(match.group(2))
                    # Update max kill count for this player
                    if kill_number > player_kills[player_name]:
                        player_kills[player_name] = kill_number
        except Exception as e:
            print(f"Error processing {log_file}: {e}")

# Sort by kill count (descending)
sorted_kills = sorted(player_kills.items(), key=lambda x: x[1], reverse=True)

# Print results
print("\n" + "=" * 40)
print("Player Kill Counts (from all .log files):")
print("=" * 40)
for player, kills in sorted_kills:
    print(f"{player:30s} {kills:3d} kills")

print(f"\nTotal players: {len(sorted_kills)}")
print(f"Total kills: {sum(player_kills.values())}")

