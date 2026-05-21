# Apple Watch Battery Monitor (macOS)

This repo reads Apple Watch battery level from a paired iPhone over macOS using `libimobiledevice` + companion proxy, then can run as a background **LaunchAgent** to notify you when:

- battery is low
- battery is draining unusually fast

## What you need

- macOS with Terminal access
- Xcode command line tools (`clang`)
- Homebrew packages for libimobiledevice
- A paired, trusted iPhone that can see its Apple Watch
- Optional but required for notifications monitor: `jq`

Install deps:

```bash
brew install libimobiledevice libimobiledevice-glue libplist libusbmuxd jq
```

## 60-second setup (copy/paste)

```bash
cd /path/to/bluetooth-battery
make build
./bin/watch_battery --watch-only --json
make monitor-install IPHONE_UDID=<IPHONE_UDID>
```

Tip: the third command will print your iPhone UDID if not provided. Copy it, then replace `<IPHONE_UDID>` in the fourth command.

## Quick start

1. Open Terminal and go to the repo:

```bash
cd /path/to/bluetooth-battery
```

2. Build the watcher binary:

```bash
make build
```

3. Check if your phone/watch is reachable:

```bash
./bin/watch_battery
```

You should see a device list.

4. Read only Watch entries in JSON:

```bash
./bin/watch_battery --watch-only --json <IPHONE_UDID>
```

To get UDID automatically from the connected phone, you can run `./bin/watch_battery --watch-only --json` and inspect output.

## Install automatic monitor

The monitor runs every 10 minutes by default and sends macOS notifications.

```bash
make monitor-install IPHONE_UDID=<IPHONE_UDID>
```

To run one check now:

```bash
make monitor-check IPHONE_UDID=<IPHONE_UDID>
```

### Tuning alert behavior

You can set these values at install time:

```bash
make monitor-install \
  IPHONE_UDID=<IPHONE_UDID> \
  WATCH_BATTERY_AGENT_INTERVAL_SECONDS=300 \
  WATCH_BATTERY_LOW_THRESHOLD=15 \
  WATCH_BATTERY_FAST_DROP_RATE_PER_HOUR=10 \
  WATCH_BATTERY_LOW_COOLDOWN_MINUTES=20 \
  WATCH_BATTERY_FAST_DROP_COOLDOWN_MINUTES=45
```

Meaning:

- `WATCH_BATTERY_AGENT_INTERVAL_SECONDS`: seconds between checks
- `WATCH_BATTERY_LOW_THRESHOLD`: alert when battery is at or below this %
- `WATCH_BATTERY_FAST_DROP_RATE_PER_HOUR`: %/hour drop threshold
- `WATCH_BATTERY_LOW_COOLDOWN_MINUTES`: minimum wait between low-battery alerts
- `WATCH_BATTERY_FAST_DROP_COOLDOWN_MINUTES`: minimum wait between fast-drain alerts

## Useful management commands

- Check monitor status:

```bash
launchctl print gui/$(id -u) | grep watch-battery-monitor
```

- Uninstall monitor:

```bash
make monitor-uninstall
```

- View logs:

```bash
ls -l ~/Library/Caches/watch-battery-monitor
tail -f ~/Library/Caches/watch-battery-monitor/monitor.log
tail -f ~/Library/Caches/watch-battery-monitor/monitor.err
```

## Uninstall / cleanup

```bash
make monitor-uninstall
rm -rf ~/Library/Caches/watch-battery-monitor
```

## Troubleshooting

- "No iPhone found": unlock phone + allow trust, keep Bluetooth/Wi-Fi on, and make sure it is paired.
- `watch-battery-monitor requires jq`: install it with `brew install jq`, then reinstall the LaunchAgent.
- `watch_battery` cannot connect: ensure phone is on same network (if using Wi‑Fi pairing) and paired trust remains active.
- No watch appears: confirm the Watch is paired with that phone and has battery data available in iPhone settings.
- Monitor not triggering: verify `~/Library/LaunchAgents/com.bluetoothembedded.watch-battery-monitor.plist` exists and contains the correct UDID.
