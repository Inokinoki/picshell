#!/bin/bash
export DISPLAY=:99

# Start Xvfb
Xvfb :99 -screen 0 1280x800x24 &
sleep 2

# Start SSH server
service ssh start

# Create a script that outputs iTerm2 image sequence
cat > /usr/local/bin/show_image << 'SCRIPT'
#!/bin/bash
FILE="$1"
if [ ! -f "$FILE" ]; then
    echo "File not found: $FILE"
    exit 1
fi
BASE64=$(base64 -w 0 "$FILE")
SIZE=$(wc -c < "$FILE")
printf "\033]1337;File=inline=1;size=%d:%s\a\n" "$SIZE" "$BASE64"
SCRIPT
chmod +x /usr/local/bin/show_image

# Start the app
/app/picshell &
APP_PID=$!
sleep 4

# Take initial screenshot
scrot /tmp/01_initial.png

# Click "New Connection" button
xdotool mousemove 640 450
sleep 0.5
xdotool click 1
sleep 2

# Take screenshot of connection dialog
scrot /tmp/02_connection_dialog.png

# Fill in Host field
xdotool mousemove 640 280
sleep 0.3
xdotool click 1
sleep 0.3
xdotool type --clearmodifiers "localhost"
sleep 0.3

# Tab to Port and clear
xdotool key Tab
sleep 0.2
xdotool key ctrl+a
xdotool type --clearmodifiers "22"

# Tab to Username
xdotool key Tab
sleep 0.2
xdotool type --clearmodifiers "root"

# Tab to Password
xdotool key Tab
sleep 0.2
xdotool type --clearmodifiers "picshell"

# Take screenshot with filled form
scrot /tmp/03_filled_form.png

# Click Connect button
xdotool mousemove 700 470
sleep 0.3
xdotool click 1
sleep 5

# Take screenshot after connection
scrot /tmp/04_connected.png

# Type command to display image
xdotool type --clearmodifiers "show_image /tmp/test.png"
sleep 0.5
xdotool key Return
sleep 4

# Take screenshot with image displayed
scrot /tmp/05_image_display.png

# Copy screenshots to output
cp /tmp/0*.png /output/

echo "Test complete! Screenshots saved."
