# Apple Watch Battery Level via Mac — Research Notes

## Target Device
- **Name**: `<APPLE_WATCH_NAME>`
- **Model**: Apple Watch Series 10 (`Watch7,11`, hardware `N218bAP`)
- **UDID**: `<WATCH_UDID>`
- **CoreDevice ID**: `<WATCH_COREDEVICE_ID>`
- **Bluetooth MAC**: `<WATCH_BT_MAC>`
- **Serial**: `<WATCH_SERIAL>`
- **OS**: watchOS 11.3.1 (22S560)
- **Known battery level (from AirBuddy)**: 36%

## Companion iPhone
- **UDID**: `<IPHONE_UDID>`
- **CoreDevice ID**: `<IPHONE_COREDEVICE_ID>`
- **Model**: iPhone 12 Pro (`iPhone13,3`)
- **OS**: iOS 18.7.2
- **Battery**: 13% (confirmed via `com.apple.mobile.battery` lockdown domain)
- **WiFi address**: `iphone.local` / `<IPHONE_IPV6_LL>`
- **usbmuxd accessible**: Yes (WiFi pairing active)

---

## Methods Tried & Results

### 1. Direct BLE — Battery Service (UUID `180F` / characteristic `2A19`)
**Result**: ❌ Not available  
Apple Watch does not expose the standard BLE Battery Service to non-Apple devices.

### 2. BLE Manufacturer Advertisement Data
**Result**: ❌ No battery in ads  
Watch broadcasts: `4C 00 10 05 24 98 08 9B A0`  
= Apple company ID (`4C 00`) + Nearby Info type (`10`) + length (`05`) + 5 status bytes.  
Nearby Info (0x10) contains device activity state flags — no battery level. Battery advertising is an AirPods (Proximity Pairing `0x07`) feature only.

### 3. IOKit HID — `AppleDeviceManagementHIDEventService`
**Result**: ❌ Watch not present (Magic Trackpad found at `BatteryPercent = 23`)  
Works only for HID-connected accessories. Apple Watch does not register as a macOS HID device.

### 4. `IOBluetoothDevice` → `classicPeer` → `CBClassicPeer.batteryPercentSingle`
**Result**: ❌ Returns 0, `isReportingBatteryPercent = false`  
The Watch appears as a `CBClassicPeer` but in "Unpaired" / "disconnected" state.  
Battery reporting via `CBClassicPeer` requires "Magic Pairing" (Auto Unlock pairing), which this Watch has not done with this Mac.  
**Used by**: AirBuddy's `BluetoothClassicService.xpc` for AirPods — NOT for Watch.

### 5. Proprietary GATT Services (BLE connected)
Watch exposes three BLE services:
- `180A` — Device Information (manufacturer, model — readable but no battery)
- `D0611E78-BBB4-4591-A5F8-487910AE4366` — Apple Continuity Service
- `9FA480E0-4967-4542-9390-D343DC5D04AE` — Apple proprietary  

Characteristic `AF0BADB1-5B99-43CD-917A-A77BC549E3CC` (props: Write + Notify) — subscribed + sent probe write, no notification response. Requires knowledge of Apple's proprietary command format.

### 6. Find My iCloud Data (`findmylocateagent` SQLite databases)
**Result**: ❌ Encrypted  
Files at `~/Library/Group Containers/group.com.apple.findmy.findmylocateagent/Library/Application Support/` are binary plist with encrypted payload (`signature` + `encryptedData`).  
Find My app shows Watch battery icon (low, ~10-15%) but data is iCloud-encrypted.

### 7. MobileDevice Framework — iPhone lockdown (usbmuxd WiFi)
**Result**: ✅ iPhone battery works, ❌ Watch via this path fails  
```
AMDeviceNotificationSubscribe → iPhone connects → com.apple.mobile.battery → 13%  ✅
AMDeviceCopyPairedWatch(iphone) → nil  ❌
AMDeviceCopyPairedCompanion(iphone) → nil  ❌
```
`AMDeviceCopyPairedWatch` returns nil. Likely requires Watch to be separately accessible via usbmuxd (it's not — not visible in `_apple-mobdev2._tcp` mDNS).

### 8. iPhone lockdown domain sweep
Tried domains: `com.apple.iosd.companion`, `com.apple.PairRecords`, `com.apple.mobile.data_sync`, `com.apple.mobile.wireless_lockdown`  
None returned Watch battery or companion address data.

### 9. `com.apple.mobile.ldwatch` service on iPhone
**Result**: ❌ Error `0xE8000022` ("service not found" / not authorized)  
This is the iPhone-side lockdown tunnel to Apple Watch. Both `AMDeviceStartService` and `AMDeviceSecureStartService` fail.  
**This IS the correct mechanism** — used by AirBuddy's `MobileDevicesService.xpc` — but appears to require additional authorization or Watch being connected in a specific state.

### 10. CoreDevice / `devicectl`
**Result**: ❌ Connection timeout  
Watch shows `state: unavailable` and `pairingState: paired` in CoreDevice DB at:  
`~/Library/Containers/com.apple.CoreDevice.CoreDeviceService/Data/Library/Developer/CoreDevice/Devices/db.sqlite`  
`devicectl device info lockState` times out with error 4000.

### 11. mDNS / Bonjour
Watch appears on network as:
```
_remotepairing._tcp: <WATCH_REMOTEPAIRING_ID>
  → iPhone.local.:49152 (iPhone proxies Watch connection)
  authTag=<AUTH_TAG> ver=24 minVer=8
```
Watch is NOT in `_apple-mobdev2._tcp` (old usbmuxd protocol). Watch is NOT in `_companion-link._tcp`.

---

## How AirBuddy Gets Watch Battery (Reverse Engineered)

AirBuddy's `MobileDevicesService.xpc` uses:
- `/Library/Apple/System/Library/PrivateFrameworks/RemotePairing.framework/`
- `/Library/Apple/System/Library/PrivateFrameworks/DeviceInterface.framework/`
- `/Library/Apple/System/Library/PrivateFrameworks/MobileDevice.framework/`

Active connections (from `lsof`):
- `iphone.local:62078` — standard lockdown/usbmuxd connection (for iPhone battery, finding Watch)
- `iphone.local:60423` — likely RemotePairing tunnel to Watch through iPhone proxy

The Watch battery is obtained via:
1. Connect to iPhone via usbmuxd (port 62078)
2. Use `RemotePairing.framework` to start a tunnel to the Watch through `iPhone.local:49152` (the Watch's `_remotepairing._tcp` service, proxied by iPhone)
3. Query `com.apple.mobile.battery` → `BatteryCurrentCapacity` on the Watch

The `RemotePairing.framework` handles the authentication/TLS required to connect through the iPhone proxy to the Watch using the CoreDevice protocol (ver=24).

---

## Most Promising Next Steps

1. **Use `RemotePairing.framework` directly** — write a Swift/ObjC program using `RemotePairingConnection` or equivalent class to connect to the Watch via the iPhone proxy at `iPhone.local:49152` and query its lockdown battery service. This is what AirBuddy does.

2. **Investigate `com.apple.mobile.ldwatch` failure** — understand why error `0xE8000022` fires. This might require the Watch to be in an active/awake state, or require a specific pairing record. Try when Watch is actively unlocked.

3. **IOPowerSources extended** — the `AccessoryPowerSourcesProvider` in AirBuddy fetches 1 power source. Check if IOKit has a separate accessor for BT accessory batteries beyond `IOPSCopyPowerSourcesInfo`.

---

## Quick Reference — Working Commands

```bash
# iPhone battery (via MobileDevice framework):
# See /tmp/mobiledevice_all binary — connects via usbmuxd WiFi

# Find Watch on network:
dns-sd -B _remotepairing._tcp local.
# Resolves to: iPhone.local.:49152 (Watch proxied through iPhone)

# CoreDevice info:
devicectl list devices
# Shows: <APPLE_WATCH_NAME>, <WATCH_COREDEVICE_ID>, available (paired)

# Watch in Bluetooth:
blueutil --info <watch-bt-mac>
system_profiler SPBluetoothDataType | grep -A10 "Apple Watch"
```

## 2026-05-20 Follow-up: companion_proxy success path (post-comptest)

### Key discovery
- `comptest` from Setapp’s Bundled libimobiledevice helper is successful at resolving Watch battery:
  - `comptest` binary path: `/Applications/Setapp/Batteries.app/Contents/Library/LoginItems/io.fadel.Batteries-setapp.Helper.app/Contents/Resources/libimobiledevice/bin/comptest`
- Confirmed behavior by run + parse shows the watch battery now appears (e.g. 29% / 26% in captures).
- This validates that the required mechanism is Apple companion proxy over iPhone → Watch path, not classic BT battery service.

### libimobiledevice API shape that matters
- Public API used:
  - `companion_proxy_client_start_service()`
  - `companion_proxy_get_device_registry()`
  - `companion_proxy_get_value_from_registry()`
- `GetDeviceRegistry` response contains `PairedDevicesArray` (UDID array).
- `GetValueFromRegistry` response contains `RetrievedValueDictionary`; the requested key must be read from that dictionary, not directly as the plist root.
- This is the core parser bug that caused earlier `ProductType` misses.

### What works in practice
For each UDID from registry:
1) query `ProductType` (fallback `ProductTypeString`)
2) query `DeviceName`
3) query `BatteryCurrentCapacity` (fallback `CurrentCapacity`)
4) query `BatteryIsCharging`

Expected output format now achieved:
- `<APPLE_WATCH_NAME>: Watch7,11 (<WATCH_UDID>) — 26%`

### Why the earlier paths were dead ends
- Direct Apple MobileDevice/`com.apple.mobile.ldwatch` calls returned `0xE8000022` in this environment.
- iOS/IOKit/BLE-based routes either had no Watch visibility or returned non-watch accessory battery semantics.
- Initial `companion_proxy_get_value_from_registry` handling misread returned structure and dropped real values.

### `watch_battery` implementation outcome
- Added/confirmed companion proxy-first flow (no lockdownd explicit handshake required by our working path).
- Added robust nested registry-key extraction.
- Added JSON output and `--watch-only` filtering mode for automation tooling.
- Current confidence: this now matches the `comptest` mechanism closely enough to be reliable on the current environment.
