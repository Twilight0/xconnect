/**
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 as
 * published by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 *
 * AUTHORS
 * Maciek Borzecki <maciek.borzecki (at] gmail.com>
 */
using Gee;

[DBus (name = "org.xconnect.DeviceManager")]
class DeviceManagerDBusProxy : Object {
    private DeviceManager manager;

    public string certificate {
        owned get {
            return Core.instance ().certificate.certificate_pem;
        }
        private set {
        }
    }

    public string uuid {
        owned get {
            return Core.instance ().config.get_uuid ();
        }
        private set {
        }
    }

    public signal void device_added (string path);

    public signal void device_removed (string path);

    public string[] custom_devices {
        owned get {
            return manager.custom_device_list;
        }
    }

    public signal void custom_devices_changed (string[] devices);

    private const string DBUS_PATH = "/org/xconnect/manager";
    private DBusConnection bus = null;
    private HashMap<string, DeviceDBusProxy> devices;

    private int device_idx = 0;

    public DeviceManagerDBusProxy.with_manager (DBusConnection bus,
                                                DeviceManager manager) {
        this.manager = manager;
        this.bus = bus;
        this.devices = new HashMap<string, DeviceDBusProxy>();

        manager.found_new_device.connect ((d) => {
            this.add_device (d);
        });
        manager.device_capability_added.connect (this.add_device_capability);
    }

    [DBus (visible = false)]
    public void publish () throws Error {
        assert (this.bus != null);

        this.bus.register_object (DBUS_PATH, this);
    }

    /**
     * allow_device:
     * @path: device object path
     *
     * Allow given device
     */
    public void allow_device (string path) throws Error {
        debug ("allow device %s", path);

        var dev_proxy = this.devices.@get (path);

        if (dev_proxy == null) {
            warning ("no device under path %s", path);
            return;
        }

        this.manager.allow_device (dev_proxy.device);
    }

    /**
     * disallow_device:
     * @path: device object path
     *
     * Disallow given device
     */
    public void disallow_device (string path) throws Error {
        debug ("disallow device %s", path);

        var dev_proxy = this.devices.@get (path);

        if (dev_proxy == null) {
            warning ("no device under path %s", path);
            return;
        }

        this.manager.disallow_device (dev_proxy.device);

        // Remove from D-Bus proxy map and notify listeners
        this.devices.unset (path);
        device_removed (path);
    }

    /**
     * remove_device:
     * @path: device object path
     *
     * Completely remove a device from config and memory.
     * Unlike disallow_device, this forgets the device entirely.
     */
    public void remove_device (string path) throws Error {
        debug ("remove device %s", path);

        var dev_proxy = this.devices.@get (path);

        if (dev_proxy == null) {
            warning ("no device under path %s", path);
            return;
        }

        this.manager.remove_device (dev_proxy.device);

        // Remove from D-Bus proxy map and notify listeners
        this.devices.unset (path);
        device_removed (path);
    }

    /**
     * list_devices:
     *
     * Returns a list of DBus paths of all allowed devices
     */
    public ObjectPath[] list_devices () throws Error {
        ObjectPath[] devices = {};

        message ("LIST_DEVICES called, %u devices in map", (uint) this.devices.size);
        foreach (var entry in this.devices.entries) {
            var dev_proxy = entry.value;
            if (dev_proxy.device.allowed) {
                message ("  DEVICE PATH: %s (allowed)", entry.key);
                devices += new ObjectPath (entry.key);
            } else {
                message ("  DEVICE PATH: %s (not allowed, skipping)", entry.key);
            }
        }
        return devices;
    }

    /**
     * add_custom_device:
     * @address: IP address or hostname of the device
     *
     * Add a custom device address for manual connection
     */
    public void add_custom_device (string address) throws Error {
        this.manager.add_custom_device (address);
        custom_devices_changed (this.manager.custom_device_list);
    }
    public void remove_custom_device (string address) throws Error {
        this.manager.remove_custom_device (address);
        custom_devices_changed (this.manager.custom_device_list);
    }

    public string get_downloads_directory () throws Error {
        var core = Core.instance ();
        string custom_dir = core.config.get_downloads_dir ();
        if (custom_dir != null && custom_dir != "") {
            return custom_dir;
        }
        var downloaddir = Environment.get_user_special_dir (UserDirectory.DOWNLOAD);
        if (downloaddir == null) {
            downloaddir = Path.build_filename(Environment.get_home_dir(), "Downloads");
        }
        return Path.build_filename (downloaddir, "xconnect");
    }

    public void set_downloads_directory (string directory) throws Error {
        Core.instance ().config.set_downloads_dir (directory);
    }
    private void add_device (Device dev) {
        var path = make_device_path ();
        var device_proxy = new DeviceDBusProxy.for_device_with_path (dev,
                                                                     new ObjectPath (path));

        this.devices.@set (path, device_proxy);

        info ("register device %s under path %s",
              dev.to_string (), path);
        device_proxy.bus_register (this.bus);
        device_added (path);
    }

    private DeviceDBusProxy ? find_proxy_for_device (Device dev) {
        DeviceDBusProxy dp = null;
        foreach (var entry in this.devices.entries) {
            if (entry.value.device == dev) {
                dp = entry.value;
                break;
            }
        }
        return dp;
    }

    private void add_device_capability (Device dev,
                                        string capability,
                                        PacketHandlerInterface iface) {
        DeviceDBusProxy dp = find_proxy_for_device (dev);

        if (dp == null) {
            warning ("no bus proxy for device %s", dev.to_string ());
            return;
        }

        if (dp.has_handler (capability)) {
            return;
        }

        info ("add capability handler %s for device at path %s",
              capability, dp.object_path.to_string ());

        var h = PacketHandlersProxy.new_device_capability_handler (dev,
                                                                    capability,
                                                                    iface);
        if (h != null) {
            try {
                h.bus_register (this.bus, dp.object_path);
            } catch (Error e) {
                // Handler may already be registered for a related capability
                debug ("handler already registered at path %s: %s", dp.object_path, e.message);
            }
        }
    }

    /**
     * make_device_path:
     *
     * return device path string that can be used as ObjectPath
     */
    private string make_device_path () {
        var path = "/org/xconnect/device/%d".printf (this.device_idx);

        // bump device index
        this.device_idx++;

        return path;
    }
}
