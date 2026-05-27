#!/bin/bash
set -e
export DISPLAY=:99

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

log() { echo -e "${GREEN}[TEST]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }

# Start Xvfb
log "Starting Xvfb..."
Xvfb :99 -screen 0 1280x800x24 &
sleep 2

# Start SSH server
log "Starting SSH server..."
service ssh start

# Start the app
log "Starting Picshell..."
/app/picshell &
APP_PID=$!
sleep 4

# Verify app window exists
WINDOW_ID=$(xdotool search --name "Picshell" | head -1)
if [ -z "$WINDOW_ID" ]; then
    fail "Picshell window not found!"
fi
log "Found window: $WINDOW_ID"

# Focus the window
xdotool windowactivate $WINDOW_ID
sleep 0.5

# Take initial screenshot
scrot /test_output/01_initial.png
log "Screenshot 1: Initial state"

# Find and click the "+" button (New Connection)
# The button is in the AppBar at the top right
xdotool mousemove --window $WINDOW_ID 750 50
sleep 0.3
xdotool click 1
sleep 2

scrot /test_output/02_dialog.png
log "Screenshot 2: Connection dialog"

# Now we need to fill the dialog
# Use Tab to navigate between fields
# The dialog has: Host, Port, Username, Password fields

# First clear any existing text and type Host
xdotool type --clearmodifiers "localhost"
sleep 0.3

# Tab to Port field
xdotool key Tab
sleep 0.2

# Clear default "22" and type port
xdotool key ctrl+a
xdotool type --clearmodifiers "22"
sleep 0.2

# Tab to Username
xdotool key Tab
sleep 0.2
xdotool type --clearmodifiers "root"
sleep 0.2

# Tab to Password
xdotool key Tab
sleep 0.2
xdotool type --clearmodifiers "picshell"
sleep 0.5

scrot /test_output/03_filled.png
log "Screenshot 3: Form filled"

# Find and click Connect button
# Use keyboard shortcut - Enter should work as Connect is the default button
xdotool key Return
sleep 6

scrot /test_output/04_connected.png
log "Screenshot 4: After connection"

# Check if we see the terminal prompt
# Type a command to verify connection
xdotool type --clearmodifiers "whoami"
sleep 0.3
xdotool key Return
sleep 1

scrot /test_output/05_whoami.png
log "Screenshot 5: whoami command"

# Now test image display
xdotool type --clearmodifiers "show_image /tmp/test.png"
sleep 0.3
xdotool key Return
sleep 5

scrot /test_output/06_image.png
log "Screenshot 6: Image display"

# Copy results
cp /test_output/*.png /output/

log "Test complete! Screenshots saved to /output/"
