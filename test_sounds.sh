#!/bin/bash
echo "Testing different notification sounds..."

# Available sounds from /System/Library/Sounds/:
# Basso.aiff, Blow.aiff, Bottle.aiff, Frog.aiff, Funk.aiff
# Glass.aiff, Hero.aiff, Morse.aiff, Ping.aiff, Pop.aiff
# Purr.aiff, Sosumi.aiff, Submarine.aiff, Tink.aiff

BIN_PATH="$HOME/Applications/ClaudeMonitor.app/Contents/MacOS/ClaudeMonitor"

# Test all available sounds
echo "Testing Hero sound..."
"$BIN_PATH" notify "Hero Sound Test" "Testing Hero sound" "Hero"
sleep 2

echo "Testing Glass sound..."
"$BIN_PATH" notify "Glass Sound Test" "Testing Glass sound" "Glass"
sleep 2

echo "Testing Basso sound..."
"$BIN_PATH" notify "Basso Sound Test" "Testing Basso sound" "Basso"
sleep 2

echo "Testing Pop sound..."
"$BIN_PATH" notify "Pop Sound Test" "Testing Pop sound" "Pop"
sleep 2

echo "Testing notification without sound..."
"$BIN_PATH" notify "No Sound Test" "Testing notification without sound (silent)" ""
sleep 2

echo "All tests completed! Check the notification center."
