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
 */

[DBus (name = "org.xconnect.Device.LockDevice")]
class LockDeviceHandlerProxy : Object, PacketHandlerInterfaceProxy {

    private Device device = null;
    private LockDeviceHandler handler = null;
    private uint register_id = 0;
    private DBusPropertyNotifier prop_notifier = null;

    public bool is_locked {
        get; private set; default = false;
    }

    public LockDeviceHandlerProxy.for_device_handler (Device dev,
                                                       PacketHandlerInterface iface) {
        this.device = dev;
        this.handler = (LockDeviceHandler) iface;
        this.handler.lock_state_changed.connect (this.on_lock_state_changed);
    }

    private void on_lock_state_changed (Device dev, bool is_locked) {
        if (this.device != dev)
            return;

        this.is_locked = is_locked;
    }

    public void set_locked (bool lock) throws Error {
        this.handler.send_lock_request (this.device, lock);
    }

    public void send_lock_state (bool is_locked) throws Error {
        this.handler.send_lock_state (this.device, is_locked);
    }

    [DBus (visible = false)]
    public void bus_register (DBusConnection conn, string path) throws IOError {
        if (this.register_id == 0)
            this.register_id = conn.register_object (path, this);

        this.prop_notifier = new DBusPropertyNotifier (conn,
                                                        "org.xconnect.Device.LockDevice",
                                                        path);

        this.notify.connect (this.send_property_change);
    }

    [DBus (visible = false)]
    public void bus_unregister (DBusConnection conn) throws IOError {
        if (this.register_id != 0)
            conn.unregister_object (this.register_id);
        this.register_id = 0;

        this.notify.disconnect (this.send_property_change);
    }

    private void send_property_change (ParamSpec p) {
        assert (this.prop_notifier != null);

        Variant v = null;

        if (p.name == "is-locked") {
            v = this.is_locked;
        }

        if (v == null)
            return;

        this.prop_notifier.queue_property_change (p.name, v);
    }
}
