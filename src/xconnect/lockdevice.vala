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
 * LockDeviceHandler:
 *
 * Handles kdeconnect.lock and kdeconnect.lock.request packets.
 * Allows locking/unlocking the desktop from the phone and vice versa.
 */
class LockDeviceHandler : Object, PacketHandlerInterface {

    public const string LOCK = "kdeconnect.lock";
    public const string LOCK_REQUEST = "kdeconnect.lock.request";

    public string get_pkt_type () {
        return LOCK_REQUEST;
    }

    private LockDeviceHandler () {
    }

    public static LockDeviceHandler instance () {
        return new LockDeviceHandler ();
    }

    public void use_device (Device dev) {
        debug ("use device %s for lock device", dev.to_string ());
        dev.message.connect (this.message);
    }

    public void release_device (Device dev) {
        debug ("release device %s", dev.to_string ());
        dev.message.disconnect (this.message);
    }

    private void message (Device dev, Packet pkt) {
        if (pkt.pkt_type != LOCK && pkt.pkt_type != LOCK_REQUEST) {
            return;
        }

        debug ("got lock packet: %s", pkt.pkt_type);

        if (pkt.pkt_type == LOCK_REQUEST) {
            // Phone requests us to lock/unlock
            if (pkt.body.has_member ("setLocked")) {
                bool should_lock = pkt.body.get_boolean_member ("setLocked");
                lock_requested (dev, should_lock);
            }
        } else if (pkt.pkt_type == LOCK) {
            // Phone reports its lock state
            if (pkt.body.has_member ("isLocked")) {
                bool is_locked = pkt.body.get_boolean_member ("isLocked");
                lock_state_changed (dev, is_locked);
            }
        }
    }

    /**
     * Send lock/unlock command to device
     */
    public void send_lock_request (Device dev, bool lock) {
        var builder = new Json.Builder ();
        builder.begin_object ();
        builder.set_member_name ("setLocked");
        builder.add_boolean_value (lock);
        builder.end_object ();

        var pkt = new Packet (LOCK_REQUEST, builder.get_root ().get_object ());
        dev.send (pkt);
    }

    /**
     * Report our lock state to device
     */
    public void send_lock_state (Device dev, bool is_locked) {
        var builder = new Json.Builder ();
        builder.begin_object ();
        builder.set_member_name ("isLocked");
        builder.add_boolean_value (is_locked);
        builder.end_object ();

        var pkt = new Packet (LOCK, builder.get_root ().get_object ());
        dev.send (pkt);
    }

    public signal void lock_requested (Device dev, bool should_lock);
    public signal void lock_state_changed (Device dev, bool is_locked);
}
