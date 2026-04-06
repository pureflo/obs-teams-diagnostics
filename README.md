# obs-teams-diagnostics

A macOS shell script that captures real-time audio/video diagnostic data for troubleshooting OBS Studio, Microsoft Teams and CoreAudio signal chain issues.

Built to diagnose intermittent audio glitches, video dropouts and device instability in complex AV setups involving USB audio interfaces, virtual audio routing (I used Loopback) and video conferencing.

## What it captures

Each run creates a timestamped session folder containing:

| File | Contents |
|---|---|
| `00_initial_snapshot.txt` | System info, macOS version, uptime, load averages, OBS/Loopback/Teams versions, Thunderbolt/USB topology, USB device tree (ioreg), audio device list |
| `coreaudio_events.txt` | Live CoreAudio subsystem events — AQMEIO timeouts, IO_Sender failures, HALC_ProxyIOContext overloads, AudioQueue errors, device initialisation, volume changes, voice isolation DSP state |
| `device_events.txt` | Kernel USB events, device connect/disconnect, power management, USB pipe aborts, network events |
| `obs_log_mirror.txt` | Real-time mirror of the active OBS log — profiler data, audio device init, buffering changes, scene switches, monitoring state |
| `system_resources.txt` | Process list for key audio/video processes, system load, memory pressure |
| `usb_topology_snapshots.txt` | Periodic USB topology snapshots to detect device disconnections or bus changes |

## Requirements

- macOS 13 (Ventura) or later
- OBS Studio 30+
- Terminal access (the script uses `log stream`, `system_profiler`, `ioreg`, and standard macOS CLI tools)

## Usage

```bash
chmod +x av_diagnostics.sh
./av_diagnostics.sh
```

The script creates a folder at `~/Desktop/AV_Diagnostics/YYYY-MM-DD_HH-MM-SS/` and begins capturing. Press `Ctrl+C` to stop the capture session.

## What to look for in the output

**AudioQueue timeouts (AQMEIO):** Search `coreaudio_events.txt` for `AQMEIO` with `timeout` or error code `-66681`. These indicate the audio monitoring device couldn't start playback in time — usually caused by USB bandwidth contention or CPU starvation.

**USB pipe aborts:** Search `device_events.txt` for `abortGated`. These are kernel-level USB disconnections on an audio interface, often caused by sharing a USB hub with high-bandwidth devices.

**IO overloads:** Search `coreaudio_events.txt` for `HALC_ProxyIOContext.*overload`. These show a CoreAudio client losing its real-time scheduling — check the `HostApplicationDisplayID` and `other_active_clients` fields to identify which processes are competing.

**Teams volume manipulation:** Search `coreaudio_events.txt` for `LogVolumeChange` with your virtual audio device UID. Excessive volume changes indicate Teams AGC is fighting with your audio routing.

**Voice Isolation CPU load:** Search for `AVAUVoiceIOChatFlavorVoiceIsolation`. If present and active, Teams is running neural voice processing that can starve other audio processes. Disable via Control Centre → Mic Mode → Standard.

**OBS device reinitialisation:** Search `obs_log_mirror.txt` for `Device '...' initialized` appearing multiple times. Repeated initialisations mean the audio device is dropping and reconnecting.

**Audio buffering increases:** Search `obs_log_mirror.txt` for `adding .* milliseconds of audio buffering`. Rising buffer values across a session indicate instability — OBS is adding padding to compensate for device timing issues.

## Tested with

- macOS 26.4 on Apple M2 MacBook Air
- OBS Studio 32.1.0
- Microsoft Teams 26072.605.4546.510
- Rogue Amoeba Loopback 2.4.8
- MOTU M2 USB audio interface
- Elgato Facecam Pro
- CalDigit Element Hub (Thunderbolt 4)

## Licence

MIT — see [LICENSE](LICENSE).
