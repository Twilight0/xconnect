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

[DBus (name = "org.xconnect.Device.Notifications")]
class NotificationHandlerProxy : Object, PacketHandlerInterfaceProxy {

    private Device device = null;
    private NotificationHandler handler = null;
    private uint register_id = 0;

    public signal void notification_received (string id, string app,
                                               string title, string? icon_path);

    public signal void notification_cancelled (string id);

    public NotificationHandlerProxy.for_device_handler (Device dev,
                                                         PacketHandlerInterface iface) {
        this.device = dev;
        this.handler = (NotificationHandler) iface;
        this.handler.notification_received.connect (this.on_notification_received);
        this.handler.notification_cancelled.connect (this.on_notification_cancelled);
    }

    private void on_notification_received (Device dev, string id, string app,
                                            string title, string? icon_path) {
        if (this.device != dev)
            return;
        notification_received (id, app, title, icon_path);
    }

    private void on_notification_cancelled (Device dev, string id) {
        if (this.device != dev)
            return;
        notification_cancelled (id);
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
