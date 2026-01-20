#!/bin/bash

# Build the app
echo "Building app..."
swift build || { echo "Build failed"; exit 1; }

# Get the full path to the built executable
EXECUTABLE_PATH=$(pwd)/.build/debug/am-i-talking-too-much-app

# Launch the app explicitly in foreground mode
echo "Launching app..."
open -F "$EXECUTABLE_PATH"

echo "Launch command executed. If you don't see the app window, look for it in your dock or application switcher." 