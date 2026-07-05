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

[DBus (name = "org.xconnect.Device.SystemVolume")]
class SystemVolumeHandlerProxy : Object, PacketHandlerInterfaceProxy {

    private Device device = null;
    private SystemVolumeHandler handler = null;
    private uint register_id = 0;
    private DBusPropertyNotifier prop_notifier = null;

    public SystemVolumeHandlerProxy.for_device_handler (Device dev,
                                                         PacketHandlerInterface iface) {
        this.device = dev;
        this.handler = (SystemVolumeHandler) iface;
    }

    public void send_volume (string sink_name, int volume, bool muted) throws Error {
        this.handler.send_volume (this.device, sink_name, volume, muted);
    }

    public void send_max_volume (int max_volume) throws Error {
        this.handler.send_max_volume (this.device, max_volume);
    }

    [DBus (visible = false)]
    public void bus_register (DBusConnection conn, string path) throws IOError {
        if (this.register_id == 0)
            this.register_id = conn.register_object (path, this);

        this.prop_notifier = new DBusPropertyNotifier (conn,
                                                        "org.xconnect.Device.SystemVolume",
                                                        path);
    }

    [DBus (visible = false)]
    public void bus_unregister (DBusConnection conn) throws IOError {
        if (this.register_id != 0)
            conn.unregister_object (this.register_id);
        this.register_id = 0;
    }
}
