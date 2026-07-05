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
 * PresenterHandler:
 *
 * Handles kdeconnect.presenter packets.
 * Allows using the phone as a presentation remote control.
 */
class PresenterHandler : Object, PacketHandlerInterface {

    public const string PRESENTER = "kdeconnect.presenter";

    public string get_pkt_type () {
        return PRESENTER;
    }

    private PresenterHandler () {
    }

    public static PresenterHandler instance () {
        return new PresenterHandler ();
    }

    public void use_device (Device dev) {
        debug ("use device %s for presenter", dev.to_string ());
        dev.message.connect (this.message);
    }

    public void release_device (Device dev) {
        debug ("release device %s", dev.to_string ());
        dev.message.disconnect (this.message);
    }

    private void message (Device dev, Packet pkt) {
        if (pkt.pkt_type != PRESENTER) {
            return;
        }

        debug ("got presenter packet");

        if (pkt.body.has_member ("dx") || pkt.body.has_member ("dy")) {
            double dx = 0;
            double dy = 0;
            if (pkt.body.has_member ("dx"))
                dx = pkt.body.get_double_member ("dx");
            if (pkt.body.has_member ("dy"))
                dy = pkt.body.get_double_member ("dy");
            pointer_move (dev, dx, dy);
        } else if (pkt.body.has_member ("start")) {
            start_presenter (dev);
        } else if (pkt.body.has_member ("stop")) {
            stop_presenter (dev);
        }
    }

    public signal void pointer_move (Device dev, double dx, double dy);
    public signal void start_presenter (Device dev);
    public signal void stop_presenter (Device dev);
}
