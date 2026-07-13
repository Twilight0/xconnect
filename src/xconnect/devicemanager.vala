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

class DeviceManager : GLib.Object {
    public signal void found_new_device (Device dev);
    public signal void device_capability_added (Device dev,
                                                string capability,
                                                PacketHandlerInterface handler);

    public const string DEVICES_CACHE_FILE = "devices";

    private HashMap<string, Device> devices;
    private ArrayList<string> custom_devices;

    public string[] custom_device_list {
        owned get {
            return custom_devices.to_array ();
        }
    }

    public DeviceManager () {
        debug ("device manager..");

        this.devices = new HashMap<string, Device>();
        this.custom_devices = new ArrayList<string>();
    }

    public bool has_active_devices () {
        foreach (var dev in this.devices.values) {
            if (dev.is_active) {
                return true;
            }
        }
        return false;
    }

    /**
     * Obtain path to devices cache file
     */
    private string get_cache_file () {
        var cache_file = Path.build_filename (Core.get_cache_dir (),
                                              DEVICES_CACHE_FILE);
        vdebug ("cache file: %s", cache_file);

        // make sure that cache dir exists
        DirUtils.create_with_parents (Core.get_cache_dir (),
                                      0700);

        return cache_file;
    }

    /**
     * Load known devices from cache and attempt pairing.
     */
    public void load_cache () {
        var cache_file = get_cache_file ();

        debug ("try loading devices from device cache %s", cache_file);

        var kf = new KeyFile ();
        try {
            kf.load_from_file (cache_file, KeyFileFlags.NONE);

            string[] groups = kf.get_groups ();

            foreach (string group in groups) {
                var dev = Device.new_from_cache (kf, group);
                if (dev != null) {
                    debug ("device %s from cache", dev.to_string ());
                    handle_new_device (dev, true);
                }
            }
        } catch (Error e) {
            debug ("error loading cache file: %s", e.message);
        }
    }

    /**
     * Update contents of device cache
     */
    private void update_cache () {
        // debug("update devices cache");

        if (devices.size == 0)
            return;

        var kf = new KeyFile ();

        foreach (var dev in devices.values) {
            // Only cache allowed devices - disallowed devices should not persist
            if (dev.allowed) {
                dev.to_cache (kf, dev.device_name);
            }
        }

        try {
            // debug("saving to cache");
            FileUtils.set_contents (get_cache_file (),
                                    kf.to_data ());
        } catch (FileError e) {
            warning ("failed to save to cache file %s: %s",
                     get_cache_file (), e.message);
        }
    }

    public void handle_discovered_device (DiscoveredDevice discovered_dev) {
        message ("found device (discovered via UDP): %s", discovered_dev.to_string ());

        var new_dev = new Device.from_discovered_device (discovered_dev);

        handle_new_device (new_dev);
    }

    public void handle_new_device (Device new_dev, bool from_cache = false) {
        var is_new = false;
        string unique = new_dev.to_unique_string ();
        vdebug ("device key: %s", unique);

        if (this.devices.has_key (unique) == false) {
            debug ("adding new device with key: %s", unique);

            this.devices.@set (unique, new_dev);

            is_new = true;
        } else {
            debug ("device %s already present", unique);
        }

        var dev = this.devices.@get (unique);

        // notify everyone that a new device appeared
        if (is_new) {
            // make sure that this happens before we update device data so that
            // all subscribeds of found_new_device() signal have a chance to
            // setup eveything they need
            found_new_device (dev);
        }

        if (is_new) {
            dev.capability_added.connect (this.device_capability_added_cb);
            dev.capability_removed.connect (this.device_capability_removed_cb);
        }
        // update device information
        dev.update_from_device (new_dev);

        message ("device %s is allowed? %s", dev.device_name, dev.allowed.to_string ());
        // check if device is whitelisted in configuration
        if (!dev.allowed && device_allowed_in_config (dev)) {
            message ("whitelisting device %s via config", dev.device_name);
            dev.allowed = true;
        }

        // auto-allow new devices that haven't been explicitly blocked in config
        if (!from_cache && !dev.allowed && is_new && !device_known_in_config (dev)) {
            message ("auto-allowing new device %s", dev.to_string ());
            dev.allowed = true;
            // persist to config so it stays allowed
            save_device_to_config (dev);
        }

        // update devices cache
        update_cache ();

        if (dev.allowed) {
            // device is allowed
            activate_device (dev);
        } else {
            warning ("skipping device %s activation, device not allowed",
                     dev.to_string ());
        }
    }

    public void handle_incoming_device_connection (DiscoveredDevice discovered_dev, DeviceChannel channel) {
        var new_dev = new Device.from_discovered_device (discovered_dev);
        var is_new = false;
        string unique = new_dev.to_unique_string ();
        message ("handling incoming connection for key: %s", unique);

        if (this.devices.has_key (unique) == false) {
            message ("adding incoming device with key: %s", unique);
            this.devices.@set (unique, new_dev);
            is_new = true;
        } else {
            message ("incoming device %s already present in manager map", unique);
        }

        var dev = this.devices.@get (unique);

        if (dev.is_active) {
            message ("device already active, updating channel to recover from stale session");
        }

        if (is_new) {
            found_new_device (dev);
            dev.capability_added.connect (this.device_capability_added_cb);
            dev.capability_removed.connect (this.device_capability_removed_cb);
        }

        dev.update_from_device (new_dev);

        if (!dev.allowed && device_allowed_in_config (dev)) {
            dev.allowed = true;
        }

        if (!dev.allowed && is_new && !device_known_in_config (dev)) {
            message ("auto-allowing incoming device %s", dev.to_string ());
            dev.allowed = true;
            save_device_to_config (dev);
        }

        update_cache ();

        if (dev.allowed) {
            message ("device %s is allowed, calling activate_with_channel", dev.device_name);
            dev.paired.connect (this.device_paired);
            dev.disconnected.connect (this.device_disconnected);
            dev.activate_with_channel (channel);
        } else {
            warning ("skipping incoming device %s activation, not allowed", dev.to_string ());
            channel.close ();
        }
    }

    private void activate_device (Device dev) {
        var core = Core.instance ();
        if (dev.device_id == core.config.get_uuid ()) {
            debug ("skipping activation of ourselves (%s)", dev.device_id);
            return;
        }
        message ("activating device %s, active: %s", dev.to_string (),
                 dev.is_active.to_string ());

        if (!dev.is_active) {
            dev.paired.connect (this.device_paired);
            dev.disconnected.connect (this.device_disconnected);

            dev.activate ();
        }
    }

    /**
     * device_allowed_in_config:
     * @dev device
     *
     * Returns true if a matching device is enabled via configuration file.
     */
    private bool device_allowed_in_config (Device dev) {
        if (dev.allowed)
            return true;

        var core = Core.instance ();

        var in_config = core.config.is_device_allowed (dev.device_name,
                                                       dev.device_type);
        return in_config;
    }

    /**
     * device_known_in_config:
     * @dev device
     *
     * Returns true if a matching device exists in the configuration file,
     * regardless of its allowed state. Used to prevent auto-allowing
     * devices that were previously explicitly blocked by the user.
     */
    private bool device_known_in_config (Device dev) {
        var core = Core.instance ();
        return core.config.is_device_known (dev.device_name,
                                             dev.device_type);
    }

    private void device_paired (Device dev, bool status) {
        info ("device %s pair status change: %s",
              dev.to_string (), status.to_string ());

        update_cache ();

        if (status == false) {
            // we're no longer interested in paired singnal
            dev.paired.disconnect (this.device_paired);

            // we're not paired anymore, deactivate if needed
            dev.deactivate ();
        }
    }

    private void device_capability_added_cb (Device dev, string cap) {
        info ("capability %s added to device %s", cap, dev.to_string ());

        if (dev.has_capability_handler (cap)) {
            return;
        }

        var core = Core.instance ();
        var h = core.handlers.get_capability_handler (cap);
        if (h != null) {
            dev.register_capability_handler (cap, h);

            device_capability_added (dev, cap, h);
        } else {
            warning ("no handler for capability %s", cap);
        }
    }

    private void device_capability_removed_cb (Device dev, string cap) {
        info ("capability %s removed from device %s", cap, dev.to_string ());
    }

    private void device_disconnected (Device dev) {
        debug ("device %s got disconnected", dev.to_string ());

        // Persist the current paired state before unhooking the signal,
        // so that paired=true survives across daemon restarts.
        update_cache ();

        dev.paired.disconnect (this.device_paired);
        dev.disconnected.disconnect (this.device_disconnected);
    }

    /**
     * allow_device:
     * @path: device object path
     *
     * Allow given device
     */
    public void allow_device (Device dev) {
        dev.allowed = true;

        // persist to config
        save_device_to_config (dev);

        // update device cache
        update_cache ();

        // maybe activate if needed
        activate_device (dev);

        if (dev.is_active && !dev.is_paired) {
            dev.pair.begin ();
        }
    }

    /**
     * disallow_device:
     * @path: device object path
     *
     * Disallow given device
     */
    public void disallow_device (Device dev) {
        dev.allowed = false;
        dev.unpair.begin ();
        dev.deactivate ();

        // persist to config
        var core = Core.instance ();
        string group_name = dev.device_name.replace (" ", "-").down ();
        core.config.add_device (group_name, dev.device_name,
                                 dev.device_type, false);

        // update device cache
        update_cache ();
    }

    /**
     * remove_device:
     * @dev: device to remove
     *
     * Completely remove a device from config and memory.
     * Unlike disallow_device, this forgets the device entirely.
     */
    public void remove_device (Device dev) {
        string unique = dev.to_unique_string ();

        // deactivate if active
        dev.unpair.begin ();
        dev.deactivate ();

        // remove from config
        var core = Core.instance ();
        string group_name = dev.device_name.replace (" ", "-").down ();
        core.config.remove_device (group_name);

        // remove from devices map
        this.devices.unset (unique);

        // update device cache
        update_cache ();

        info ("removed device %s completely", dev.to_string ());
    }

    /**
     * add_custom_device:
     * @address: IP address or hostname of the device
     *
     * Add a custom device address for manual connection.
     */
    public void add_custom_device (string address) {
        if (!custom_devices.contains (address)) {
            custom_devices.add (address);
            debug ("added custom device: %s", address);
        }
    }

    /**
     * remove_custom_device:
     * @address: IP address or hostname to remove
     *
     * Remove a custom device address.
     */
    public void remove_custom_device (string address) {
        custom_devices.remove (address);
        debug ("removed custom device: %s", address);
    }

    /**
     * load_custom_devices:
     *
     * Load custom device addresses from configuration file.
     */
    public void load_custom_devices () {
        var core = Core.instance ();
        try {
            string[] addrs = core.config.get_custom_devices ();
            foreach (string addr in addrs) {
                add_custom_device (addr);
                debug ("loaded custom device from config: %s", addr);
            }
        } catch (Error e) {
            debug ("no custom devices in config: %s", e.message);
        }
    }

    /**
     * reload_config:
     *
     * Called when the configuration file changes externally. Reloads custom device
     * definitions from the configuration. Additional handling for updated device
     * permissions could be added here.
     */
    public void reload_config () {
        // Refresh custom devices from config file
        load_custom_devices ();
    }

    /**
     * save_device_to_config:
     * @dev: device to save
     *
     * Persist a device entry to the config file so it stays allowed
     * across daemon restarts.
     */
    private void save_device_to_config (Device dev) {
        var core = Core.instance ();
        string group_name = dev.device_name.replace (" ", "-").down ();
        core.config.add_device (group_name, dev.device_name,
                                 dev.device_type, true);
    }
}