#!/usr/bin/env python3
"""
D-Bus client for communicating with the xconnect daemon.
Provides Pythonic wrappers around the org.xconnect D-Bus interfaces.
"""

import gi
gi.require_version('Gio', '2.0')
gi.require_version('GLib', '2.0')
from gi.repository import Gio, GLib, GObject
import json
import os

BUS_NAME = "org.xconnect"
MANAGER_PATH = "/org/xconnect/manager"

# D-Bus introspection XML for DeviceManager
MANAGER_IFACE = """
<node>
  <interface name="org.xconnect.DeviceManager">
    <method name="AllowDevice">
      <arg type="s" name="path" direction="in"/>
    </method>
    <method name="DisallowDevice">
      <arg type="s" name="path" direction="in"/>
    </method>
    <method name="RemoveDevice">
      <arg type="s" name="path" direction="in"/>
    </method>
    <method name="ListDevices">
      <arg type="ao" name="result" direction="out"/>
    </method>
    <method name="AddCustomDevice">
      <arg type="s" name="address" direction="in"/>
    </method>
    <method name="RemoveCustomDevice">
      <arg type="s" name="address" direction="in"/>
    </method>
    <property type="as" name="CustomDevices" access="read"/>
    <property type="s" name="Certificate" access="read"/>
    <signal name="DeviceAdded">
      <arg type="s" name="path"/>
    </signal>
    <signal name="DeviceRemoved">
      <arg type="s" name="path"/>
    </signal>
    <signal name="CustomDevicesChanged">
      <arg type="as" name="devices"/>
    </signal>
  </interface>
</node>
"""

# D-Bus introspection XML for Device
DEVICE_IFACE = """
<node>
  <interface name="org.xconnect.Device">
    <property type="s" name="Id" access="read"/>
    <property type="s" name="Name" access="read"/>
    <property type="s" name="DeviceType" access="read"/>
    <property type="u" name="ProtocolVersion" access="read"/>
    <property type="s" name="Address" access="read"/>
    <property type="b" name="IsPaired" access="read"/>
    <property type="b" name="Allowed" access="read"/>
    <property type="b" name="IsActive" access="read"/>
    <property type="b" name="IsConnected" access="read"/>
    <property type="as" name="IncomingCapabilities" access="read"/>
    <property type="as" name="OutgoingCapabilities" access="read"/>
  </interface>
</node>
"""

# D-Bus introspection XML for Battery
BATTERY_IFACE = """
<node>
  <interface name="org.xconnect.Device.Battery">
    <property type="u" name="Level" access="read"/>
    <property type="b" name="Charging" access="read"/>
  </interface>
</node>
"""

# D-Bus introspection XML for Ping
PING_IFACE = """
<node>
  <interface name="org.xconnect.Device.Ping">
    <method name="SendPing"/>
    <signal name="Ping"/>
  </interface>
</node>
"""

# D-Bus introspection XML for Share
SHARE_IFACE = """
<node>
  <interface name="org.xconnect.Device.Share">
    <method name="ShareFile">
      <arg type="s" name="path" direction="in"/>
    </method>
    <method name="ShareUrl">
      <arg type="s" name="url" direction="in"/>
    </method>
    <method name="ShareText">
      <arg type="s" name="text" direction="in"/>
    </method>
  </interface>
</node>
"""

# D-Bus introspection XML for FindMyPhone
FINDMYPHONE_IFACE = """
<node>
  <interface name="org.xconnect.Device.FindMyPhone">
    <method name="Find"/>
    <signal name="FindMyPhone"/>
  </interface>
</node>
"""

# D-Bus introspection XML for Telephony
TELEPHONY_IFACE = """
<node>
  <interface name="org.xconnect.Device.Telephony">
    <method name="SendSms">
      <arg type="s" name="number" direction="in"/>
      <arg type="s" name="message" direction="in"/>
    </method>
  </interface>
</node>
"""

# D-Bus introspection XML for ConnectivityReport
CONNECTIVITY_IFACE = """
<node>
  <interface name="org.xconnect.Device.ConnectivityReport">
    <property type="s" name="CellularNetworkType" access="read"/>
    <property type="i" name="CellularNetworkStrength" access="read"/>
  </interface>
</node>
"""

# D-Bus introspection XML for LockDevice
LOCKDEVICE_IFACE = """
<node>
  <interface name="org.xconnect.Device.LockDevice">
    <property type="b" name="IsLocked" access="read"/>
    <method name="SetLocked">
      <arg type="b" name="lock" direction="in"/>
    </method>
    <method name="SendLockState">
      <arg type="b" name="is_locked" direction="in"/>
    </method>
  </interface>
</node>
"""

# D-Bus introspection XML for SystemVolume
SYSTEMVOLUME_IFACE = """
<node>
  <interface name="org.xconnect.Device.SystemVolume">
    <method name="SendVolume">
      <arg type="s" name="sink_name" direction="in"/>
      <arg type="i" name="volume" direction="in"/>
      <arg type="b" name="muted" direction="in"/>
    </method>
    <method name="SendMaxVolume">
      <arg type="i" name="max_volume" direction="in"/>
    </method>
  </interface>
</node>
"""


class MConnectDBus:
    """Main D-Bus client for communicating with xconnect daemon."""

    def __init__(self):
        self._conn = None
        self._manager = None
        self._devices = {}  # path -> DeviceProxy
        self._device_proxies = {}  # path -> {iface_name: proxy}
        self._connected = False

    def _new_proxy(self, name, path, interface):
        if self._conn:
            return Gio.DBusProxy.new_sync(
                self._conn,
                Gio.DBusProxyFlags.NONE,
                None,
                name,
                path,
                interface,
                None
            )
        else:
            return Gio.DBusProxy.new_for_bus_sync(
                Gio.BusType.SESSION,
                Gio.DBusProxyFlags.NONE,
                None,
                name,
                path,
                interface,
                None
            )

        self._manager_info = Gio.DBusNodeInfo.new_for_xml(MANAGER_IFACE)
        self._device_info = Gio.DBusNodeInfo.new_for_xml(DEVICE_IFACE)
        self._battery_info = Gio.DBusNodeInfo.new_for_xml(BATTERY_IFACE)
        self._ping_info = Gio.DBusNodeInfo.new_for_xml(PING_IFACE)
        self._share_info = Gio.DBusNodeInfo.new_for_xml(SHARE_IFACE)
        self._findmyphone_info = Gio.DBusNodeInfo.new_for_xml(FINDMYPHONE_IFACE)
        self._telephony_info = Gio.DBusNodeInfo.new_for_xml(TELEPHONY_IFACE)
        self._connectivity_info = Gio.DBusNodeInfo.new_for_xml(CONNECTIVITY_IFACE)
        self._lockdevice_info = Gio.DBusNodeInfo.new_for_xml(LOCKDEVICE_IFACE)
        self._systemvolume_info = Gio.DBusNodeInfo.new_for_xml(SYSTEMVOLUME_IFACE)

    def connect(self):
        """Connect to the xconnect D-Bus service."""
        try:
            self._conn = None
            uid = os.getuid()
            user_bus_address = f"unix:path=/run/user/{uid}/bus"
            if os.path.exists(f"/run/user/{uid}/bus"):
                try:
                    self._conn = Gio.DBusConnection.new_for_address_sync(
                        user_bus_address,
                        Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION,
                        None,
                        None
                    )
                except Exception as e:
                    print(f"Failed to connect to user bus at {user_bus_address}: {e}")
                    self._conn = None

            self._manager = self._new_proxy(
                BUS_NAME,
                MANAGER_PATH,
                "org.xconnect.DeviceManager"
            )
            self._connected = True

            # Connect signals
            self._manager.connect("g-signal", self._on_manager_signal)

            # Connect to transfer manager
            try:
                self._transfer_mgr = self._new_proxy(
                    BUS_NAME,
                    "/org/xconnect/transfer",
                    "org.xconnect.TransferManager"
                )
                self._transfer_mgr.connect("g-signal",
                                           self._on_transfer_signal)
            except Exception:
                self._transfer_mgr = None

            # Enumerate existing devices
            self._enumerate_devices()

            return True
        except Exception as e:
            print(f"Failed to connect to xconnect: {e}")
            self._connected = False
            return False

    @property
    def connected(self):
        return self._connected

    def disconnect(self):
        """Disconnect from the daemon."""
        self._conn = None
        self._manager = None
        self._devices = {}
        self._device_proxies = {}
        self._connected = False

    def _on_manager_signal(self, proxy, sender, signal_name, parameters):
        """Handle signals from the DeviceManager."""
        if signal_name == "DeviceAdded":
            path = parameters.unpack()[0]
            self._add_device(path)
            if hasattr(self, '_device_added_callback'):
                self._device_added_callback(path)
        elif signal_name == "DeviceRemoved":
            path = parameters.unpack()[0]
            self._remove_device(path)
            if hasattr(self, '_device_removed_callback'):
                self._device_removed_callback(path)

    def _enumerate_devices(self):
        """List all currently known devices."""
        try:
            result = self._manager.ListDevices()
            for path in result:
                self._add_device(path)
        except Exception as e:
            print(f"Failed to enumerate devices: {e}")

    def _add_device(self, path):
        """Add a device proxy."""
        try:
            dev_proxy = self._new_proxy(
                BUS_NAME,
                path,
                "org.xconnect.Device"
            )
            self._devices[path] = dev_proxy

            # Add capability proxies
            self._device_proxies[path] = {}

            out_caps = dev_proxy.get_cached_property("OutgoingCapabilities")
            in_caps = dev_proxy.get_cached_property("IncomingCapabilities")
            out_list = out_caps.unpack() if out_caps else []
            in_list = in_caps.unpack() if in_caps else []
            cap_list = list(set(out_list + in_list))

            if "kdeconnect.battery" in cap_list:
                self._device_proxies[path]["battery"] = self._new_proxy(
                    BUS_NAME, path, "org.xconnect.Device.Battery"
                )
            if "kdeconnect.ping" in cap_list:
                self._device_proxies[path]["ping"] = self._new_proxy(
                    BUS_NAME, path, "org.xconnect.Device.Ping"
                )
            if "kdeconnect.share" in cap_list:
                self._device_proxies[path]["share"] = self._new_proxy(
                    BUS_NAME, path, "org.xconnect.Device.Share"
                )
            if ("kdeconnect.findmyphone.request" in cap_list
                    or "kdeconnect.findmyphone" in cap_list):
                self._device_proxies[path]["findmyphone"] = self._new_proxy(
                    BUS_NAME, path, "org.xconnect.Device.FindMyPhone"
                )
            if "kdeconnect.telephony" in cap_list:
                self._device_proxies[path]["telephony"] = self._new_proxy(
                    BUS_NAME, path, "org.xconnect.Device.Telephony"
                )
            if "kdeconnect.connectivity_report" in cap_list:
                self._device_proxies[path]["connectivity"] = self._new_proxy(
                    BUS_NAME, path, "org.xconnect.Device.ConnectivityReport"
                )
            if "kdeconnect.lock" in cap_list or "kdeconnect.lock.request" in cap_list:
                self._device_proxies[path]["lockdevice"] = self._new_proxy(
                    BUS_NAME, path, "org.xconnect.Device.LockDevice"
                )
            if "kdeconnect.systemvolume" in cap_list:
                self._device_proxies[path]["systemvolume"] = self._new_proxy(
                    BUS_NAME, path, "org.xconnect.Device.SystemVolume"
                )
            if "kdeconnect.mpris" in cap_list:
                self._device_proxies[path]["mpris"] = self._new_proxy(
                    BUS_NAME, path, "org.xconnect.Device.Mpris"
                )

            # Notification proxy (always register, incoming cap)
            try:
                notif_proxy = self._new_proxy(
                    BUS_NAME, path, "org.xconnect.Device.Notifications"
                )
                self._device_proxies[path]["notifications"] = notif_proxy
                # Subscribe to notification signals
                notif_proxy.connect("g-signal", self._on_notification_signal)
            except Exception:
                pass

            # Monitor device property changes (battery, connectivity, etc.)
            dev_proxy.connect("g-properties-changed",
                              self._on_device_properties_changed)

        except Exception as e:
            print(f"Failed to add device {path}: {e}")

    def _remove_device(self, path):
        """Remove a device proxy."""
        self._devices.pop(path, None)
        self._device_proxies.pop(path, None)

    def _on_device_properties_changed(self, proxy, changed_props, invalidated):
        """Handle D-Bus property changes on a device (battery, connectivity, etc.)."""
        # Find the path for this proxy
        path = None
        for p, px in self._devices.items():
            if px is proxy:
                path = p
                break
        if not path:
            return

        props = changed_props.unpack()
        if hasattr(self, '_property_changed_callback'):
            self._property_changed_callback(path, props)

    def _on_notification_signal(self, proxy, sender, signal_name, parameters):
        """Handle notification signals from a device."""
        # Find the path for this proxy
        path = None
        for p, px in self._device_proxies.items():
            if px.get("notifications") is proxy:
                path = p
                break
        if not path:
            return

        if signal_name == "notification_received":
            nid, app, title, icon_path = parameters.unpack()
            if hasattr(self, '_notification_received_callback'):
                self._notification_received_callback(path, nid, app, title, icon_path)
        elif signal_name == "notification_cancelled":
            nid = parameters.unpack()[0]
            if hasattr(self, '_notification_cancelled_callback'):
                self._notification_cancelled_callback(path, nid)

    def set_notification_received_callback(self, callback):
        """Set callback for phone notifications: callback(path, id, app, title, icon_path)."""
        self._notification_received_callback = callback

    def set_notification_cancelled_callback(self, callback):
        """Set callback for cancelled notifications: callback(path, id)."""
        self._notification_cancelled_callback = callback

    def set_property_changed_callback(self, callback):
        """Set callback for device property changes: callback(path, props_dict)."""
        self._property_changed_callback = callback

    def _on_transfer_signal(self, proxy, sender, signal_name, parameters):
        """Handle transfer manager signals."""
        if signal_name == "transfer_started":
            path = parameters.unpack()[0]
            if hasattr(self, '_transfer_callback'):
                self._transfer_callback("started", path, None)
        elif signal_name == "transfer_finished":
            path = parameters.unpack()[0]
            if hasattr(self, '_transfer_callback'):
                self._transfer_callback("finished", path, None)
        elif signal_name == "transfer_failed":
            path, reason = parameters.unpack()
            if hasattr(self, '_transfer_callback'):
                self._transfer_callback("failed", path, reason)

    def set_transfer_callback(self, callback):
        """Set callback for transfer events: callback(event, path, detail)."""
        self._transfer_callback = callback

    def get_devices(self):
        """Return list of (path, device_info) tuples."""
        result = []
        for path, proxy in self._devices.items():
            info = {
                "path": path,
                "id": self._get_prop(proxy, "Id"),
                "name": self._get_prop(proxy, "Name"),
                "type": self._get_prop(proxy, "DeviceType"),
                "paired": self._get_prop(proxy, "IsPaired"),
                "allowed": self._get_prop(proxy, "Allowed"),
                "active": self._get_prop(proxy, "IsActive"),
                "connected": self._get_prop(proxy, "IsConnected"),
            }
            result.append((path, info))
        return result

    def get_device_name(self, path):
        """Get device name by path."""
        proxy = self._devices.get(path)
        if proxy:
            return self._get_prop(proxy, "Name")
        return "Unknown"

    def get_device_type(self, path):
        """Get device type by path."""
        proxy = self._devices.get(path)
        if proxy:
            return self._get_prop(proxy, "DeviceType")
        return "unknown"

    def is_device_active(self, path):
        """Check if device is active/connected."""
        proxy = self._devices.get(path)
        if proxy:
            return self._get_prop(proxy, "IsActive") or self._get_prop(proxy, "IsConnected")
        return False

    def allow_device(self, path):
        """Allow/pair with a device."""
        try:
            self._manager.AllowDevice("(s)", path)
            return True
        except Exception as e:
            print(f"Failed to allow device: {e}")
            return False

    def disallow_device(self, path):
        """Disallow/unpair a device."""
        try:
            self._manager.DisallowDevice("(s)", path)
            return True
        except Exception as e:
            print(f"Failed to disallow device: {e}")
            return False

    def remove_device(self, path):
        """Completely remove a device from config and memory."""
        try:
            self._manager.RemoveDevice("(s)", path)
            return True
        except Exception as e:
            print(f"Failed to remove device: {e}")
            return False

    def get_battery(self, path):
        """Get battery level and charging state."""
        proxy = self._device_proxies.get(path, {}).get("battery")
        if proxy:
            level = self._get_prop(proxy, "Level")
            charging = self._get_prop(proxy, "Charging")
            return level, charging
        return None, None

    def get_connectivity(self, path):
        """Get connectivity info (network type, signal strength)."""
        proxy = self._device_proxies.get(path, {}).get("connectivity")
        if proxy:
            net_type = self._get_prop(proxy, "CellularNetworkType")
            strength = self._get_prop(proxy, "CellularNetworkStrength")
            return net_type, strength
        return None, None

    def ping(self, path):
        """Send a ping to the device."""
        proxy = self._device_proxies.get(path, {}).get("ping")
        if proxy:
            try:
                proxy.SendPing()
                return True
            except Exception:
                pass
        return False

    def find_device(self, path):
        """Make the device ring."""
        proxy = self._device_proxies.get(path, {}).get("findmyphone")
        if proxy:
            try:
                proxy.Find()
                return True
            except Exception as e:
                print(f"Failed to find device: {e}")
        return False

    def share_file(self, path, file_path):
        """Share a file with the device."""
        proxy = self._device_proxies.get(path, {}).get("share")
        if proxy:
            try:
                proxy.ShareFile(file_path)
                return True
            except Exception as e:
                print(f"Failed to share file: {e}")
        return False

    def share_url(self, path, url):
        """Share a URL with the device."""
        proxy = self._device_proxies.get(path, {}).get("share")
        if proxy:
            try:
                proxy.ShareUrl(url)
                return True
            except Exception as e:
                print(f"Failed to share URL: {e}")
        return False

    def share_text(self, path, text):
        """Share text with the device."""
        proxy = self._device_proxies.get(path, {}).get("share")
        if proxy:
            try:
                proxy.ShareText(text)
                return True
            except Exception as e:
                print(f"Failed to share text: {e}")
        return False

    def send_sms(self, path, number, message):
        """Send an SMS via the device."""
        proxy = self._device_proxies.get(path, {}).get("telephony")
        if proxy:
            try:
                proxy.SendSms(number, message)
                return True
            except Exception as e:
                print(f"Failed to send SMS: {e}")
        return False

    def lock_device(self, path, lock=True):
        """Send lock/unlock command to device."""
        proxy = self._device_proxies.get(path, {}).get("lockdevice")
        if proxy:
            try:
                proxy.SetLocked(lock)
                return True
            except Exception as e:
                print(f"Failed to lock device: {e}")
        return False

    def report_lock_state(self, path, is_locked):
        """Report our lock state to the device."""
        proxy = self._device_proxies.get(path, {}).get("lockdevice")
        if proxy:
            try:
                proxy.SendLockState(is_locked)
                return True
            except Exception as e:
                print(f"Failed to report lock state: {e}")
        return False

    def set_device_added_callback(self, callback):
        """Set callback for when a new device is added."""
        self._device_added_callback = callback

    def set_device_removed_callback(self, callback):
        """Set callback for when a device is removed."""
        self._device_removed_callback = callback

    @staticmethod
    def _get_prop(proxy, name):
        """Safely get a D-Bus property."""
        try:
            val = proxy.get_cached_property(name)
            if val is not None:
                return val.unpack()
        except Exception:
            pass
        return None

    def get_prop(self, path, name):
        """Get a property from a device by path."""
        proxy = self._devices.get(path)
        if proxy:
            return self._get_prop(proxy, name)
        return None

    def get_icon_name_for_type(self, device_type):
        """Get an appropriate icon name for a device type."""
        icons = {
            "phone": "phone",
            "tablet": "tablet",
            "desktop": "computer",
            "laptop": "computer",
            "tv": "video-display",
        }
        return icons.get(device_type, "dialog-information")
