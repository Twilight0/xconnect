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

/**
 * General device wrapper.
 */
[DBus (name = "org.xconnect.Device")]
public class DeviceDBusProxy : Object {

    public string id {
        get {
            return device.device_id;
        }
        private set {
        }
    }
    public string name {
        get {
            return device.device_name;
        }
        private set {
        }
    }
    public string device_type {
        get {
            return device.device_type;
        }
        private set {
        }
    }
    public uint protocol_version {
        get {
            return device.protocol_version;
        }
        private set {
        }
    }
    public string address {
        get; private set; default = "";
    }

    public bool is_paired {
        get {
            return device.is_paired;
        }
        private set {
        }
    }
    public bool allowed {
        get {
            return device.allowed;
        }
        private set {
        }
    }
    public bool is_active {
        get {
            return device.is_active;
        }
        private set {
        }
    }
    public bool is_connected {
        get; private set;
    }

    public string[] incoming_capabilities {
        get;
        private set;
    }

    public string[] outgoing_capabilities {
        get;
        private set;
    }

    public string certificate {
        owned get {
            return device.certificate_pem;
        }
        private set {
        }
    }

    public string certificate_fingerprint {
        get {
            return device.certificate_fingerprint;
        }
        private set {
        }
    }

    public signal void pair_requested (string fingerprint);

    private HashMap<string, PacketHandlerInterfaceProxy> handlers;

    private uint register_id = 0;

    private DBusPropertyNotifier prop_notifier = null;

    [DBus (visible = false)]
    public ObjectPath object_path = null;

    [DBus (visible = false)]
    public Device device {
        get; private set; default = null;
    }

    public DeviceDBusProxy.for_device_with_path (Device device, ObjectPath path) {
        this.device = device;
        this.object_path = path;
        this.handlers = new HashMap<string, PacketHandlerInterfaceProxy>();
        this.update_address ();
        this.update_capabilities ();
        this.device.notify.connect (this.param_changed);
        this.device.connected.connect (() => {
            this.is_connected = true;
        });
        this.device.disconnected.connect (() => {
            this.is_connected = false;
        });
        this.device.pair_requested.connect ((f) => {
            this.pair_requested (f);
        });
        this.notify.connect (this.update_properties);
    }

    private void update_capabilities () {
        string[] caps = {};

        foreach (var cap in device.incoming_capabilities) {
            caps += cap;
        }
        this.incoming_capabilities = caps;

        caps = {};

        foreach (var cap in device.outgoing_capabilities) {
            caps += cap;
        }
        this.outgoing_capabilities = caps;
    }

    private void update_address () {
        this.address = "%s:%u".printf (device.host.to_string (),
                                       device.tcp_port);
    }

    private void update_properties (ParamSpec param) {
        debug ("param %s changed", param.name);

        string name = param.name;
        Variant v = null;
        switch (param.name) {
        case "address":
            v = this.address;
            break;
        case "id":
            v = this.id;
            break;
        case "name":
            v = this.name;
            break;
        case "device-type":
            name = "DeviceType";
            v = this.device_type;
            break;
        case "potocol-version":
            name = "ProtocolVersion";
            v = this.protocol_version;
            break;
        case "is-paired":
            name = "IsPaired";
            v = this.is_paired;
            break;
        case "allowed":
            v = this.allowed;
            break;
        case "is-active":
            name = "IsActive";
            v = this.is_active;
            break;
        case "is-connected":
            name = "IsConnected";
            v = this.is_connected;
            break;
        case "certificate":
            name = "certificate";
            v = this.certificate;
            break;
        }

        if (v == null)
            return;

        this.prop_notifier.queue_property_change (name, v);
    }

    private void param_changed (ParamSpec param) {
        debug ("parameter %s changed", param.name);
        switch (param.name) {
        case "host":
        case "tcp-port":
            this.update_address ();
            break;
        case "allowed":
            this.notify_property ("allowed");
            break;
        case "is-active":
            this.notify_property ("is-active");
            break;
        case "is-paired":
            this.notify_property ("is-paired");
            break;
        case "incoming-capabilities":
        case "outgoing-capabilities":
            this.update_capabilities ();
            break;
        }
    }

    [DBus (visible = false)]
    public bool has_handler (string cap) {
        return this.handlers.has_key (cap);
    }

    /**
     * pair:
     *
     * Send a pairing request to this device
     */
    public void pair () throws Error {
        GLib.message ("DeviceDBusProxy.pair() called for device %s", this.device.device_name);
        this.device.allowed = true;
        // initiate_pair sets _pair_pending_send = true and the shared timestamp.
        this.device.initiate_pair ();
        this.device.maybe_pair ();
        if (!this.device.is_active) {
            GLib.message ("pair(): device %s not active, initiating connection...",
                          this.device.device_name);
            this.device.activate ();
        }
    }

    public void accept_pair () throws Error {
        this.device.accept_pair.begin ();
    }

    public void reject_pair () throws Error {
        this.device.reject_pair.begin ();
    }

    /**
     * get_verification_key:
     *
     * Returns the pairing verification key, computed live (not cached),
     * since its value depends on the current pairing timestamp and would
     * be stale if exposed as a plain D-Bus property (GDBusProxy caches
     * property values client-side and only updates them via
     * PropertiesChanged signals, which we don't emit for this).
     */
    public string get_verification_key () throws Error {
        return this.device.verification_key;
    }

    [DBus (visible = false)]
    public void bus_register (DBusConnection conn) {
        try {
            this.register_id = conn.register_object (this.object_path, this);
            GLib.message ("device %s registered on D-Bus at %s (id=%u)",
                  this.device.to_string (), this.object_path.to_string (),
                  this.register_id);
            this.prop_notifier = new DBusPropertyNotifier (conn,
                                                            "org.xconnect.Device",
                                                            this.object_path);
        } catch (IOError err) {
            warning ("failed to register DBus object for device %s under path %s: %s",
                     this.device.to_string (), this.object_path.to_string (),
                     err.message);
        }
    }

    [DBus (visible = false)]
    public void bus_unregister (DBusConnection conn) {
        if (this.register_id != 0) {
            conn.unregister_object (this.register_id);
        }
        this.register_id = 0;
        this.prop_notifier = null;
    }

    [DBus (visible = false)]
    public void bus_register_handler (DBusConnection conn,
                                      string cap,
                                      PacketHandlerInterfaceProxy handler) throws Error {

        handler.bus_register (conn, this.object_path);
        this.handlers.@set (cap, handler);
    }

    [DBus (visible = false)]
    public void bus_unregister_handler (DBusConnection conn,
                                        string cap) throws Error {
        PacketHandlerInterfaceProxy handler;

        this.handlers.@unset (cap, out handler);
        if (handler != null) {
            handler.bus_unregister (conn);
        }
    }
}
