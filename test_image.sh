#!/bin/bash
set -e
export DISPLAY=:99

log() { echo "[TEST] $1"; }

# Start Xvfb
log "Starting Xvfb..."
Xvfb :99 -screen 0 1280x800x24 &
sleep 2

# Start SSH server
log "Starting SSH server..."
service ssh start

# Start the app
log "Starting Picshell..."
/app/build/linux/arm64/release/bundle/picshell &
APP_PID=$!
sleep 5

# Take initial screenshot
scrot /test_output/01_initial.png
log "Screenshot 1: Initial"

# Click New Connection button
log "Opening connection dialog..."
xdotool mousemove 640 470
sleep 0.3
xdotool click 1
sleep 2

scrot /test_output/02_dialog.png
log "Screenshot 2: Dialog"

# Fill form
log "Filling form..."
xdotool mousemove 640 290 && sleep 0.2 && xdotool click 1 && sleep 0.3 && xdotool type --clearmodifiers "localhost"
xdotool mousemove 640 330 && sleep 0.2 && xdotool click 1 && sleep 0.3 && xdotool key ctrl+a && xdotool type --clearmodifiers "22"
xdotool mousemove 640 370 && sleep 0.2 && xdotool click 1 && sleep 0.3 && xdotool type --clearmodifiers "root"
xdotool mousemove 640 410 && sleep 0.2 && xdotool click 1 && sleep 0.3 && xdotool type --clearmodifiers "picshell"
sleep 0.5

scrot /test_output/03_filled.png
log "Screenshot 3: Filled"

# Click Connect button (y=430)
log "Connecting..."
xdotool mousemove 640 430
sleep 0.3
xdotool click 1
sleep 8

scrot /test_output/04_connected.png
log "Screenshot 4: Connected"

# Run test_image command
log "Testing image display..."
xdotool type --clearmodifiers "test_image"
sleep 0.3
xdotool key Return
sleep 5

scrot /test_output/05_image.png
log "Screenshot 5: Image display"

# Copy results
cp /test_output/*.png /output/
log "Test complete! Screenshots saved to /output/"
