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
 * ScreensaverInhibitHandler:
 *
 * Handles kdeconnect.screensaver.inhibit packets.
 * When the phone screen is on, inhibit the desktop screensaver.
 */
class ScreensaverInhibitHandler : Object, PacketHandlerInterface {

    public const string SCREENSAVER_INHIBIT = "kdeconnect.screensaver.inhibit";

    public string get_pkt_type () {
        return SCREENSAVER_INHIBIT;
    }

    private ScreensaverInhibitHandler () {
    }

    public static ScreensaverInhibitHandler instance () {
        return new ScreensaverInhibitHandler ();
    }

    public void use_device (Device dev) {
        debug ("use device %s for screensaver inhibit", dev.to_string ());
        dev.message.connect (this.message);
    }

    public void release_device (Device dev) {
        debug ("release device %s", dev.to_string ());
        dev.message.disconnect (this.message);
    }

    private void message (Device dev, Packet pkt) {
        if (pkt.pkt_type != SCREENSAVER_INHIBIT) {
            return;
        }

        debug ("got screensaver inhibit packet");

        // The packet body may contain "suppress" boolean
        // If true, inhibit screensaver; if false, uninhibit
        bool suppress = true;
        if (pkt.body.has_member ("suppress")) {
            suppress = pkt.body.get_boolean_member ("suppress");
        }

        screensaver_inhibit_changed (dev, suppress);
    }

    /**
     * Send inhibit/uninhibit command to device
     */
    public void send_inhibit (Device dev, bool inhibit) {
        var builder = new Json.Builder ();
        builder.begin_object ();
        builder.set_member_name ("suppress");
        builder.add_boolean_value (inhibit);
        builder.end_object ();

        var pkt = new Packet (SCREENSAVER_INHIBIT, builder.get_root ().get_object ());
        dev.send (pkt);
    }

    public signal void screensaver_inhibit_changed (Device dev, bool suppress);
}
