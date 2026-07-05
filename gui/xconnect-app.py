#!/usr/bin/env python3
"""
xconnect-gui: Rich GTK3/XApp frontend for xconnect
Full-featured system tray + window application for KDE Connect protocol.
"""

import sys
import os
import signal
import subprocess
import time
from datetime import datetime

# Allow finding dbus_client when installed system-wide
_share_gui = "/usr/share/xconnect/gui"
if os.path.isdir(_share_gui) and _share_gui not in sys.path:
    sys.path.insert(0, _share_gui)

import gi
gi.require_version('Gtk', '3.0')
gi.require_version('XApp', '1.0')
gi.require_version('Gdk', '3.0')
gi.require_version('Notify', '0.7')
gi.require_version('GdkPixbuf', '2.0')
from gi.repository import Gtk, Gdk, XApp, GLib, Gio, GdkPixbuf, Notify, Pango

from dbus_client import MConnectDBus

APP_ID = "org.xconnect.gui"
APP_NAME = "xconnect"
APP_VERSION = "2.0"
SETTINGS_DIR = os.path.expanduser("~/.config/xconnect")
SETTINGS_FILE = os.path.join(SETTINGS_DIR, "gui.conf")
ICON_DIR = "/usr/share/xconnect/gui/icons"


class DeviceStore:
    """In-memory device state with live D-Bus updates."""

    def __init__(self, dbus):
        self.dbus = dbus
        self.devices = {}  # path -> {info dict}
        self._listeners = []

    def refresh(self):
        for path, info in self.dbus.get_devices():
            self.devices[path] = info

    def add(self, path, info):
        self.devices[path] = info
        self._notify("added", path)

    def remove(self, path):
        self.devices.pop(path, None)
        self._notify("removed", path)

    def update(self, path, key, value):
        if path in self.devices:
            self.devices[path][key] = value
            self._notify("updated", path)

    def on_change(self, callback):
        self._listeners.append(callback)

    def _notify(self, action, path):
        for cb in self._listeners:
            try:
                cb(action, path)
            except Exception as e:
                print(f"Listener error: {e}")


class NotificationLog:
    """Persistent notification history."""

    def __init__(self, max_entries=200):
        self.entries = []  # [(timestamp, app, title, body, icon)]
        self.max_entries = max_entries
        self._listeners = []

    def add(self, app, title, body, icon="phone"):
        entry = (time.time(), app, title, body, icon)
        self.entries.insert(0, entry)
        if len(self.entries) > self.max_entries:
            self.entries.pop()
        for cb in self._listeners:
            try:
                cb(entry)
            except Exception:
                pass

    def on_new(self, callback):
        self._listeners.append(callback)

    def clear(self):
        self.entries.clear()


class MConnectApp(Gtk.Application):
    """Main GTK Application."""

    def __init__(self):
        super().__init__(application_id=APP_ID,
                         flags=Gio.ApplicationFlags.FLAGS_NONE)
        self.dbus = MConnectDBus()
        self.store = DeviceStore(self.dbus)
        self.notif_log = NotificationLog()
        self.window = None
        self.status_icon = None
        self._selected_path = None
        self._update_timers = []
        self._start_hidden = False
        self._icon_style = self._load_setting("icon_style", "color")

    def do_activate(self):
        if not self.window:
            self.window = self._build_window()
            self.window.set_application(self)
        if not self._start_hidden:
            self.window.show_all()
            self.window.present()

    def do_startup(self):
        Gtk.Application.do_startup(self)
        Notify.init(APP_NAME)

        # Ensure daemon is running in our D-Bus session
        self._ensure_daemon()

        # Connect to daemon
        if not self.dbus.connect():
            # Retry after a short delay
            GLib.timeout_add(1000, self._retry_connect)

        # Set up D-Bus signal handlers
        self.dbus.set_device_added_callback(self._on_device_added)
        self.dbus.set_device_removed_callback(self._on_device_removed)
        self.dbus.set_notification_received_callback(self._on_phone_notification)
        self.dbus.set_property_changed_callback(self._on_property_changed)
        self.dbus.set_transfer_callback(self._on_transfer_event)

        # Active transfers tracker
        self._active_transfers = {}

        # Initial device load
        self.store.refresh()

        # Create tray icon
        self._create_status_icon()

        # Periodic battery/status refresh
        self._update_timers.append(
            GLib.timeout_add_seconds(30, self._refresh_all_device_status)
        )

    def _ensure_daemon(self):
        """Start the daemon if not already running in our D-Bus session."""
        # Check if already running
        try:
            uid = os.getuid()
            user_bus_address = f"unix:path=/run/user/{uid}/bus"
            if os.path.exists(f"/run/user/{uid}/bus"):
                conn = Gio.DBusConnection.new_for_address_sync(
                    user_bus_address,
                    Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION,
                    None,
                    None
                )
                proxy = Gio.DBusProxy.new_sync(
                    conn,
                    Gio.DBusProxyFlags.NONE,
                    None,
                    "org.xconnect",
                    "/org/xconnect/manager",
                    "org.xconnect.DeviceManager",
                    None
                )
            else:
                proxy = Gio.DBusProxy.new_for_bus_sync(
                    Gio.BusType.SESSION, Gio.DBusProxyFlags.NONE, None,
                    "org.xconnect", "/org/xconnect/manager",
                    "org.xconnect.DeviceManager", None)
            proxy.ListDevices()
            return  # Daemon running
        except Exception:
            pass

        # Start daemon via systemd
        try:
            subprocess.run(
                ["systemctl", "--user", "start", "xconnect.service"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=True
            )
            import time
            time.sleep(1)
        except Exception as e:
            print(f"Failed to start daemon via systemd: {e}")

    def _retry_connect(self):
        """Retry connecting to daemon after startup delay."""
        if self.dbus.connect():
            self.store.refresh()
            self._rebuild_device_list()
            self._update_welcome_status()
            return False  # Don't repeat
        return True  # Retry

    def _show_daemon_warning(self):
        dialog = Gtk.MessageDialog(
            transient_for=self.window,
            flags=0,
            message_type=Gtk.MessageType.WARNING,
            buttons=Gtk.ButtonsType.OK,
            text="xconnect daemon is not running"
        )
        dialog.format_secondary_text(
            "The xconnect daemon must be running for this application to work.\n\n"
            "Start it with:\n"
            "  systemctl --user start xconnect.service"
        )
        dialog.run()
        dialog.destroy()
        return False

    # ── Status Icon ──────────────────────────────────────────────────

    def _create_status_icon(self):
        self.status_icon = XApp.StatusIcon.new_with_name(APP_NAME)
        self._apply_tray_icon()
        self.status_icon.set_tooltip_text("xconnect")
        self.status_icon.connect("activate", self._on_tray_activate)

        # Right-click context menu
        self._tray_menu = Gtk.Menu()

        open_item = Gtk.MenuItem(label="Open")
        open_item.connect("activate", lambda w: self._show_window())
        self._tray_menu.append(open_item)

        self._tray_menu.append(Gtk.SeparatorMenuItem())

        quit_item = Gtk.MenuItem(label="Quit")
        quit_item.connect("activate", lambda w: self.quit())
        self._tray_menu.append(quit_item)

        self._tray_menu.show_all()
        self.status_icon.set_secondary_menu(self._tray_menu)

        self._update_tray_icon()

    def _apply_tray_icon(self):
        """Set tray icon based on user preference."""
        if self._icon_style == "bw":
            icon_path = os.path.join(ICON_DIR, "xconnect-bw.png")
        else:
            icon_path = os.path.join(ICON_DIR, "xconnect.png")

        if os.path.exists(icon_path):
            self.status_icon.set_icon_name(icon_path)
        else:
            # Fallback to theme icon
            self.status_icon.set_icon_name("xconnect")

    def _on_tray_activate(self, icon, button, panel_position):
        # Left-click toggles window
        if button == 1:
            if self.window and self.window.get_visible():
                self.window.hide()
            else:
                self._show_window()
        # Right-click shows context menu (handled by secondary_menu)
        elif button == 3:
            self.status_icon.popup_menu(
                self._tray_menu, 0, 0, button,
                Gtk.get_current_event_time(), panel_position)

    def _show_window(self):
        if not self.window:
            self.activate()
        else:
            self.window.show_all()
            self.window.present()

    def _update_tray_icon(self):
        connected = [d for d in self.store.devices.values()
                     if d.get("active") or d.get("connected")]
        if connected:
            names = [d["name"] for d in connected]
            self.status_icon.set_tooltip_text(
                f"xconnect — {', '.join(names)}")
            self.status_icon.set_label(str(len(connected))
                                       if len(connected) > 1 else "")
        else:
            self.status_icon.set_tooltip_text("xconnect — no devices")
            self.status_icon.set_label("")

    # ── D-Bus Callbacks ──────────────────────────────────────────────

    def _on_device_added(self, path):
        info = {
            "path": path,
            "id": self.dbus.get_prop(path, "Id"),
            "name": self.dbus.get_prop(path, "Name"),
            "type": self.dbus.get_prop(path, "DeviceType"),
            "paired": self.dbus.get_prop(path, "IsPaired"),
            "active": self.dbus.get_prop(path, "IsActive"),
            "connected": self.dbus.get_prop(path, "IsConnected"),
        }
        self.store.add(path, info)
        self._update_tray_icon()
        GLib.idle_add(self._rebuild_device_list)
        name = info.get("name", "Unknown")
        self.notif_log.add("xconnect", "Device Found",
                           f"{name} is now available")
        GLib.idle_add(self._show_notification, "Device Found",
                      f"{name} is now available")

    def _on_device_removed(self, path):
        name = self.store.devices.get(path, {}).get("name", "Unknown")
        self.store.remove(path)
        self._update_tray_icon()
        GLib.idle_add(self._rebuild_device_list)
        self.notif_log.add("xconnect", "Device Lost",
                           f"{name} disconnected")

    def _on_phone_notification(self, path, nid, app, title, icon_path):
        """Handle notification received from phone."""
        name = self.store.devices.get(path, {}).get("name", "Phone")
        self.notif_log.add(app, title, f"[{name}]")
        GLib.idle_add(self._show_notification, f"{app}: {title}",
                      f"From {name}", "phone")

    def _on_property_changed(self, path, props):
        """Handle D-Bus property changes on a device."""
        if "Level" in props:
            self.store.update(path, "battery_level", props["Level"])
        if "Charging" in props:
            self.store.update(path, "battery_charging", props["Charging"])
        if "CellularNetworkType" in props:
            self.store.update(path, "net_type", props["CellularNetworkType"])
        if "CellularNetworkStrength" in props:
            self.store.update(path, "net_strength",
                              props["CellularNetworkStrength"])
        if "IsActive" in props:
            self.store.update(path, "active", props["IsActive"])
        if "IsConnected" in props:
            self.store.update(path, "connected", props["IsConnected"])
        if "IsPaired" in props:
            self.store.update(path, "paired", props["IsPaired"])
        GLib.idle_add(self._update_device_detail)
        GLib.idle_add(self._update_tray_icon)
        GLib.idle_add(self._rebuild_device_list)

    def _on_transfer_event(self, event, path, detail):
        """Handle file transfer events."""
        if event == "started":
            self._active_transfers[path] = True
            GLib.idle_add(self._update_transfer_spinner)
        elif event in ("finished", "failed"):
            self._active_transfers.pop(path, None)
            GLib.idle_add(self._update_transfer_spinner)
            if event == "finished":
                GLib.idle_add(self._toast, "File transfer complete")
            else:
                GLib.idle_add(self._toast,
                              f"File transfer failed: {detail}")

    def _update_transfer_spinner(self):
        """Show/hide the transfer spinner based on active transfers."""
        if self._active_transfers:
            self.transfer_spinner.start()
            self.transfer_spinner.show()
        else:
            self.transfer_spinner.stop()
            self.transfer_spinner.hide()

    def _refresh_all_device_status(self):
        for path in list(self.store.devices.keys()):
            level, charging = self.dbus.get_battery(path)
            if level is not None:
                self.store.update(path, "battery_level", level)
                self.store.update(path, "battery_charging", charging)
            net_type, strength = self.dbus.get_connectivity(path)
            if net_type is not None:
                self.store.update(path, "net_type", net_type)
                self.store.update(path, "net_strength", strength)
        GLib.idle_add(self._update_device_detail)
        return True  # keep timer

    # ── Main Window ──────────────────────────────────────────────────

    def _build_window(self):
        win = Gtk.ApplicationWindow(application=self)
        win.set_title("xconnect")
        win.set_default_size(900, 600)
        win.set_icon_name("xconnect")

        # Header bar
        header = Gtk.HeaderBar()
        header.set_show_close_button(True)
        header.set_title("xconnect")
        header.set_subtitle("KDE Connect client")
        win.set_titlebar(header)

        # Refresh button
        refresh_btn = Gtk.Button.new_from_icon_name(
            "view-refresh-symbolic", Gtk.IconSize.BUTTON)
        refresh_btn.set_tooltip_text("Refresh devices")
        refresh_btn.connect("clicked", lambda w: self._refresh_devices())
        header.pack_start(refresh_btn)

        # Settings button
        settings_btn = Gtk.Button.new_from_icon_name(
            "preferences-system-symbolic", Gtk.IconSize.BUTTON)
        settings_btn.set_tooltip_text("Settings")
        settings_btn.connect("clicked", lambda w: self._open_settings())
        header.pack_end(settings_btn)

        # Transfer progress spinner
        self.transfer_spinner = Gtk.Spinner()
        self.transfer_spinner.set_tooltip_text("Transferring files...")
        header.pack_end(self.transfer_spinner)

        # Main layout: sidebar + content
        paned = Gtk.Paned(orientation=Gtk.Orientation.HORIZONTAL)
        paned.set_position(260)

        # Sidebar
        sidebar = self._build_sidebar()
        paned.pack1(sidebar, False, False)

        # Content stack
        self.content_stack = Gtk.Stack()
        self.content_stack.set_transition_type(
            Gtk.StackTransitionType.SLIDE_UP_DOWN)
        self.content_stack.set_transition_duration(200)

        # Welcome page
        welcome = self._build_welcome_page()
        self.content_stack.add_named(welcome, "welcome")

        # Device detail page
        detail = self._build_device_detail()
        self.content_stack.add_named(detail, "device")

        # Notification page
        notif_page = self._build_notification_page()
        self.content_stack.add_named(notif_page, "notifications")

        # MPRIS page
        mpris_page = self._build_mpris_page()
        self.content_stack.add_named(mpris_page, "mpris")

        paned.pack2(self.content_stack, True, True)

        win.add(paned)
        win.connect("delete-event", self._on_window_close)

        # Select first device if available
        GLib.idle_add(self._select_first_device)

        return win

    def _on_window_close(self, widget, event):
        widget.hide()
        return True  # don't destroy, keep in tray

    # ── Sidebar ──────────────────────────────────────────────────────

    def _build_sidebar(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)

        # Device list
        sw = Gtk.ScrolledWindow()
        sw.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)

        self.device_listbox = Gtk.ListBox()
        self.device_listbox.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self.device_listbox.connect("row-selected", self._on_device_selected)
        sw.add(self.device_listbox)

        box.pack_start(sw, True, True, 0)

        # Bottom buttons
        sep = Gtk.Separator()
        box.pack_start(sep, False, False, 0)

        btn_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        btn_box.set_margin_start(8)
        btn_box.set_margin_end(8)
        btn_box.set_margin_top(8)
        btn_box.set_margin_bottom(8)

        dev_btn = Gtk.Button.new_with_label("Devices")
        dev_btn.set_image(Gtk.Image.new_from_icon_name(
            "smartphone-symbolic", Gtk.IconSize.BUTTON))
        dev_btn.set_always_show_image(True)
        dev_btn.connect("clicked",
                        lambda w: self.content_stack.set_visible_child_name(
                            "device" if self.device_listbox.get_selected_row() else "welcome"))
        btn_box.pack_start(dev_btn, True, True, 0)

        notif_btn = Gtk.Button.new_with_label("Notifications")
        notif_btn.set_image(Gtk.Image.new_from_icon_name(
            "preferences-desktop-notifications-symbolic", Gtk.IconSize.BUTTON))
        notif_btn.set_always_show_image(True)
        notif_btn.connect("clicked",
                          lambda w: self.content_stack.set_visible_child_name(
                              "notifications"))
        btn_box.pack_start(notif_btn, True, True, 0)

        mpris_btn = Gtk.Button.new_with_label("Media")
        mpris_btn.set_image(Gtk.Image.new_from_icon_name(
            "audio-x-generic-symbolic", Gtk.IconSize.BUTTON))
        mpris_btn.set_always_show_image(True)
        mpris_btn.connect("clicked",
                          lambda w: self.content_stack.set_visible_child_name(
                              "mpris"))
        btn_box.pack_start(mpris_btn, True, True, 0)

        box.pack_start(btn_box, False, False, 0)

        self._rebuild_device_list()
        box.show_all()
        return box

    def _rebuild_device_list(self):
        for child in self.device_listbox.get_children():
            self.device_listbox.remove(child)

        for path, info in sorted(self.store.devices.items(),
                                  key=lambda x: x[1].get("name", "")):
            row = self._build_device_row(path, info)
            self.device_listbox.add(row)

        self.device_listbox.show_all()

    def _build_device_row(self, path, info):
        name = info.get("name", "Unknown")
        dev_type = info.get("type", "unknown")
        is_active = info.get("active") or info.get("connected")
        is_paired = info.get("paired")

        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        box.set_margin_start(12)
        box.set_margin_end(12)
        box.set_margin_top(8)
        box.set_margin_bottom(8)

        # Icon
        icon_name = self._icon_for_type(dev_type)
        icon = Gtk.Image.new_from_icon_name(icon_name, Gtk.IconSize.LARGE_TOOLBAR)
        box.pack_start(icon, False, False, 0)

        # Name + status
        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        label = Gtk.Label(label=name)
        label.set_halign(Gtk.Align.START)
        label.set_ellipsize(Pango.EllipsizeMode.END)
        vbox.pack_start(label, False, False, 0)

        status = Gtk.Label()
        if is_active and is_paired:
            status.set_markup(
                '<span size="small" color="#2e7d32">Connected</span>')
        elif is_active and not is_paired:
            status.set_markup(
                '<span size="small" color="#f57c00">Pairing required</span>')
        else:
            status.set_markup(
                '<span size="small" color="#9e9e9e">Disconnected</span>')
        status.set_halign(Gtk.Align.START)
        vbox.pack_start(status, False, False, 0)

        box.pack_start(vbox, True, True, 0)

        # Battery indicator
        batt_level = info.get("battery_level")
        if batt_level is not None:
            batt_label = Gtk.Label(label=f"{batt_level}%")
            batt_label.set_halign(Gtk.Align.END)
            box.pack_end(batt_label, False, False, 0)

        row = Gtk.ListBoxRow()
        row.add(box)
        row._device_path = path
        row.connect("button-press-event",
                     lambda w, e, p=path, i=info: self._on_device_right_click(
                         w, e, p, i))
        return row

    def _on_device_right_click(self, widget, event, path, info):
        """Show context menu on right-click of a device row."""
        if event.button != 3:
            return False

        is_active = info.get("active") or info.get("connected")
        is_paired = info.get("paired")
        name = info.get("name", "device")

        menu = Gtk.Menu()

        # Pair / Unpair
        if not is_paired and is_active:
            pair_item = Gtk.MenuItem(label="Send Pairing Request")
            pair_item.connect("activate",
                              lambda w: self._pair_device(path))
            menu.append(pair_item)
        elif is_paired:
            unpair_item = Gtk.MenuItem(label="Unpair")
            unpair_item.connect("activate",
                                lambda w: self._unpair_device(path))
            menu.append(unpair_item)

        menu.append(Gtk.SeparatorMenuItem())

        # Ping
        ping_item = Gtk.MenuItem(label="Ping")
        ping_item.set_sensitive(is_active and is_paired)
        ping_item.connect("activate",
                          lambda w: self._ping_device(path))
        menu.append(ping_item)

        # Find
        find_item = Gtk.MenuItem(label="Find My Phone")
        find_item.set_sensitive(is_active and is_paired)
        find_item.connect("activate",
                          lambda w: self._find_device(path))
        menu.append(find_item)

        menu.append(Gtk.SeparatorMenuItem())

        # Remove from list
        remove_item = Gtk.MenuItem(label="Remove")
        remove_item.connect("activate",
                            lambda w: self._remove_device(path))
        menu.append(remove_item)

        menu.show_all()
        menu.popup_at_pointer(event)
        return True

    def _pair_device(self, path):
        """Send pairing request to device via D-Bus."""
        if self.dbus.allow_device(path):
            self._toast("Pairing request sent")
        else:
            self._toast("Pairing failed")

    def _unpair_device(self, path):
        """Unpair a device."""
        # Fully remove device from config and memory
        self.dbus.remove_device(path)
        self.store.remove(path)
        self._rebuild_device_list()
        self.content_stack.set_visible_child_name("welcome")

    def _remove_device(self, path):
        """Completely remove device from config and memory."""
        self.dbus.remove_device(path)
        self.store.remove(path)
        self._rebuild_device_list()
        self.content_stack.set_visible_child_name("welcome")

    def _on_device_selected(self, listbox, row):
        if row:
            self._selected_path = row._device_path
            self._update_device_detail()
            self.content_stack.set_visible_child_name("device")

    def _select_first_device(self):
        row = self.device_listbox.get_row_at_index(0)
        if row:
            self.device_listbox.select_row(row)
        return False

    # ── Welcome Page ─────────────────────────────────────────────────

    def _build_welcome_page(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
        box.set_valign(Gtk.Align.CENTER)
        box.set_halign(Gtk.Align.CENTER)
        box.set_margin_start(40)
        box.set_margin_end(40)

        icon = Gtk.Image.new_from_icon_name("xconnect", Gtk.IconSize.DIALOG)
        box.pack_start(icon, False, False, 0)

        title = Gtk.Label()
        title.set_markup(
            '<span size="x-large" weight="bold">xconnect</span>')
        box.pack_start(title, False, False, 0)

        self.welcome_status = Gtk.Label(label="Checking daemon...")
        self.welcome_status.set_line_wrap(True)
        self.welcome_status.set_justify(Gtk.Justification.CENTER)
        box.pack_start(self.welcome_status, False, False, 0)

        sep = Gtk.Separator()
        box.pack_start(sep, False, False, 0)

        hint_lines = [
            "To connect your phone:",
            "",
            "  1. Install KDE Connect on your phone",
            "  2. Make sure both devices are on the same network",
            "  3. Open KDE Connect and discover this PC",
            "  4. Accept the pairing request",
            "",
            "If the phone doesn't see this PC, check your firewall:",
            "  sudo ufw allow 1714:1716/udp",
            "  sudo ufw allow 1714:1716/tcp",
        ]
        hint = Gtk.Label(label="\n".join(hint_lines))
        hint.set_line_wrap(True)
        hint.set_justify(Gtk.Justification.CENTER)
        hint.set_selectable(True)
        box.pack_start(hint, False, False, 0)

        refresh_btn = Gtk.Button.new_with_label("Refresh")
        refresh_btn.set_image(Gtk.Image.new_from_icon_name(
            "view-refresh-symbolic", Gtk.IconSize.BUTTON))
        refresh_btn.set_always_show_image(True)
        refresh_btn.set_halign(Gtk.Align.CENTER)
        refresh_btn.connect("clicked", lambda w: self._refresh_devices())
        box.pack_start(refresh_btn, False, False, 0)

        box.show_all()
        GLib.idle_add(self._update_welcome_status)
        return box

    def _update_welcome_status(self):
        if self.dbus.connected:
            self.welcome_status.set_text(
                "Daemon running - searching for devices...")
        else:
            self.welcome_status.set_text(
                "Daemon not running")
        return False

    # ── Device Detail Page ───────────────────────────────────────────

    def _build_device_detail(self):
        self.detail_box = Gtk.Box(
            orientation=Gtk.Orientation.VERTICAL, spacing=16)
        self.detail_box.set_margin_start(24)
        self.detail_box.set_margin_end(24)
        self.detail_box.set_margin_top(24)
        self.detail_box.set_margin_bottom(24)

        # Header: name + type
        self.detail_header = Gtk.Label()
        self.detail_header.set_xalign(0)
        self.detail_box.pack_start(self.detail_header, False, False, 0)

        # Status cards row
        cards = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        self.batt_card = self._build_info_card(
            "battery-good-symbolic", "Battery", "--")
        cards.pack_start(self.batt_card, True, True, 0)
        self.conn_card = self._build_info_card(
            "network-cellular-symbolic", "Signal", "--")
        cards.pack_start(self.conn_card, True, True, 0)
        self.detail_box.pack_start(cards, False, False, 0)

        # Separator
        self.detail_box.pack_start(Gtk.Separator(), False, False, 0)

        # Actions grid
        actions_label = Gtk.Label(label="Actions")
        actions_label.set_xalign(0)
        actions_label.get_style_context().add_class("dim-label")
        self.detail_box.pack_start(actions_label, False, False, 0)

        action_grid = Gtk.Grid()
        action_grid.set_column_spacing(8)
        action_grid.set_row_spacing(8)
        action_grid.set_column_homogeneous(True)

        actions = [
            ("Ping", "dialog-information-symbolic", self._action_ping),
            ("Find Phone", "edit-find-symbolic", self._action_find),
            ("Send File", "document-send-symbolic", self._action_send_file),
            ("Send URL", "web-browser-symbolic", self._action_send_url),
            ("Send Text", "accessories-text-editor-symbolic",
             self._action_send_text),
            ("Send SMS", "mail-send-symbolic", self._action_send_sms),
            ("Lock Device", "system-lock-screen-symbolic",
             self._action_lock),
            ("Unpair", "dialog-error-symbolic", self._action_unpair),
            ("Remove", "edit-delete-symbolic", self._action_remove),
        ]

        for i, (label, icon_name, callback) in enumerate(actions):
            btn = Gtk.Button.new_from_icon_name(icon_name, Gtk.IconSize.BUTTON)
            btn.set_label(label)
            btn.set_always_show_image(True)
            btn.set_relief(Gtk.ReliefStyle.NONE)
            btn.connect("clicked", lambda w, cb=callback: cb())
            action_grid.attach(btn, i % 4, i // 4, 1, 1)

        self.detail_box.pack_start(action_grid, False, False, 0)

        # Separator
        self.detail_box.pack_start(Gtk.Separator(), False, False, 0)

        # Notification echo area
        notif_label = Gtk.Label(label="Recent Notifications from Device")
        notif_label.set_xalign(0)
        notif_label.get_style_context().add_class("dim-label")
        self.detail_box.pack_start(notif_label, False, False, 0)

        sw = Gtk.ScrolledWindow()
        sw.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        sw.set_min_content_height(150)
        self.device_notif_list = Gtk.ListBox()
        self.device_notif_list.set_selection_mode(Gtk.SelectionMode.NONE)
        sw.add(self.device_notif_list)
        self.detail_box.pack_start(sw, True, True, 0)

        self.detail_box.show_all()
        return self.detail_box

    def _build_info_card(self, icon_name, title, value):
        frame = Gtk.Frame()
        frame.set_shadow_type(Gtk.ShadowType.ETCHED_IN)

        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        box.set_margin_start(12)
        box.set_margin_end(12)
        box.set_margin_top(10)
        box.set_margin_bottom(10)

        icon = Gtk.Image.new_from_icon_name(icon_name, Gtk.IconSize.DND)
        box.pack_start(icon, False, False, 0)

        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        title_lbl = Gtk.Label(label=title)
        title_lbl.set_xalign(0)
        title_lbl.get_style_context().add_class("dim-label")
        vbox.pack_start(title_lbl, False, False, 0)

        value_lbl = Gtk.Label()
        value_lbl.set_markup(f'<span size="large" weight="bold">{value}</span>')
        value_lbl.set_xalign(0)
        vbox.pack_start(value_lbl, False, False, 0)

        box.pack_start(vbox, True, True, 0)
        frame.add(box)
        frame._value_label = value_lbl
        frame.show_all()
        return frame

    def _update_device_detail(self):
        if not self._selected_path:
            return

        path = self._selected_path
        info = self.store.devices.get(path, {})
        if not info:
            return

        name = info.get("name", "Unknown")
        dev_type = info.get("type", "unknown")
        is_active = info.get("active") or info.get("connected")
        is_paired = info.get("paired")

        # Header
        icon_name = self._icon_for_type(dev_type)
        if is_active and is_paired:
            status_color = "#2e7d32"
            status_text = "Connected"
        elif is_active and not is_paired:
            status_color = "#f57c00"
            status_text = "Pairing required — accept on phone"
        else:
            status_color = "#9e9e9e"
            status_text = "Disconnected"
        self.detail_header.set_markup(
            f'<span size="x-large" weight="bold">{name}</span>\n'
            f'<span color="{status_color}">{status_text}</span>')

        # Battery
        level = info.get("battery_level")
        charging = info.get("battery_charging")
        if level is not None:
            batt_text = f"{level}%"
            if charging:
                batt_text += " ⚡"
            icon = "battery-full-symbolic" if level > 50 else \
                "battery-low-symbolic" if level > 15 else \
                "battery-empty-symbolic"
            self.batt_card._value_label.set_markup(
                f'<span size="large" weight="bold">{batt_text}</span>')
        else:
            self.batt_card._value_label.set_markup(
                '<span size="large" color="#9e9e9e">N/A</span>')

        # Connectivity
        net_type = info.get("net_type")
        strength = info.get("net_strength")
        if net_type:
            self.conn_card._value_label.set_markup(
                f'<span size="large" weight="bold">{net_type} {strength}%</span>')
        else:
            self.conn_card._value_label.set_markup(
                '<span size="large" color="#9e9e9e">N/A</span>')

    # ── Notification Page ────────────────────────────────────────────

    def _build_notification_page(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        box.set_margin_start(12)
        box.set_margin_end(12)
        box.set_margin_top(12)
        box.set_margin_bottom(12)

        header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        title = Gtk.Label(label="Notification History")
        title.set_xalign(0)
        title.get_style_context().add_class("dim-label")
        header.pack_start(title, True, True, 0)

        clear_btn = Gtk.Button.new_with_label("Clear")
        clear_btn.connect("clicked", lambda w: self._clear_notifications())
        header.pack_end(clear_btn, False, False, 0)
        box.pack_start(header, False, False, 0)

        sw = Gtk.ScrolledWindow()
        sw.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)

        self.notif_listbox = Gtk.ListBox()
        self.notif_listbox.set_selection_mode(Gtk.SelectionMode.NONE)
        sw.add(self.notif_listbox)
        box.pack_start(sw, True, True, 0)

        # Listen for new notifications
        self.notif_log.on_new(self._on_new_notification)

        box.show_all()
        return box

    def _on_new_notification(self, entry):
        GLib.idle_add(self._add_notification_row, entry)

    def _add_notification_row(self, entry):
        ts, app, title, body, icon = entry
        time_str = datetime.fromtimestamp(ts).strftime("%H:%M")

        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        box.set_margin_start(8)
        box.set_margin_end(8)
        box.set_margin_top(6)
        box.set_margin_bottom(6)

        img = Gtk.Image.new_from_icon_name(icon, Gtk.IconSize.LARGE_TOOLBAR)
        box.pack_start(img, False, False, 0)

        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        top = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        app_lbl = Gtk.Label(label=app)
        app_lbl.set_xalign(0)
        app_lbl.get_style_context().add_class("dim-label")
        top.pack_start(app_lbl, True, True, 0)
        time_lbl = Gtk.Label(label=time_str)
        time_lbl.set_xalign(1)
        time_lbl.get_style_context().add_class("dim-label")
        top.pack_end(time_lbl, False, False, 0)
        vbox.pack_start(top, False, False, 0)

        title_lbl = Gtk.Label(label=title)
        title_lbl.set_xalign(0)
        title_lbl.set_ellipsize(Pango.EllipsizeMode.END)
        title_lbl.get_style_context().add_class("font-weight-bold")
        vbox.pack_start(title_lbl, False, False, 0)

        if body:
            body_lbl = Gtk.Label(label=body)
            body_lbl.set_xalign(0)
            body_lbl.set_ellipsize(Pango.EllipsizeMode.END)
            body_lbl.set_lines(2)
            vbox.pack_start(body_lbl, False, False, 0)

        box.pack_start(vbox, True, True, 0)

        row = Gtk.ListBoxRow()
        row.add(box)
        self.notif_listbox.prepend(row)
        self.notif_listbox.show_all()

    def _clear_notifications(self):
        self.notif_log.clear()
        for child in self.notif_listbox.get_children():
            self.notif_listbox.remove(child)

    # ── MPRIS Page ───────────────────────────────────────────────────

    def _build_mpris_page(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        box.set_margin_start(24)
        box.set_margin_end(24)
        box.set_margin_top(24)
        box.set_margin_bottom(24)
        box.set_valign(Gtk.Align.CENTER)

        title = Gtk.Label(label="Media Control")
        title.set_markup(
            '<span size="large" weight="bold">Media Control</span>')
        title.set_xalign(0)
        box.pack_start(title, False, False, 0)

        subtitle = Gtk.Label(
            label="Control media playback on your connected device")
        subtitle.set_xalign(0)
        subtitle.get_style_context().add_class("dim-label")
        box.pack_start(subtitle, False, False, 0)

        box.pack_start(Gtk.Separator(), False, False, 0)

        # Now playing info
        self.mpris_title_label = Gtk.Label(label="No media playing")
        self.mpris_title_label.set_markup(
            '<span size="large">No media playing</span>')
        self.mpris_title_label.set_xalign(0)
        self.mpris_title_label.set_ellipsize(Pango.EllipsizeMode.END)
        box.pack_start(self.mpris_title_label, False, False, 0)

        self.mpris_artist_label = Gtk.Label(label="")
        self.mpris_artist_label.set_xalign(0)
        self.mpris_artist_label.get_style_context().add_class("dim-label")
        box.pack_start(self.mpris_artist_label, False, False, 0)

        self.mpris_album_label = Gtk.Label(label="")
        self.mpris_album_label.set_xalign(0)
        self.mpris_album_label.get_style_context().add_class("dim-label")
        box.pack_start(self.mpris_album_label, False, False, 0)

        box.pack_start(Gtk.Separator(), False, False, 0)

        # Playback controls
        controls = Gtk.Box(
            orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        controls.set_halign(Gtk.Align.CENTER)
        controls.set_margin_top(12)

        prev_btn = Gtk.Button.new_from_icon_name(
            "media-skip-backward-symbolic", Gtk.IconSize.LARGE_TOOLBAR)
        prev_btn.set_relief(Gtk.ReliefStyle.NONE)
        prev_btn.connect("clicked", lambda w: self._mpris_action("Previous"))
        controls.pack_start(prev_btn, False, False, 0)

        self.mpris_play_btn = Gtk.Button.new_from_icon_name(
            "media-playback-start-symbolic", Gtk.IconSize.DND)
        self.mpris_play_btn.set_relief(Gtk.ReliefStyle.NONE)
        self.mpris_play_btn.connect("clicked",
                                    lambda w: self._mpris_action("PlayPause"))
        controls.pack_start(self.mpris_play_btn, False, False, 0)

        next_btn = Gtk.Button.new_from_icon_name(
            "media-skip-forward-symbolic", Gtk.IconSize.LARGE_TOOLBAR)
        next_btn.set_relief(Gtk.ReliefStyle.NONE)
        next_btn.connect("clicked", lambda w: self._mpris_action("Next"))
        controls.pack_start(next_btn, False, False, 0)

        box.pack_start(controls, False, False, 0)

        # Volume
        vol_box = Gtk.Box(
            orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        vol_box.set_halign(Gtk.Align.CENTER)
        vol_box.set_margin_top(12)

        vol_icon = Gtk.Image.new_from_icon_name(
            "audio-volume-low-symbolic", Gtk.IconSize.BUTTON)
        vol_box.pack_start(vol_icon, False, False, 0)

        self.mpris_volume = Gtk.Scale.new_with_range(
            Gtk.Orientation.HORIZONTAL, 0, 100, 5)
        self.mpris_volume.set_value(50)
        self.mpris_volume.set_size_request(200, -1)
        self.mpris_volume.connect("value-changed",
                                  lambda s: self._mpris_set_volume(
                                      int(s.get_value())))
        vol_box.pack_start(self.mpris_volume, True, True, 0)

        vol_high = Gtk.Image.new_from_icon_name(
            "audio-volume-high-symbolic", Gtk.IconSize.BUTTON)
        vol_box.pack_start(vol_high, False, False, 0)

        box.pack_start(vol_box, False, False, 0)

        # Status
        self.mpris_status_label = Gtk.Label(label="")
        self.mpris_status_label.get_style_context().add_class("dim-label")
        box.pack_start(self.mpris_status_label, False, False, 0)

        # Player selector (if multiple)
        self.mpris_player_combo = Gtk.ComboBoxText()
        self.mpris_player_combo.connect("changed",
                                        self._on_mpris_player_changed)
        box.pack_start(self.mpris_player_combo, False, False, 0)

        box.show_all()
        self.mpris_player_combo.hide()

        # MPRIS metadata polling
        self._mpris_player_name = None
        self._update_timers.append(
            GLib.timeout_add_seconds(2, self._poll_mpris_metadata))

        return box

    def _on_mpris_player_changed(self, combo):
        """Handle player selection change."""
        active = combo.get_active_id()
        if active:
            self._mpris_player_name = active

    def _get_mpris_players(self):
        """List MPRIS player bus names."""
        players = []
        try:
            bus = Gio.bus_get_sync(Gio.BusType.SESSION)
            result = bus.call_sync(
                "org.freedesktop.DBus", "/org/freedesktop/DBus",
                "org.freedesktop.DBus", "ListNames", None, None,
                Gio.DBusCallFlags.NONE, 5000, None)
            if result:
                for name in result.unpack()[0]:
                    if name.startswith("org.mpris.MediaPlayer2."):
                        players.append(name)
        except Exception:
            pass
        return players

    def _get_mpris_proxy(self, bus_name, iface="org.mpris.MediaPlayer2.Player"):
        """Get a D-Bus proxy for an MPRIS player."""
        try:
            return Gio.DBusProxy.new_for_bus_sync(
                Gio.BusType.SESSION, Gio.DBusProxyFlags.NONE, None,
                bus_name, "/org/mpris/MediaPlayer2", iface, None)
        except Exception:
            return None

    def _mpris_action(self, method):
        """Call an MPRIS method on the active player."""
        players = self._get_mpris_players()
        target = self._mpris_player_name
        if not target and players:
            target = players[0]
        if target:
            try:
                player = self._get_mpris_proxy(target)
                if player:
                    getattr(player, method)()
            except Exception as e:
                print(f"MPRIS {method} error: {e}")

    def _mpris_set_volume(self, vol):
        """Set volume on the active player."""
        players = self._get_mpris_players()
        target = self._mpris_player_name or (players[0] if players else None)
        if target:
            try:
                player = self._get_mpris_proxy(target)
                if player:
                    player.set_cached_property(
                        "Volume", GLib.Variant("d", vol / 100.0))
            except Exception as e:
                print(f"MPRIS volume error: {e}")

    def _poll_mpris_metadata(self):
        """Poll MPRIS players for metadata updates."""
        players = self._get_mpris_players()

        # Update player selector if count changed
        if len(players) > 1:
            current = self.mpris_player_combo.get_active_text()
            self.mpris_player_combo.remove_all()
            for p in players:
                short = p.replace("org.mpris.MediaPlayer2.", "")
                self.mpris_player_combo.append(p, short)
            if not self._mpris_player_name and players:
                self._mpris_player_name = players[0]
            if self._mpris_player_name:
                self.mpris_player_combo.set_active_id(
                    self._mpris_player_name)
            self.mpris_player_combo.show()
        elif len(players) <= 1:
            self.mpris_player_combo.hide()
            if players:
                self._mpris_player_name = players[0]

        # Get metadata from active player
        target = self._mpris_player_name or (players[0] if players else None)
        if target:
            try:
                player = self._get_mpris_proxy(target)
                if player:
                    metadata = player.get_cached_property("Metadata")
                    if metadata:
                        meta = metadata.unpack()
                        title = meta.get("xesam:title", [""])[0] \
                            if isinstance(meta.get("xesam:title"), list) \
                            else str(meta.get("xesam:title", ""))
                        artist = meta.get("xesam:artist", [""])[0] \
                            if isinstance(meta.get("xesam:artist"), list) \
                            else str(meta.get("xesam:artist", ""))
                        album = meta.get("xesam:album", [""])[0] \
                            if isinstance(meta.get("xesam:album"), list) \
                            else str(meta.get("xesam:album", ""))

                        if title:
                            self.mpris_title_label.set_markup(
                                f'<span size="large" weight="bold">'
                                f'{GLib.markup_escape_text(title)}</span>')
                            self.mpris_artist_label.set_text(artist)
                            self.mpris_album_label.set_text(album)
                        else:
                            self.mpris_title_label.set_markup(
                                '<span size="large">No media playing</span>')
                            self.mpris_artist_label.set_text("")
                            self.mpris_album_label.set_text("")

                    # Playback status
                    status = player.get_cached_property("PlaybackStatus")
                    if status:
                        s = status.unpack()
                        icon = "media-playback-pause-symbolic" \
                            if s == "Playing" \
                            else "media-playback-start-symbolic"
                        self.mpris_play_btn.set_image(
                            Gtk.Image.new_from_icon_name(
                                icon, Gtk.IconSize.DND))
                        self.mpris_status_label.set_text(s)
                    return True
            except Exception:
                pass

        # No player found
        self.mpris_title_label.set_markup(
            '<span size="large">No media playing</span>')
        self.mpris_artist_label.set_text("")
        self.mpris_album_label.set_text("")
        self.mpris_status_label.set_text("")
        return True  # keep timer

    # ── Device Actions ───────────────────────────────────────────────

    def _get_selected(self):
        if not self._selected_path:
            return None, None
        return self._selected_path, self.store.devices.get(
            self._selected_path, {})

    def _action_ping(self):
        path, info = self._get_selected()
        if path:
            self.dbus.ping(path)
            self._toast(f"Pinged {info.get('name', 'device')}")

    def _action_find(self):
        path, info = self._get_selected()
        if path:
            self.dbus.find_device(path)
            self._toast(f"{info.get('name', 'device')} should be ringing")

    def _action_send_file(self):
        path, info = self._get_selected()
        if not path:
            return
        dialog = Gtk.FileChooserDialog(
            title="Select File", parent=self.window,
            action=Gtk.FileChooserAction.OPEN)
        dialog.add_buttons(Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL,
                           Gtk.STOCK_OPEN, Gtk.ResponseType.OK)
        response = dialog.run()
        if response == Gtk.ResponseType.OK:
            fpath = dialog.get_filename()
            if fpath:
                self.dbus.share_file(path, fpath)
                self._toast(f"Sending {os.path.basename(fpath)}")
        dialog.destroy()

    def _action_send_url(self):
        path, info = self._get_selected()
        if not path:
            return
        url = self._prompt("Send URL", "URL:", "https://")
        if url:
            self.dbus.share_url(path, url)
            self._toast("URL sent")

    def _action_send_text(self):
        path, info = self._get_selected()
        if not path:
            return
        text = self._prompt_multiline("Send Text", "Text to send:")
        if text:
            self.dbus.share_text(path, text)
            self._toast("Text sent")

    def _action_send_sms(self):
        path, info = self._get_selected()
        if not path:
            return

        win = Gtk.Window(title="SMS — " + info.get("name", "Device"))
        win.set_transient_for(self.window)
        win.set_default_size(400, 500)
        win.set_position(Gtk.WindowPosition.CENTER_ON_PARENT)

        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)

        # Header with phone number
        header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        header.set_margin_start(12)
        header.set_margin_end(12)
        header.set_margin_top(8)
        header.set_margin_bottom(8)

        num_label = Gtk.Label(label="To:")
        header.pack_start(num_label, False, False, 0)

        num_entry = Gtk.Entry()
        num_entry.set_placeholder_text("+1234567890")
        num_entry.set_hexpand(True)
        header.pack_start(num_entry, True, True, 0)
        vbox.pack_start(header, False, False, 0)

        vbox.pack_start(Gtk.Separator(), False, False, 0)

        # Conversation area
        sw = Gtk.ScrolledWindow()
        sw.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        sw.set_vexpand(True)

        self._sms_messages = Gtk.ListBox()
        self._sms_messages.set_selection_mode(Gtk.SelectionMode.NONE)
        sw.add(self._sms_messages)
        vbox.pack_start(sw, True, True, 0)

        vbox.pack_start(Gtk.Separator(), False, False, 0)

        # Compose area
        compose = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        compose.set_margin_start(8)
        compose.set_margin_end(8)
        compose.set_margin_top(8)
        compose.set_margin_bottom(8)

        msg_entry = Gtk.Entry()
        msg_entry.set_placeholder_text("Type a message...")
        msg_entry.set_hexpand(True)
        msg_entry.connect("activate",
                          lambda w: self._sms_send(
                              path, num_entry, msg_entry))
        compose.pack_start(msg_entry, True, True, 0)

        send_btn = Gtk.Button.new_from_icon_name(
            "mail-send-symbolic", Gtk.IconSize.BUTTON)
        send_btn.connect("clicked",
                         lambda w: self._sms_send(
                             path, num_entry, msg_entry))
        compose.pack_end(send_btn, False, False, 0)

        vbox.pack_start(compose, False, False, 0)

        win.add(vbox)
        win.show_all()

    def _sms_send(self, path, num_entry, msg_entry):
        """Send SMS and add to conversation."""
        number = num_entry.get_text().strip()
        message = msg_entry.get_text().strip()
        if not number or not message:
            return

        if self.dbus.send_sms(path, number, message):
            # Add sent message to conversation
            row = self._sms_bubble(message, sent=True)
            self._sms_messages.add(row)
            self._sms_messages.show_all()
            msg_entry.set_text("")
            # Scroll to bottom
            adj = self._sms_messages.get_adjustment()
            if adj:
                adj.set_value(adj.get_upper())
        else:
            self._toast("Failed to send SMS")

    def _sms_bubble(self, text, sent=False):
        """Create a chat bubble row."""
        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=0)
        box.set_margin_start(8 if sent else 40)
        box.set_margin_end(40 if sent else 8)
        box.set_margin_top(4)
        box.set_margin_bottom(4)

        label = Gtk.Label(label=text)
        label.set_line_wrap(True)
        label.set_line_wrap_mode(Pango.WrapMode.WORD)
        label.set_xalign(0 if sent else 1)
        label.set_margin_start(10)
        label.set_margin_end(10)
        label.set_margin_top(6)
        label.set_margin_bottom(6)

        if sent:
            box.pack_end(label, False, False, 0)
            label.get_style_context().add_class("accent")
        else:
            box.pack_start(label, False, False, 0)

        row = Gtk.ListBoxRow()
        row.set_selectable(False)
        row.add(box)
        return row

    def _action_lock(self):
        path, info = self._get_selected()
        if path:
            self.dbus.lock_device(path, True)
            self._toast("Lock command sent")

    def _action_unpair(self):
        path, info = self._get_selected()
        if path:
            name = info.get("name", "device")
            self.dbus.disallow_device(path)
            self.store.remove(path)
            self._rebuild_device_list()
            self.content_stack.set_visible_child_name("welcome")
            self._toast(f"Unpaired from {name}")

    def _action_remove(self):
        path, info = self._get_selected()
        if path:
            name = info.get("name", "device")
            dialog = Gtk.MessageDialog(
                transient_for=self.window,
                flags=0,
                message_type=Gtk.MessageType.QUESTION,
                buttons=Gtk.ButtonsType.YES_NO,
                text=f"Remove {name}?")
            dialog.format_secondary_text(
                "This will permanently remove the device from the list.")
            response = dialog.run()
            dialog.destroy()
            if response == Gtk.ResponseType.YES:
                self.dbus.remove_device(path)
                self.store.remove(path)
                self._rebuild_device_list()
                self.content_stack.set_visible_child_name("welcome")
                self._toast(f"Removed {name}")

    # ── Settings Dialog ──────────────────────────────────────────────

    def _open_settings(self):
        dialog = Gtk.Dialog(title="Settings", parent=self.window,
                            flags=Gtk.DialogFlags.MODAL)
        dialog.add_buttons(Gtk.STOCK_CLOSE, Gtk.ResponseType.CLOSE)
        dialog.set_default_size(600, 500)

        content = dialog.get_content_area()
        content.set_spacing(12)
        content.set_margin_start(16)
        content.set_margin_end(16)
        content.set_margin_top(16)
        content.set_margin_bottom(16)

        notebook = Gtk.Notebook()
        content.pack_start(notebook, True, True, 0)

        # ── General tab ──────────────────────────────────────────
        general = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        general.set_margin_start(12)
        general.set_margin_end(12)
        general.set_margin_top(12)
        general.set_margin_bottom(12)

        # Daemon section
        daemon_label = Gtk.Label()
        daemon_label.set_markup(
            '<span weight="bold">Daemon</span>')
        daemon_label.set_xalign(0)
        general.pack_start(daemon_label, False, False, 0)

        daemon_box = Gtk.Box(
            orientation=Gtk.Orientation.HORIZONTAL, spacing=8)

        self.daemon_status_label = Gtk.Label(
            label="Status: checking...")
        daemon_box.pack_start(self.daemon_status_label, True, True, 0)

        self.daemon_toggle_btn = Gtk.Button.new_with_label("Start daemon")
        self.daemon_toggle_btn.connect("clicked", lambda w: self._toggle_daemon())
        daemon_box.pack_end(self.daemon_toggle_btn, False, False, 0)

        general.pack_start(daemon_box, False, False, 0)

        # Custom devices section
        general.pack_start(Gtk.Separator(), False, False, 0)
        custom_label = Gtk.Label()
        custom_label.set_markup(
            '<span weight="bold">Custom Device Addresses</span>')
        custom_label.set_xalign(0)
        general.pack_start(custom_label, False, False, 0)

        custom_entry_box = Gtk.Box(
            orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        self.custom_addr_entry = Gtk.Entry()
        self.custom_addr_entry.set_placeholder_text("192.168.1.100")
        custom_entry_box.pack_start(self.custom_addr_entry, True, True, 0)
        add_btn = Gtk.Button.new_with_label("Add")
        add_btn.connect("clicked", lambda w: self._add_custom_device())
        custom_entry_box.pack_end(add_btn, False, False, 0)
        general.pack_start(custom_entry_box, False, False, 0)

        # Transfer directory
        general.pack_start(Gtk.Separator(), False, False, 0)
        dl_label = Gtk.Label()
        dl_label.set_markup(
            '<span weight="bold">File Transfers</span>')
        dl_label.set_xalign(0)
        general.pack_start(dl_label, False, False, 0)

        dl_path = os.path.expanduser("~/Downloads/xconnect")
        dl_info = Gtk.Label(label=f"Received files: {dl_path}")
        dl_info.set_xalign(0)
        dl_info.set_ellipsize(Pango.EllipsizeMode.MIDDLE)
        general.pack_start(dl_info, False, False, 0)

        open_dl_btn = Gtk.Button.new_with_label("Open Downloads Folder")
        open_dl_btn.connect("clicked",
                            lambda w: subprocess.Popen(
                                ["xdg-open", dl_path]))
        general.pack_start(open_dl_btn, False, False, 0)

        # Icon style section
        general.pack_start(Gtk.Separator(), False, False, 0)
        icon_label = Gtk.Label()
        icon_label.set_markup(
            '<span weight="bold">Tray Icon Style</span>')
        icon_label.set_xalign(0)
        general.pack_start(icon_label, False, False, 0)

        icon_box = Gtk.Box(
            orientation=Gtk.Orientation.HORIZONTAL, spacing=12)

        color_radio = Gtk.RadioButton.new_with_label_from_widget(
            None, "Color")
        color_radio.connect("toggled", lambda w: self._set_icon_style(
            "color" if w.get_active() else "bw"))
        icon_box.pack_start(color_radio, False, False, 0)

        bw_radio = Gtk.RadioButton.new_with_label_from_widget(
            color_radio, "Black & White")
        bw_radio.connect("toggled", lambda w: self._set_icon_style(
            "bw" if w.get_active() else "color"))
        icon_box.pack_start(bw_radio, False, False, 0)

        # Set current selection
        if self._icon_style == "bw":
            bw_radio.set_active(True)
        else:
            color_radio.set_active(True)

        general.pack_start(icon_box, False, False, 0)

        notebook.append_page(general, Gtk.Label(label="General"))

        # ── Config Editor tab ────────────────────────────────────
        config_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        config_box.set_margin_start(12)
        config_box.set_margin_end(12)
        config_box.set_margin_top(12)
        config_box.set_margin_bottom(12)

        config_path = os.path.expanduser(
            "~/.config/xconnect/xconnect.conf")

        config_header = Gtk.Box(
            orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        config_path_label = Gtk.Label(label=config_path)
        config_path_label.set_xalign(0)
        config_path_label.set_ellipsize(Pango.EllipsizeMode.MIDDLE)
        config_header.pack_start(config_path_label, True, True, 0)

        reload_btn = Gtk.Button.new_with_label("Reload")
        reload_btn.connect("clicked",
                           lambda w: self._load_config_editor(
                               config_editor, config_path))
        config_header.pack_end(reload_btn, False, False, 0)

        save_btn = Gtk.Button.new_with_label("Save")
        save_btn.connect("clicked",
                         lambda w: self._save_config_editor(
                             config_editor, config_path))
        config_header.pack_end(save_btn, False, False, 0)

        config_box.pack_start(config_header, False, False, 0)

        sw = Gtk.ScrolledWindow()
        sw.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        config_editor = Gtk.TextView()
        config_editor.set_monospace(True)
        config_editor.set_wrap_mode(Gtk.WrapMode.NONE)
        sw.add(config_editor)
        config_box.pack_start(sw, True, True, 0)

        notebook.append_page(config_box, Gtk.Label(label="Config Editor"))

        # ── About tab ────────────────────────────────────────────
        about = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        about.set_margin_start(24)
        about.set_margin_end(24)
        about.set_margin_top(24)
        about.set_margin_bottom(24)
        about.set_valign(Gtk.Align.CENTER)

        about_icon = Gtk.Image.new_from_icon_name(
            "xconnect", Gtk.IconSize.DIALOG)
        about.pack_start(about_icon, False, False, 0)

        about_title = Gtk.Label()
        about_title.set_markup(
            '<span size="x-large" weight="bold">xconnect</span>')
        about.pack_start(about_title, False, False, 0)

        about_ver = Gtk.Label(label="Version 2.0")
        about.pack_start(about_ver, False, False, 0)

        about_desc = Gtk.Label(
            label="KDE Connect protocol client for Linux desktops")
        about_desc.get_style_context().add_class("dim-label")
        about.pack_start(about_desc, False, False, 0)

        about_url = Gtk.Label()
        about_url.set_markup(
            '<a href="https://github.com/Twilight0/xconnect">'
            'github.com/Twilight0/xconnect</a>')
        about.pack_start(about_url, False, False, 0)

        notebook.append_page(about, Gtk.Label(label="About"))

        for w in content.get_children():
            w.show_all()

        # Load config
        self._load_config_editor(config_editor, config_path)
        self._check_daemon_status()

        dialog.run()
        dialog.destroy()

    def _load_config_editor(self, editor, path):
        """Load config file into the text editor."""
        try:
            with open(path, "r") as f:
                content = f.read()
        except FileNotFoundError:
            content = "# xconnect configuration file\n[main]\ndevices=\n"
        editor.get_buffer().set_text(content)

    def _set_icon_style(self, style):
        """Change tray icon style and save preference."""
        self._icon_style = style
        self._save_setting("icon_style", style)
        if self.status_icon:
            self._apply_tray_icon()

    def _save_config_editor(self, editor, path):
        """Save the text editor contents to config file."""
        buf = editor.get_buffer()
        content = buf.get_text(buf.get_start_iter(),
                               buf.get_end_iter(), True)
        try:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w") as f:
                f.write(content)
            self._toast("Config saved")
        except Exception as e:
            self._toast(f"Failed to save: {e}")

    def _check_daemon_status(self):
        if self.dbus.connected:
            self.daemon_status_label.set_markup(
                '<span color="#2e7d32">Running</span>')
            self.daemon_toggle_btn.set_label("Stop daemon")
        else:
            self.daemon_status_label.set_markup(
                '<span color="#c62828">Not running</span>')
            self.daemon_toggle_btn.set_label("Start daemon")

    def _toggle_daemon(self):
        if self.dbus.connected:
            # Stop daemon
            try:
                subprocess.run(
                    ["systemctl", "--user", "stop", "xconnect.service"],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    check=True
                )
                self.dbus.disconnect()
                self._check_daemon_status()
                self._toast("Daemon stopped")
            except Exception as e:
                self._toast(f"Failed to stop daemon: {e}")
        else:
            # Start daemon
            try:
                subprocess.run(
                    ["systemctl", "--user", "start", "xconnect.service"],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    check=True
                )
                import time
                time.sleep(1)
                if self.dbus.connect():
                    self.store.refresh()
                    self._rebuild_device_list()
                    self._check_daemon_status()
                    self._toast("Daemon started")
                else:
                    self._toast("Daemon started but connection failed")
            except Exception as e:
                self._toast(f"Failed to start daemon: {e}")

    def _open_config_file(self, path):
        try:
            subprocess.Popen(["xdg-open", path])
        except Exception:
            pass

    def _add_custom_device(self):
        addr = self.custom_addr_entry.get_text().strip()
        if addr:
            try:
                if self.dbus._manager:
                    self.dbus._manager.AddCustomDevice("(s)", addr)
                    self.custom_addr_entry.set_text("")
                    self._toast(f"Added {addr}")
                else:
                    self._toast("Failed: Not connected to daemon")
            except Exception as e:
                self._toast(f"Failed: {e}")

    def quit(self):
        """Quit the application."""
        for src in self._update_timers:
            GLib.source_remove(src)
        Notify.uninit()
        self.release()
        Gtk.main_quit()

    # ── Settings Helpers ─────────────────────────────────────────────

    def _load_setting(self, key, default=None):
        """Load a setting from the GUI config file."""
        try:
            os.makedirs(SETTINGS_DIR, exist_ok=True)
            if os.path.exists(SETTINGS_FILE):
                with open(SETTINGS_FILE, "r") as f:
                    for line in f:
                        line = line.strip()
                        if "=" in line and not line.startswith("#"):
                            k, v = line.split("=", 1)
                            if k.strip() == key:
                                return v.strip()
        except Exception:
            pass
        return default

    def _save_setting(self, key, value):
        """Save a setting to the GUI config file."""
        try:
            os.makedirs(SETTINGS_DIR, exist_ok=True)
            lines = []
            if os.path.exists(SETTINGS_FILE):
                with open(SETTINGS_FILE, "r") as f:
                    lines = f.readlines()

            found = False
            for i, line in enumerate(lines):
                if line.strip().startswith(key + "="):
                    lines[i] = f"{key}={value}\n"
                    found = True
                    break
            if not found:
                lines.append(f"{key}={value}\n")

            with open(SETTINGS_FILE, "w") as f:
                f.writelines(lines)
        except Exception as e:
            print(f"Failed to save setting: {e}")

    # ── Helpers ──────────────────────────────────────────────────────

    def _show_notification(self, title, body, icon="phone"):
        try:
            notif = Notify.Notification.new(title, body, icon)
            notif.show()
        except Exception:
            pass

    def _toast(self, text):
        """Brief status message via notification."""
        self._show_notification("xconnect", text)

    def _prompt(self, title, label, default=""):
        dialog = Gtk.Dialog(title=title, parent=self.window,
                            flags=Gtk.DialogFlags.MODAL)
        dialog.add_buttons(Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL,
                           Gtk.STOCK_OK, Gtk.ResponseType.OK)
        content = dialog.get_content_area()
        content.set_spacing(10)
        content.set_margin_start(12)
        content.set_margin_end(12)
        content.set_margin_top(12)

        lbl = Gtk.Label(label=label)
        lbl.set_xalign(0)
        content.add(lbl)

        entry = Gtk.Entry()
        entry.set_text(default)
        entry.set_width_chars(40)
        content.add(entry)

        for w in content.get_children():
            w.show()

        response = dialog.run()
        result = entry.get_text().strip() if response == Gtk.ResponseType.OK \
            else None
        dialog.destroy()
        return result

    def _prompt_multiline(self, title, label):
        dialog = Gtk.Dialog(title=title, parent=self.window,
                            flags=Gtk.DialogFlags.MODAL)
        dialog.add_buttons(Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL,
                           Gtk.STOCK_OK, Gtk.ResponseType.OK)
        dialog.set_default_size(450, 300)

        content = dialog.get_content_area()
        content.set_spacing(10)
        content.set_margin_start(12)
        content.set_margin_end(12)
        content.set_margin_top(12)

        lbl = Gtk.Label(label=label)
        lbl.set_xalign(0)
        content.add(lbl)

        sw = Gtk.ScrolledWindow()
        sw.set_min_content_height(200)
        tv = Gtk.TextView()
        tv.set_wrap_mode(Gtk.WrapMode.WORD)
        sw.add(tv)
        content.add(sw)

        for w in content.get_children():
            w.show()
        tv.show()

        response = dialog.run()
        if response == Gtk.ResponseType.OK:
            buf = tv.get_buffer()
            result = buf.get_text(buf.get_start_iter(),
                                  buf.get_end_iter(), True).strip()
        else:
            result = None
        dialog.destroy()
        return result

    def _refresh_devices(self):
        if self.dbus.connected:
            self.dbus._enumerate_devices()
            self.store.refresh()
            self._rebuild_device_list()
            self._toast("Devices refreshed")

    @staticmethod
    def _icon_for_type(dev_type):
        icons = {
            "phone": "phone",
            "tablet": "tablet",
            "desktop": "computer",
            "laptop": "computer",
            "tv": "video-display",
        }
        return icons.get(dev_type, "dialog-information")


def main():
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    start_hidden = "--hidden" in sys.argv
    # Strip --hidden so GApplication doesn't reject it
    argv = [a for a in sys.argv if a != "--hidden"]
    app = MConnectApp()
    app._start_hidden = start_hidden
    app.run(argv)


if __name__ == "__main__":
    main()
