#!/usr/bin/env bash

# Thresholds
CPU_THRESHOLD=0.10
IDLE_LIMIT=600 # 1 minutes in seconds
IDLE_FILE="/run/vm_idle_time"

# Get current 1-minute CPU load
CPU_LOAD=$(awk '{print $2}' /proc/loadavg)

# This counts any active bash/sh shells, ssh sessions, or pts allocations.
# We expect at least 1-2 processes to always be active while you are connected.
ACTIVE_SESSIONS=$(ps aux | grep -v grep | grep -c -E "sshd|pts/|/bin/bash|/bin/sh|gcloud")

# Evaluate if system is mathematically idle
IS_IDLE=$(echo "$CPU_LOAD < $CPU_THRESHOLD" | bc -l)

# If CPU is low AND there are no active terminal/shell sessions
# Note: When you disconnect completely, ACTIVE_SESSIONS should drop to 0
if [ "$IS_IDLE" -eq 1 ] && [ "$ACTIVE_SESSIONS" -eq 0 ]; then
    if [ ! -f "$IDLE_FILE" ]; then
        echo 0 > "$IDLE_FILE"
    fi
    
    CURRENT_IDLE=$(cat "$IDLE_FILE")
    NEW_IDLE=$((CURRENT_IDLE + 60))
    echo "$NEW_IDLE" > "$IDLE_FILE"
    echo "System is idle. Counter incremented to: ${NEW_IDLE}s" 
    
    if [ "$NEW_IDLE" -ge "$IDLE_LIMIT" ]; then
        echo "VM idle limit reached. Shutting down."
        rm -f "$IDLE_FILE"
        echo "!!! SHUTDOWN TRIGGERED !!!"
        systemctl poweroff
    fi
else
    # Reset the timer because an interactive shell or high CPU load is detected
    echo "Activity detected! (CPU: $CPU_LOAD, Sessions: $ACTIVE_SESSIONS). Resetting idle timer to 0." # <-- Change this line!
    echo 0 > "$IDLE_FILE"
fi
