# xconnect Feature Reference & Alignment

This document outlines all features supported by **`xconnect`**, providing a detailed comparison between the **CLI client (`xconnectctl`)** and the **GTK GUI client (`xconnect-app`)**.

Both interfaces communicate directly with the core `xconnect` daemon over D-Bus (`org.xconnect`), ensuring **100% feature and architectural parity**.

---

## 1. Feature Parity Matrix

| Feature / Action | CLI (`xconnectctl`) | GUI (`xconnect-app`) | Protocol Capability |
|---|---|---|---|
| **Device Discovery** | `xconnectctl list-devices` | Left sidebar list | `kdeconnect.identity` (UDP/TCP) |
| **Device Information** | `xconnectctl show-device <path>` | Device details panel | Device specs & capability list |
| **Initiate Pairing** | `xconnectctl pair <path>` | **Pair** button | `kdeconnect.pair` (`pair: true`) |
| **Accept Pairing** | `xconnectctl accept <path>` | **Accept** dialog button | `kdeconnect.pair` (`pair: true`) |
| **Reject Pairing** | `xconnectctl reject <path>` | **Reject** dialog button | `kdeconnect.pair` (`pair: false`) |
| **Unpair / Forget** | `xconnectctl remove <path>` | **Unpair / Forget** button | `kdeconnect.pair` (`pair: false`) |
| **Verification Key** | Printed in CLI output | Displayed in dialog text | SHA-256 (Public DERs + Timestamp) |
| **Battery Monitoring** | `xconnectctl battery <path>` | Battery indicator & percentage | `kdeconnect.battery` |
| **Find My Phone** | `xconnectctl find <path>` | **Ring Phone** button | `kdeconnect.findmyphone.request` |
| **Share File** | `xconnectctl share-file <path> <file>` | **Send File...** picker | `kdeconnect.share.request` |
| **Share URL** | `xconnectctl share-url <path> <url>` | **Send Link / URL** entry | `kdeconnect.share.request` |
| **Share Text** | `xconnectctl share-text <path> <text>` | **Send Text** entry | `kdeconnect.share.request` |
| **Send SMS** | `xconnectctl send-sms <path> <num> <msg>` | SMS composer dialog | `kdeconnect.sms.request` |
| **Clipboard Sync** | Automatic / D-Bus | Automatic / Tray toggle | `kdeconnect.clipboard` |
| **Notification Mirroring** | Automatic | Notification history panel | `kdeconnect.notification` |
| **MPRIS Media Control** | Automatic / D-Bus | Media player widget | `kdeconnect.mpris` |
| **System Service Control** | `xconnectctl start-daemon`/`stop-daemon` | Automated service launch | systemd user service |

---

## 2. CLI Reference (`xconnectctl`)

`xconnectctl` provides full command-line control over all daemon functions. Every long-form command has a shorthand alias for convenience.

### Device & Pairing Management

* **`list-devices`** *(alias: `list`)*
  ```bash
  xconnectctl list
  ```
  Lists all discovered and paired devices, including object paths, names, types, connection status, and pairing status.

* **`show-device <path>`** *(alias: `show`)*
  ```bash
  xconnectctl show /org/xconnect/device/0
  ```
  Displays full technical details of the device (ID, Name, Type, Protocol Version, IP Address, Active/Connected state, incoming and outgoing capabilities).

* **`pair-device <path>`** *(alias: `pair`)*
  ```bash
  xconnectctl pair /org/xconnect/device/0
  ```
  Initiates a pairing request to the device and outputs the **8-character verification key** (e.g. `C87D75EE`).
  * *Behavior Note*: If the device is active, the request is sent immediately. If offline/connecting, the request is queued and sent as soon as the phone opens a TLS channel.

* **`accept-pair <path>`** *(alias: `accept`)*
  ```bash
  xconnectctl accept /org/xconnect/device/0
  ```
  Accepts an incoming pairing request initiated from a remote phone.

* **`reject-pair <path>`** *(alias: `reject`)*
  ```bash
  xconnectctl reject /org/xconnect/device/0
  ```
  Rejects an incoming pairing request.

* **`remove-device <path>`** *(alias: `remove`)*
  ```bash
  xconnectctl remove /org/xconnect/device/0
  ```
  Unpairs and removes the device from local configuration.

* **`allow-device <path>`** *(alias: `allow`)*
  ```bash
  xconnectctl allow /org/xconnect/device/0
  ```
  Marks a device as allowed to connect.

---

### Status & Telemetry

* **`show-battery <path>`** *(alias: `battery`)*
  ```bash
  xconnectctl battery /org/xconnect/device/0
  ```
  Displays battery percentage level and charging status (`Charging` or `Discharging`).

---

### Remote Actions & Content Sharing

* **`find-device <path>`** *(alias: `find`)*
  ```bash
  xconnectctl find /org/xconnect/device/0
  ```
  Triggers the **Find My Phone** alarm, causing the phone to ring loudly even if set to silent/vibrate.

* **`share-file <path> <filepath>`**
  ```bash
  xconnectctl share-file /org/xconnect/device/0 /home/user/Pictures/photo.jpg
  ```
  Transfers a local file to the phone over the secure file transfer socket.

* **`share-url <path> <url>`**
  ```bash
  xconnectctl share-url /org/xconnect/device/0 "https://example.com"
  ```
  Sends a web URL to the phone and opens it in the phone's default browser.

* **`share-text <path> <text>`**
  ```bash
  xconnectctl share-text /org/xconnect/device/0 "Hello from Linux terminal"
  ```
  Sends a text string snippet to the phone.

* **`send-sms <path> <phone_number> <message>`**
  ```bash
  xconnectctl send-sms /org/xconnect/device/0 "+1234567890" "Meeting at 5 PM"
  ```
  Sends an SMS text message using the mobile device's cellular connection.

---

### Service Control

* **`start-daemon`**
  ```bash
  xconnectctl start-daemon
  ```
  Starts the `xconnect` user systemd service.

* **`stop-daemon`**
  ```bash
  xconnectctl stop-daemon
  ```
  Stops the `xconnect` user systemd service.

---

## 3. GUI Reference (`xconnectapp`)

`xconnect-app` is a GTK3/XApp application featuring a desktop tray icon and main control window.

* **System Tray Icon**:
  * **Left-click**: Toggle main window visibility.
  * **Right-click**: Context menu with quick status, Open, and Quit.
* **Device Sidebar**: Live status indicator (Active, Inactive, Unpaired) and battery percentage widget for each discovered device.
* **Pairing Request Dialogs**:
  * Incoming pairing requests prompt a modal GTK dialog containing the 8-character **Verification Key** matching the code shown on the phone.
  * Provides **Accept** and **Reject** response buttons.
* **Actions Panel**:
  * Buttons for **Ring Phone**, **Send File**, **Send Link**, **Send Text**, and **Send SMS**.
* **Media & Notifications**:
  * Integrated MPRIS media playback control panel for controlling phone media players.
  * Notification stream viewer displaying mirrored phone notifications.

---

## 4. Pairing Protocol & Notification Behavior

### Two-Way Pairing Handshake

1. **PC -> Phone (`xconnectctl pair <path>`)**:
   - PC sends `kdeconnect.pair` over the active TLS connection.
   - Calculates and displays the 8-character verification key.
   - **Android Behavior**: The pairing prompt arrives in the Android **Notification Shade** (swipe down from top of screen). On Android/Samsung One UI, background service notifications do not pop up as full-screen overlays by default; pulling down the notification bar shows the **ACCEPT** / **REJECT** options along with the verification key.

2. **Phone -> PC**:
   - Tapping **REQUEST PAIRING** inside the KDE Connect app on the phone sends `kdeconnect.pair` to `xconnect`.
   - On the PC, a GTK modal prompt appears in `xconnect-app`, or can be accepted via terminal using `xconnectctl accept /org/xconnect/device/0`.
