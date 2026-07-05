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
 * SystemVolumeHandler:
 *
 * Handles kdeconnect.systemvolume and kdeconnect.systemvolume.request packets.
 * Allows controlling the desktop's audio volume from the phone.
 */
class SystemVolumeHandler : Object, PacketHandlerInterface {

    public const string SYSTEMVOLUME = "kdeconnect.systemvolume";
    public const string SYSTEMVOLUME_REQUEST = "kdeconnect.systemvolume.request";

    public string get_pkt_type () {
        return SYSTEMVOLUME_REQUEST;
    }

    private SystemVolumeHandler () {
    }

    public static SystemVolumeHandler instance () {
        return new SystemVolumeHandler ();
    }

    public void use_device (Device dev) {
        debug ("use device %s for system volume", dev.to_string ());
        dev.message.connect (this.message);
    }

    public void release_device (Device dev) {
        debug ("release device %s", dev.to_string ());
        dev.message.disconnect (this.message);
    }

    private void message (Device dev, Packet pkt) {
        if (pkt.pkt_type != SYSTEMVOLUME && pkt.pkt_type != SYSTEMVOLUME_REQUEST) {
            return;
        }

        debug ("got system volume packet: %s", pkt.pkt_type);

        if (pkt.pkt_type == SYSTEMVOLUME_REQUEST) {
            // Phone requests volume change
            if (pkt.body.has_member ("name") && pkt.body.has_member ("volume")) {
                string sink_name = pkt.body.get_string_member ("name");
                int64 volume = pkt.body.get_int_member ("volume");
                volume_change_requested (dev, sink_name, (int) volume);
            } else if (pkt.body.has_member ("name") && pkt.body.has_member ("muted")) {
                string sink_name = pkt.body.get_string_member ("name");
                bool muted = pkt.body.get_boolean_member ("muted");
                mute_change_requested (dev, sink_name, muted);
            }
        }
    }

    /**
     * Send current volume state to device
     */
    public void send_volume (Device dev, string sink_name, int volume, bool muted) {
        var builder = new Json.Builder ();
        builder.begin_object ();
        builder.set_member_name ("name");
        builder.add_string_value (sink_name);
        builder.set_member_name ("volume");
        builder.add_int_value (volume);
        builder.set_member_name ("muted");
        builder.add_boolean_value (muted);
        builder.end_object ();

        var pkt = new Packet (SYSTEMVOLUME, builder.get_root ().get_object ());
        dev.send (pkt);
    }

    /**
     * Send max volume to device
     */
    public void send_max_volume (Device dev, int max_volume) {
        var builder = new Json.Builder ();
        builder.begin_object ();
        builder.set_member_name ("maxVolume");
        builder.add_int_value (max_volume);
        builder.end_object ();

        var pkt = new Packet (SYSTEMVOLUME, builder.get_root ().get_object ());
        dev.send (pkt);
    }

    public signal void volume_change_requested (Device dev, string sink_name, int volume);
    public signal void mute_change_requested (Device dev, string sink_name, bool muted);
}
