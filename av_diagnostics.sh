#!/bin/bash
# =============================================================================
# AV Diagnostics Logger — Shawn's OBS + Loopback + Teams Chain
# =============================================================================
# Run this BEFORE starting your AV chain (OBS, Loopback, Teams).
# It captures USB topology, CoreAudio events, system resource usage,
# and provides an issue marker you can trigger with a keystroke.
#
# Usage:
#   chmod +x av_diagnostics.sh
#   ./av_diagnostics.sh
#
# To stop logging:
#   Press Ctrl+C in this terminal window, or run: ./av_diagnostics.sh stop
#
# Logs are saved to: ~/Desktop/AV_Diagnostics/<timestamp>/
# =============================================================================

# --- Setup ---
TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')
LOG_DIR="$HOME/Desktop/AV_Diagnostics/$TIMESTAMP"
mkdir -p "$LOG_DIR"

# Trap Ctrl+C to clean up background processes
cleanup() {
    echo ""
    echo "============================================"
    echo "Stopping all diagnostic processes..."
    echo "============================================"
    
    # Kill all background jobs
    if [ -f "$LOG_DIR/.pids" ]; then
        while read pid; do
            kill "$pid" 2>/dev/null
        done < "$LOG_DIR/.pids"
        rm "$LOG_DIR/.pids"
    fi
    
    # Kill any remaining child processes
    jobs -p | xargs -r kill 2>/dev/null
    
    echo ""
    echo "Logs saved to: $LOG_DIR"
    echo ""
    echo "Files captured:"
    ls -lh "$LOG_DIR"/ 2>/dev/null
    echo ""
    echo "============================================"
    echo "Next steps:"
    echo "  1. Note any issue times from issue_markers.txt"
    echo "  2. Cross-reference timestamps across log files"
    echo "  3. Check usb_topology_snapshots.txt for device drops"
    echo "  4. Search coreaudio_events.txt around issue times"
    echo "  5. Review system_resources.txt for CPU/memory spikes"
    echo "============================================"
    exit 0
}

trap cleanup SIGINT SIGTERM

# Handle 'stop' argument to kill a running instance
if [ "$1" = "stop" ]; then
    echo "Stopping running diagnostics..."
    pkill -f "av_diagnostics.sh" 2>/dev/null
    pkill -f "av_diag_marker" 2>/dev/null
    echo "Done."
    exit 0
fi

# =============================================================================
# 1. SNAPSHOT: System & USB Topology at Start
# =============================================================================
echo "Capturing initial system state..."

{
    echo "=== SYSTEM INFO ==="
    echo "Date: $(date)"
    echo "macOS: $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
    echo "Uptime: $(uptime)"
    echo ""
    
    echo "=== OBS VERSION ==="
    if [ -d "/Applications/OBS.app" ]; then
        defaults read /Applications/OBS.app/Contents/Info.plist CFBundleShortVersionString 2>/dev/null || echo "Could not read OBS version"
    else
        echo "OBS not found in /Applications"
    fi
    echo ""
    
    echo "=== LOOPBACK VERSION ==="
    if [ -d "/Applications/Loopback.app" ]; then
        defaults read /Applications/Loopback.app/Contents/Info.plist CFBundleShortVersionString 2>/dev/null || echo "Could not read Loopback version"
    else
        echo "Loopback not found in /Applications"
    fi
    echo ""
    
    echo "=== CAMERA HUB VERSION ==="
    CAMHUB_PATH=$(find /Applications -maxdepth 2 -name "Camera Hub*" -type d 2>/dev/null | head -1)
    if [ -n "$CAMHUB_PATH" ]; then
        defaults read "$CAMHUB_PATH/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "Could not read Camera Hub version"
    else
        echo "Camera Hub not found in /Applications"
    fi
    echo ""
    
    echo "=== MICROSOFT TEAMS VERSION ==="
    TEAMS_PATH=$(find /Applications -maxdepth 2 -name "Microsoft Teams*" -type d 2>/dev/null | head -1)
    if [ -n "$TEAMS_PATH" ]; then
        defaults read "$TEAMS_PATH/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "Could not read Teams version"
    else
        echo "Teams not found in /Applications"
    fi
    echo ""
    
    echo "=== THUNDERBOLT/USB TOPOLOGY ==="
    system_profiler SPThunderboltDataType SPUSBDataType 2>/dev/null
    echo ""
    
    echo "=== USB DEVICE TREE (IOREG) ==="
    ioreg -p IOUSB -w 0 | grep -E "@|\"USB|\"name\""
    echo ""
    
    echo "=== AUDIO DEVICES ==="
    system_profiler SPAudioDataType 2>/dev/null
    echo ""
    
} > "$LOG_DIR/00_initial_snapshot.txt" 2>&1

echo "  -> Saved to 00_initial_snapshot.txt"


# =============================================================================
# 2. CONTINUOUS: USB Topology Polling (every 30 seconds)
# =============================================================================
echo "Starting USB topology polling (every 30s)..."

(
    while true; do
        {
            echo "=== USB SNAPSHOT: $(date '+%Y-%m-%d %H:%M:%S') ==="
            ioreg -p IOUSB -w 0 | grep -E "@|\"USB|\"name\""
            echo ""
        } >> "$LOG_DIR/usb_topology_snapshots.txt" 2>&1
        sleep 30
    done
) &
echo $! >> "$LOG_DIR/.pids"


# =============================================================================
# 3. CONTINUOUS: CoreAudio Event Stream
# =============================================================================
echo "Starting CoreAudio event logging..."

log stream \
    --predicate 'subsystem == "com.apple.coreaudio" OR eventMessage CONTAINS "audio" OR eventMessage CONTAINS "sample rate"' \
    --level debug \
    >> "$LOG_DIR/coreaudio_events.txt" 2>&1 &
echo $! >> "$LOG_DIR/.pids"


# =============================================================================
# 4. CONTINUOUS: USB/Elgato/MOTU System Log Events
# =============================================================================
echo "Starting USB and device event logging..."

log stream \
    --predicate 'eventMessage CONTAINS[c] "elgato" OR eventMessage CONTAINS[c] "facecam" OR eventMessage CONTAINS[c] "MOTU" OR eventMessage CONTAINS[c] "USB" OR eventMessage CONTAINS[c] "camera" OR eventMessage CONTAINS[c] "Rogue Amoeba" OR eventMessage CONTAINS[c] "ACE" OR eventMessage CONTAINS[c] "Loopback"' \
    --level info \
    >> "$LOG_DIR/device_events.txt" 2>&1 &
echo $! >> "$LOG_DIR/.pids"


# =============================================================================
# 5. CONTINUOUS: System Resource Monitoring (every 15 seconds)
# =============================================================================
echo "Starting system resource monitoring (every 15s)..."

(
    while true; do
        {
            echo "=== RESOURCES: $(date '+%Y-%m-%d %H:%M:%S') ==="
            
            # CPU and memory for key processes
            echo "--- Key Processes ---"
            ps aux | head -1
            ps aux | grep -iE "obs|teams|loopback|camera.hub|stream.deck" | grep -v grep
            
            # Overall system load
            echo ""
            echo "--- System Load ---"
            echo "Load averages: $(sysctl -n vm.loadavg 2>/dev/null)"
            
            # Memory pressure
            echo "Memory pressure: $(memory_pressure 2>/dev/null | tail -1)"
            
            # Thermal state
            echo "Thermal state: $(pmset -g thermlog 2>/dev/null | tail -3)"
            
            echo ""
        } >> "$LOG_DIR/system_resources.txt" 2>&1
        sleep 15
    done
) &
echo $! >> "$LOG_DIR/.pids"


# =============================================================================
# 6. CONTINUOUS: OBS Log Watcher
# =============================================================================
OBS_LOG_DIR="$HOME/Library/Application Support/obs-studio/logs"
if [ -d "$OBS_LOG_DIR" ]; then
    echo "Starting OBS log watcher..."
    (
        # Watch for new log files and tail them
        LAST_LOG=""
        while true; do
            CURRENT_LOG=$(ls -t "$OBS_LOG_DIR"/*.txt 2>/dev/null | head -1)
            if [ -n "$CURRENT_LOG" ] && [ "$CURRENT_LOG" != "$LAST_LOG" ]; then
                LAST_LOG="$CURRENT_LOG"
                echo "=== NEW OBS LOG: $(basename "$CURRENT_LOG") at $(date '+%Y-%m-%d %H:%M:%S') ===" >> "$LOG_DIR/obs_log_mirror.txt"
                # Copy current content and continue tailing
                tail -f "$CURRENT_LOG" >> "$LOG_DIR/obs_log_mirror.txt" 2>&1 &
                echo $! >> "$LOG_DIR/.pids"
            fi
            sleep 10
        done
    ) &
    echo $! >> "$LOG_DIR/.pids"
else
    echo "  -> OBS log directory not found (OBS may not be installed or hasn't run yet)"
fi


# =============================================================================
# 7. CONTINUOUS: Teams Media Stack Log Watcher
# =============================================================================
TEAMS_LOG_DIR="$HOME/Library/Group Containers/UBF8T346G9.com.microsoft.teams/logs"
if [ -d "$TEAMS_LOG_DIR" ]; then
    echo "Starting Teams log watcher..."
    (
        LAST_MEDIA_LOG=""
        while true; do
            CURRENT_MEDIA_LOG=$(find "$TEAMS_LOG_DIR" -name "*media*" -type f 2>/dev/null | sort -t/ -k$(echo "$TEAMS_LOG_DIR" | tr -cd '/' | wc -c) | tail -1)
            if [ -n "$CURRENT_MEDIA_LOG" ] && [ "$CURRENT_MEDIA_LOG" != "$LAST_MEDIA_LOG" ]; then
                LAST_MEDIA_LOG="$CURRENT_MEDIA_LOG"
                echo "=== TEAMS MEDIA LOG: $(basename "$CURRENT_MEDIA_LOG") at $(date '+%Y-%m-%d %H:%M:%S') ===" >> "$LOG_DIR/teams_media_log.txt"
                tail -f "$CURRENT_MEDIA_LOG" >> "$LOG_DIR/teams_media_log.txt" 2>&1 &
                echo $! >> "$LOG_DIR/.pids"
            fi
            sleep 10
        done
    ) &
    echo $! >> "$LOG_DIR/.pids"
else
    echo "  -> Teams log directory not found (checking alternative locations...)"
    # New Teams might use a different path
    ALT_TEAMS_DIR="$HOME/Library/Containers/com.microsoft.teams2/Data/Library/Logs"
    if [ -d "$ALT_TEAMS_DIR" ]; then
        echo "  -> Found Teams logs at alternative path"
        (
            while true; do
                CURRENT_LOG=$(find "$ALT_TEAMS_DIR" -name "*media*" -o -name "*call*" 2>/dev/null | sort | tail -1)
                if [ -n "$CURRENT_LOG" ]; then
                    tail -f "$CURRENT_LOG" >> "$LOG_DIR/teams_media_log.txt" 2>&1 &
                    echo $! >> "$LOG_DIR/.pids"
                    break
                fi
                sleep 10
            done
        ) &
        echo $! >> "$LOG_DIR/.pids"
    else
        echo "  -> Teams logs not found at any known location"
    fi
fi


# =============================================================================
# 8. READY: Issue Marker (Interactive)
# =============================================================================
echo ""
echo "============================================"
echo "  AV DIAGNOSTICS RUNNING"
echo "============================================"
echo ""
echo "  Log directory: $LOG_DIR"
echo ""
echo "  Active monitors:"
echo "    - USB topology (every 30s)"
echo "    - CoreAudio events (live stream)"
echo "    - USB/Elgato/MOTU device events (live stream)"
echo "    - System resources (every 15s)"
echo "    - OBS logs (mirrored)"
echo "    - Teams media logs (mirrored)"
echo ""
echo "============================================"
echo "  HOW TO USE"
echo "============================================"
echo ""
echo "  1. Start your AV chain: OBS -> Loopback -> Teams"
echo "  2. When you see an issue, come back to this"
echo "     terminal and press ENTER to mark it"
echo "  3. When done, press Ctrl+C to stop logging"
echo ""
echo "============================================"
echo "  Press ENTER each time you notice an issue"
echo "============================================"
echo ""

# Issue marker loop
ISSUE_COUNT=0
while true; do
    read -r -p ""
    ISSUE_COUNT=$((ISSUE_COUNT + 1))
    MARK_TIME=$(date '+%Y-%m-%d %H:%M:%S')
    echo ">>> ISSUE #$ISSUE_COUNT MARKED at $MARK_TIME" >> "$LOG_DIR/issue_markers.txt"
    
    # Also capture a USB snapshot at the moment of the issue
    {
        echo "=== ISSUE #$ISSUE_COUNT SNAPSHOT: $MARK_TIME ==="
        ioreg -p IOUSB -w 0 | grep -E "@|\"USB|\"name\""
        echo ""
        echo "--- Process State ---"
        ps aux | grep -iE "obs|teams|loopback|camera.hub" | grep -v grep
        echo ""
    } >> "$LOG_DIR/issue_snapshots.txt" 2>&1
    
    echo "  ✓ Issue #$ISSUE_COUNT marked at $MARK_TIME (snapshot captured)"
done