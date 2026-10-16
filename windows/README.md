# Rear Screen — Windows install guide

Mirror, record and take photos of your Xiaomi's **rear screen** (and front screen) on your PC, over USB or Wi-Fi.
A single `.exe`, with scrcpy and adb built in: nothing else to install.

- **Requires:** Windows 11 (Mica background on 22H2 or newer) or Windows 10, 64-bit (x64; ARM PCs run it through emulation)
- **Phone:** Android with USB debugging (built for a Xiaomi 18 Pro Max)
- **Status:** version 1.0.0 was tested on a Windows PC and worked. The features added in 1.1.0 (languages, both screens) have so far been verified on macOS only — please report anything odd.

---

## Installation

### 1. Install the app
1. Unzip `RearScreen-Windows-x64-v<version>.zip` anywhere (for example `C:\Tools\RearScreen`).
2. Double-click **EcranArriere.exe**.
3. **First launch only:** Windows SmartScreen may say *"Windows protected your PC"* because the app is not code-signed.
   Click **More info** → **Run anyway**.
   Some antivirus tools may also flag it, since the `.exe` contains bundled tools; allow it if needed.
4. The first launch takes a few seconds: scrcpy and adb (about 26 MB) are unpacked to `%LOCALAPPDATA%\EcranArriere`.

### 2. Prepare the phone (once)
1. *Settings → About phone* → tap **OS version** (or *HyperOS/MIUI version*) **7 times** to unlock Developer options.
2. *Settings → Additional settings → Developer options* → turn on **USB debugging**.
   (Optional: also turn on *USB debugging (Security settings)* if you want to control the phone with the mouse.)
3. Plug the phone into the PC with a data-capable USB cable and choose **File transfer** as the USB mode.
4. On the phone, accept **Allow USB debugging?** and tick **Always allow from this computer**.
5. If the app says *No phone detected*, install the phone's USB driver: **Xiaomi USB Driver** (or the **Google USB Driver**) — then unplug and replug the phone.

### 3. Use it
Open the app. The phone's name appears in the *Phone* menu and the status reads **Phone connected ✓**.

| Control | What it does |
|---|---|
| **Screen** menu | Front screen, rear screen, or **both screens** (default: rear) |
| **Quality** menu | Light (4 Mb/s · 30 fps), Normal (8 Mb/s · 60 fps), Max (20 Mb/s · 120 fps) |
| **Live mirror** | Opens a live window of the selected screen(s) |
| **Record** | Records to MP4, with or without the live window |
| **Photo** | Saves a PNG of the selected screen(s) |
| **Switch to Wi-Fi** | With the phone plugged in, enables wireless mode — then unplug (phone and PC on the same network) |
| **Manual connection…** | Pair and connect over Wireless debugging (address + pairing code) |
| Language menu (top right) | Français, English, Deutsch, Español, Italiano, Português |

Files are saved in **`Videos\EcranArriere`**, named `ecran_<screen>_<date>_<time>` (`avant` = front, `arriere` = rear, `principal` = single-screen phones).

### Showing both screens
Choose **Both screens** in the *Screen* menu. Two windows open side by side, about 2.5 seconds apart. Recording produces two separate MP4 files.

---

## Troubleshooting

| Message | What to do |
|---|---|
| *No phone detected* | Check the cable (must carry data), set USB mode to **File transfer**, install the USB driver (step 2.5), make sure USB debugging is on, then press **↻**. |
| *Phone not authorized* | Unlock the phone and accept the USB debugging prompt (tick **Always allow**). |
| *Phone offline* | Unplug and replug the cable, or switch USB debugging off and on. |
| Black video | The screen being captured is off — wake it up (the rear screen must be on). |
| Recording file is unreadable | Stop with the **Stop** button or by closing the mirror window, not by killing the app from Task Manager. |
| App will not start | Make sure the zip was fully extracted (do not run the `.exe` from inside the zip). |

## Uninstall
Delete `EcranArriere.exe`. To remove everything it created:
- the folder `%LOCALAPPDATA%\EcranArriere` (bundled tools);
- the registry key `HKEY_CURRENT_USER\Software\EcranArriere` (language choice);
- your recordings, if you no longer want them: `Videos\EcranArriere`.

## Known limitations
- 64-bit only.
- No audio is captured.
- When recording both screens, the second video starts about 2.5 s after the first.
- The app is not code-signed (hence the SmartScreen step above).
- The 1.1.0 additions (languages, both screens) are not yet validated on Windows hardware.
