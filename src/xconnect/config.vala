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
public class Config : Object {

    public const string FILE = "xconnect.conf";

    private KeyFile _kf = null;

    public string path {
        get; private set; default = null;
    }

    public static string[] config_search_dirs (string primary_dir) {
        string[] dirs = { primary_dir };

        string[] sysdirs = Environment.get_system_data_dirs ();
        foreach (string d in sysdirs) {
            dirs += Path.build_path (Path.DIR_SEPARATOR_S,
                                     d, "xconnect");
        }
        return dirs;
    }

    public Config (string base_config_dir) {

        _kf = new KeyFile ();
        string[] dirs = config_search_dirs (base_config_dir);
        string full_path = null;

        foreach (string d in dirs) {
            debug ("config search dir: %s", d);
        }

        try {
            bool found = _kf.load_from_dirs (Config.FILE, dirs,
                                             out full_path,
                                             KeyFileFlags.KEEP_COMMENTS);
            path = full_path;
            if (found == false) {
                critical ("configuration file %s was not found",
                          Config.FILE);
            }
            message ("loaded configuration from %s", full_path);
        } catch (KeyFileError ke) {
            critical ("failed to parse configuration file: %s", ke.message);
        } catch (FileError fe) {
            critical ("failed to read configuration file: %s", fe.message);
        }
    }

    public void save () {
        string user_config_path = Path.build_filename (
            Environment.get_user_config_dir (), "xconnect", FILE);
        dump_to_file (user_config_path);
    }

    /**
     * reload:
     *
     * Re‑read the configuration file from disk, updating the internal KeyFile.
     */
    public void reload () {
        if (path == null) {
            warning ("config path is null, cannot reload");
            return;
        }
        try {
            _kf = new KeyFile ();
            _kf.load_from_file (path, KeyFileFlags.KEEP_COMMENTS);
            info ("reloaded configuration from %s", path);
        } catch (Error e) {
            warning ("failed to reload configuration from %s: %s", path, e.message);
        }
    }

    public void dump_to_file (string path) {
        if (_kf == null)
            return;

        string data = _kf.to_data ();
        try {
            FileUtils.set_contents (path, data);
        } catch (FileError e) {
            critical ("failed to save configuration to %s: %s",
                      path, e.message);
        }
    }

    public string[] list_commands () {
        if (_kf.has_group("commands")) {
            return _kf.get_keys("commands");
        } else {
            return {};
        }
    }

    public string get_command (string key) {
        return _kf.get_string("commands", key);
    }

    public bool is_device_allowed (string name, string type) {

        debug ("check if device %s type %s is allowed", name, type);
        try {
            string[] devices = _kf.get_string_list ("main", "devices");

            foreach (string dev in devices) {
                debug ("checking dev %s", dev);
                //
                if (_kf.has_group (dev) == false) {
                    debug ("no group %s", dev);
                    continue;
                }

                if (_kf.get_string (dev, "name") == name &&
                    _kf.get_string (dev, "type") == type &&
                    _kf.get_boolean (dev, "allowed") == true) {
                    return true;
                }
            }
        } catch (KeyFileError ke) {
            critical ("failed to read entries from configuration file: %s",
                      ke.message);
        }
        return false;
    }

    /**
     * is_device_known:
     * @name: device display name
     * @type: device type (phone, tablet, etc.)
     *
     * Returns true if the device exists in the config file at all,
     * regardless of its allowed state. Used to prevent auto-allowing
     * devices that were previously explicitly blocked.
     */
    public bool is_device_known (string name, string type) {
        try {
            if (!_kf.has_group ("main") || !_kf.has_key ("main", "devices"))
                return false;

            string[] devices = _kf.get_string_list ("main", "devices");

            foreach (string dev in devices) {
                if (_kf.has_group (dev) == false)
                    continue;

                if (_kf.get_string (dev, "name") == name &&
                    _kf.get_string (dev, "type") == type) {
                    return true;
                }
            }
        } catch (KeyFileError ke) {
            // not found
        }
        return false;
    }

    public bool is_debug_on () {
        try {
            bool debug = _kf.get_boolean ("main", "debug");
            return debug;
        } catch (KeyFileError ke) {
            critical ("failed to read config entry");
        }
        return false;
    }

    public string[] get_custom_devices () throws Error {
        if (_kf.has_group ("main") && _kf.has_key ("main", "custom_devices")) {
            return _kf.get_string_list ("main", "custom_devices");
        }
        return {};
    }

    public string get_uuid () {
        try {
            if (_kf.has_group ("main") && _kf.has_key ("main", "uuid")) {
                return _kf.get_string ("main", "uuid");
            }
        } catch (Error e) { }
        return "";
    }

    public void set_uuid (string uuid) {
        _kf.set_string ("main", "uuid", uuid);
    }

    public string get_name () {
        try {
            if (_kf.has_group ("main") && _kf.has_key ("main", "name")) {
                return _kf.get_string ("main", "name");
            }
        } catch (Error e) { }
        return "";
    }

    public void set_name (string name) {
        _kf.set_string ("main", "name", name);
    }

    public uint16 get_udp_port () {
        try {
            if (_kf.has_group ("main") && _kf.has_key ("main", "udp_port")) {
                return (uint16) _kf.get_integer ("main", "udp_port");
            }
        } catch (Error e) {}
        return 1716;
    }

    public void set_udp_port (uint16 port) {
        _kf.set_integer ("main", "udp_port", port);
    }

    public uint16 get_tcp_port () {
        try {
            if (_kf.has_group ("main") && _kf.has_key ("main", "tcp_port")) {
                return (uint16) _kf.get_integer ("main", "tcp_port");
            }
        } catch (Error e) {}
        return 1716;
    }

    public void set_tcp_port (uint16 port) {
        _kf.set_integer ("main", "tcp_port", port);
    }

    public bool has_key (string group, string key) {
        return _kf.has_group (group) && _kf.has_key (group, key);
    }

    /**
     * add_device:
     * @group_name: config group name for the device
     * @name: device name
     * @type: device type (phone, tablet, etc.)
     * @allowed: whether device is allowed
     *
     * Add or update a device entry in the config file.
     */
    public void add_device (string group_name, string name, string type, bool allowed, bool paired = false) {
        try {
            // Get current device list
            string[] devices = {};
            if (_kf.has_group ("main") && _kf.has_key ("main", "devices")) {
                devices = _kf.get_string_list ("main", "devices");
            }

            // Add to list if not present
            bool found = false;
            foreach (string d in devices) {
                if (d == group_name) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                devices += group_name;
                _kf.set_string_list ("main", "devices", devices);
            }

            // Set device properties
            _kf.set_string (group_name, "name", name);
            _kf.set_string (group_name, "type", type);
            _kf.set_boolean (group_name, "allowed", allowed);
            _kf.set_boolean (group_name, "paired", paired);

            // Write back to file
            save ();
            info ("saved device %s (allowed=%s, paired=%s) to config", name, allowed.to_string (), paired.to_string ());
        } catch (Error e) {
            warning ("failed to save device to config: %s", e.message);
        }
    }

    public bool is_device_paired (string name, string type) {
        try {
            if (!_kf.has_group ("main") || !_kf.has_key ("main", "devices"))
                return false;

            string[] devices = _kf.get_string_list ("main", "devices");

            foreach (string dev in devices) {
                if (_kf.has_group (dev) == false)
                    continue;

                if (_kf.get_string (dev, "name") == name &&
                    _kf.get_string (dev, "type") == type) {
                    if (_kf.has_key (dev, "paired")) {
                        return _kf.get_boolean (dev, "paired");
                    }
                }
            }
        } catch (KeyFileError ke) { }
        return false;
    }

    /**
     * remove_device:
     * @group_name: config group name to remove
     *
     * Remove a device entry completely from the config file.
     */
    public void remove_device (string group_name) {
        try {
            string[] devices = {};
            if (_kf.has_group ("main") && _kf.has_key ("main", "devices")) {
                devices = _kf.get_string_list ("main", "devices");
            }

            string[] new_devices = {};
            foreach (string d in devices) {
                if (d != group_name) {
                    new_devices += d;
                }
            }
            _kf.set_string_list ("main", "devices", new_devices);

            if (_kf.has_group (group_name)) {
                _kf.remove_group (group_name);
            }

            save ();
            info ("removed device group %s from config", group_name);
        } catch (Error e) {
            warning ("failed to remove device from config: %s", e.message);
        }
    }

    /**
     * set_device_allowed:
     * @group_name: device config group
     * @allowed: new allowed state
     *
     * Update the allowed state of a device in the config.
     */
    public void set_device_allowed (string group_name, bool allowed) {
        if (_kf.has_group (group_name)) {
            _kf.set_boolean (group_name, "allowed", allowed);
            save ();
        }
    }

    public string get_downloads_dir () {
        try {
            if (_kf.has_group ("main") && _kf.has_key ("main", "downloads_dir")) {
                return _kf.get_string ("main", "downloads_dir");
            }
        } catch (Error e) {}
        return "";
    }

    public void set_downloads_dir (string dir) {
        _kf.set_string ("main", "downloads_dir", dir);
        save ();
    }
}
