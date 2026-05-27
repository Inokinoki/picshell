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

# Create a script that outputs iTerm2 image sequence
cat > /usr/local/bin/test_image << 'EOF'
#!/bin/bash
python3 -c "
import base64
# Minimal 1x1 red pixel PNG
png = bytes([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53,
    0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41,
    0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
    0x00, 0x00, 0x02, 0x00, 0x01, 0xE2, 0x21, 0xBC,
    0x33, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E,
    0x44, 0xAE, 0x42, 0x60, 0x82
])
b64 = base64.b64encode(png).decode()
print(f'\033]1337;File=inline=1;size={len(png)}:{b64}\a')
echo 'Image displayed!'
"
EOF
chmod +x /usr/local/bin/test_image

# Start the app
log "Starting Picshell..."
/app/picshell &
APP_PID=$!
sleep 5

# Take initial screenshot
scrot /test_output/01_initial.png
log "Screenshot 1: Initial"

# Use Ctrl+N to open connection dialog (new keyboard shortcut)
log "Opening connection dialog with Ctrl+N..."
xdotool key ctrl+n
sleep 2

scrot /test_output/02_dialog.png
log "Screenshot 2: Dialog"

# Fill form using Tab
xdotool type --clearmodifiers "localhost"
sleep 0.3
xdotool key Tab
sleep 0.2
xdotool key ctrl+a
xdotool type --clearmodifiers "22"
sleep 0.2
xdotool key Tab
sleep 0.2
xdotool type --clearmodifiers "root"
sleep 0.2
xdotool key Tab
sleep 0.2
xdotool type --clearmodifiers "picshell"
sleep 0.5

scrot /test_output/03_filled.png
log "Screenshot 3: Filled"

# Click Connect (Enter key)
xdotool key Return
sleep 6

scrot /test_output/04_connected.png
log "Screenshot 4: Connected"

# Run test_image command
xdotool type --clearmodifiers "test_image"
sleep 0.3
xdotool key Return
sleep 4

scrot /test_output/05_image.png
log "Screenshot 5: Image display"

# Copy results
cp /test_output/*.png /output/
log "Test complete! Screenshots saved to /output/"
