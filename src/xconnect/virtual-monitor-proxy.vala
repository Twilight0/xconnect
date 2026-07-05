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

[DBus (name = "org.xconnect.Device.VirtualMonitor")]
class VirtualMonitorHandlerProxy : Object, PacketHandlerInterfaceProxy {

    private Device device = null;
    private VirtualMonitorHandler handler = null;
    private uint register_id = 0;

    public VirtualMonitorHandlerProxy.for_device_handler (Device dev,
                                                           PacketHandlerInterface iface) {
        this.device = dev;
        this.handler = (VirtualMonitorHandler) iface;
    }

    public void send_virtual_monitor_created (string host, int port,
                                               string password) throws Error {
        this.handler.send_virtual_monitor_created (this.device, host, port, password);
    }

    [DBus (visible = false)]
    public void bus_register (DBusConnection conn, string path) throws IOError {
        if (this.register_id == 0)
            this.register_id = conn.register_object (path, this);
    }

    [DBus (visible = false)]
    public void bus_unregister (DBusConnection conn) throws IOError {
        if (this.register_id != 0)
            conn.unregister_object (this.register_id);
        this.register_id = 0;
    }
}
