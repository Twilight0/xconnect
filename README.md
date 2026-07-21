# xconnect

KDE Connect protocol implementation in Vala/C with a GTK3/XApp GUI.

Allows your Linux desktop to communicate with Android devices via the KDE Connect
protocol — notifications mirroring, file sharing, clipboard sync, remote input,
SMS, media control, and more.

No KDE dependencies required.

## Installation

### Arch Linux (PKGBUILD)

Build and install the package:

```bash
makepkg -si
```

### Building from source

#### Dependencies

**Arch Linux:**

```bash
sudo pacman -S vala meson ninja pkg-config glib2 json-glib libgee libnotify gtk3 libxtst at-spi2-core gnutls python python-gobject xapp
```

**Debian/Ubuntu:**

```bash
sudo apt install valac meson ninja-build pkg-config libglib2.0-dev libgee-0.8-dev \
  libjson-glib-dev libnotify-dev libgtk-3-dev libxtst-dev libatspi2.0-dev \
  libgnutls28-dev python3 python3-gi gir1.2-xapp-1.0
```

**Fedora:**

```bash
sudo dnf install vala meson ninja-build pkgconfig glib2-devel libgee-devel \
  json-glib-devel libnotify-devel gtk3-devel libXtst-devel at-spi2-core-devel \
  gnutls-devel python3 python3-gobject xapp
```

#### Build and install

```bash
meson setup build
ninja -C build
sudo ninja -C build install
```

To install to a custom prefix:

```bash
meson setup build --prefix=/usr --sysconfdir=/etc
ninja -C build
DESTDIR=/tmp/xconnect ninja -C build install
```

| Binary | Description |
|--------|-------------|
| `xconnect` | Daemon — handles protocol, discovery, device communication |
| `xconnectctl` | CLI client — list devices, share files, send SMS, pair devices |
| `xconnect-app` | GUI — system tray icon with device management window |

For a complete guide to all commands, options, and feature alignment between CLI and GUI, see [FEATURES.md](file:///home/twilight/Projects/xconnect/FEATURES.md).
For developer and AI agent workflow guidelines, command order, and build instructions, see [AGENTS.md](file:///home/twilight/Projects/xconnect/AGENTS.md).

## Daemon

### Starting

```bash
# Foreground (with debug output)
xconnect -d

# Background (silent)
xconnect
```

The daemon listens on UDP port 1716 for incoming device discovery and broadcasts
its identity to UDP port 1714 every 5 seconds so phones can find it.

### systemd user service

Enable auto-start on login:

```bash
systemctl --user enable xconnect
systemctl --user start xconnect
```

To keep the service running even when you're not logged in:

```bash
loginctl enable-linger $USER
```

Check status:

```bash
systemctl --user status xconnect
```

View logs:

```bash
journalctl --user -u xconnect -f
```

## GUI

Launch the graphical interface:

```bash
# Show window on start
xconnect-app

# Start hidden in system tray only
xconnect-app --hidden
```

The tray icon provides:
- **Left-click**: Toggle window visibility
- **Right-click**: Context menu (Open / Quit)

The window includes:
- Device sidebar with connection status and battery
- Device detail page with actions (Ping, Find, Share, SMS, Lock)
- Notification history from phone
- MPRIS media control
- Settings with inline config editor

## CLI client

```bash
# List devices
xconnectctl list-devices

# Show device details
xconnectctl show-device /org/xconnect/device/0

# Share file/URL/text
xconnectctl share-file /org/xconnect/device/0 /path/to/file
xconnectctl share-url /org/xconnect/device/0 https://example.com
xconnectctl share-text /org/xconnect/device/0 "Hello from desktop"

# Send SMS
xconnectctl send-sms /org/xconnect/device/0 "+1234567890" "Message text"

# Find device (make it ring)
xconnectctl find-device /org/xconnect/device/0

# Show battery
xconnectctl show-battery /org/xconnect/device/0
```

## Configuration

Manual configuration is not required — new devices are auto-allowed on first
discovery and saved to the config file automatically.

The config file is at `~/.config/xconnect/xconnect.conf`. You can edit it
via the GUI (Settings → Config Editor) or directly.

### Custom device addresses

To connect to a device by IP (e.g., on a different subnet), add it via
the GUI settings or add to the config:

```ini
[main]
custom_devices=192.168.2.100
```

## Firewall

The following ports must be open:

| Port | Protocol | Purpose |
|------|----------|---------|
| 1714 | UDP | Outgoing — broadcast identity to phones |
| 1716 | UDP | Incoming — receive discovery from phones |
| 1714 | TCP | Incoming — device connections |
| 9970-9975 | TCP | Incoming — file transfers |

**ufw:**

```bash
sudo ufw allow 1714:1716/udp
sudo ufw allow 1714:1716/tcp
```

**firewalld:**

```bash
sudo cp extra/firewalld/xconnect.xml /etc/firewalld/services/
sudo firewall-cmd --permanent --add-service=xconnect
sudo firewall-cmd --reload
```

## License

GPL-2.0
