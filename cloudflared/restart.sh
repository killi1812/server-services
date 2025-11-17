#!/bin/bash

PROCESS_NAME="cloudflared"
START_COMMAND="cloudflared tunnel --config $HOME/service/cloudflared/config.yml run pc-dev"
LOG_FILE="$HOME/service/cloudflared/log/cloudflared_restart.log"

echo "--- 1. Finding existing **$PROCESS_NAME** process PID ---"

OLD_PID=$(pgrep -x $PROCESS_NAME)

if [ -z "$OLD_PID" ]; then
    echo "No existing **$PROCESS_NAME** process found. Proceeding to start a new one."
else
    echo "Found old **$PROCESS_NAME** PID(s): **$OLD_PID**"
fi

echo "--- 2. Starting a new **$PROCESS_NAME** process ---"

nohup $START_COMMAND > $LOG_FILE 2>&1 &

# Wait briefly for the new process to start and stabilize
sleep 2

# Verify the new process is running and get its PID (optional, but good practice)
NEW_PID=$(pgrep -x $PROCESS_NAME | grep -v "$OLD_PID")
if [ -z "$NEW_PID" ]; then
    echo "Error: Failed to confirm the new **$PROCESS_NAME** process started."
    exit 1
else
    echo "New **$PROCESS_NAME** process started with PID: **$NEW_PID**"
fi

echo "--- Killing the old **$PROCESS_NAME** process ---"

if [ -n "$OLD_PID" ]; then
    echo "Killing old **$PROCESS_NAME** process(es) with PID(s): **$OLD_PID**"
    kill "$OLD_PID"
    
    # Wait for the process to terminate
    sleep 1
    
    if pgrep -x $PROCESS_NAME | grep -q "$OLD_PID"; then
        echo "Warning: Old process **$OLD_PID** did not terminate cleanly."
    else
        echo "Old process successfully terminated."
    fi
else
    echo "No old process found to kill."
fi

echo "--- Restart complete ---"
