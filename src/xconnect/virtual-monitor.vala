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

/**
 * VirtualMonitorHandler:
 *
 * Handles kdeconnect.virtualmonitor and kdeconnect.virtualmonitor.request packets.
 * Allows creating a virtual monitor on the desktop that the phone can connect to
 * via RDP/VNC for screen mirroring.
 *
 * Note: This is a stub handler. Full implementation requires RDP server integration
 * (e.g., krdpserver or x11vnc).
 */
class VirtualMonitorHandler : Object, PacketHandlerInterface {

    public const string VIRTUALMONITOR = "kdeconnect.virtualmonitor";
    public const string VIRTUALMONITOR_REQUEST = "kdeconnect.virtualmonitor.request";

    public string get_pkt_type () {
        return VIRTUALMONITOR_REQUEST;
    }

    private VirtualMonitorHandler () {
    }

    public static VirtualMonitorHandler instance () {
        return new VirtualMonitorHandler ();
    }

    public void use_device (Device dev) {
        debug ("use device %s for virtual monitor", dev.to_string ());
        dev.message.connect (this.message);
    }

    public void release_device (Device dev) {
        debug ("release device %s", dev.to_string ());
        dev.message.disconnect (this.message);
    }

    private void message (Device dev, Packet pkt) {
        if (pkt.pkt_type != VIRTUALMONITOR && pkt.pkt_type != VIRTUALMONITOR_REQUEST) {
            return;
        }

        debug ("got virtual monitor packet: %s", pkt.pkt_type);

        if (pkt.pkt_type == VIRTUALMONITOR_REQUEST) {
            // Phone requests a virtual monitor to be created
            int64 width = 1920;
            int64 height = 1080;

            if (pkt.body.has_member ("width")) {
                width = pkt.body.get_int_member ("width");
            }
            if (pkt.body.has_member ("height")) {
                height = pkt.body.get_int_member ("height");
            }

            virtual_monitor_requested (dev, (int) width, (int) height);
        }
    }

    /**
     * Notify the device about a virtual monitor being available
     */
    public void send_virtual_monitor_created (Device dev, string host,
                                               int port, string password) {
        var builder = new Json.Builder ();
        builder.begin_object ();
        builder.set_member_name ("host");
        builder.add_string_value (host);
        builder.set_member_name ("port");
        builder.add_int_value (port);
        if (password != null && password.length > 0) {
            builder.set_member_name ("password");
            builder.add_string_value (password);
        }
        builder.end_object ();

        var pkt = new Packet (VIRTUALMONITOR, builder.get_root ().get_object ());
        dev.send (pkt);
    }

    public signal void virtual_monitor_requested (Device dev, int width, int height);
}
