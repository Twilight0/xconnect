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

class ClipboardHandler : Object, PacketHandlerInterface {

    public const string CLIPBOARD = "kdeconnect.clipboard";
    public const string CLIPBOARD_CONNECT = "kdeconnect.clipboard.connect";
    public const string CLIPBOARD_FILE = "kdeconnect.clipboard.file";

    public string get_pkt_type () {
        return CLIPBOARD;
    }

    private ClipboardHandler () {
    }

    public static ClipboardHandler instance () {
        return new ClipboardHandler ();
    }

    public void use_device (Device dev) {
        debug ("use device %s for Clipboard sharing", dev.to_string ());
        dev.message.connect (this.message);
    }

    public void release_device (Device dev) {
        debug ("release device %s", dev.to_string ());
        dev.message.disconnect (this.message);
    }

    public void message (Device dev, Packet pkt) {
        if (pkt.pkt_type != CLIPBOARD &&
            pkt.pkt_type != CLIPBOARD_CONNECT &&
            pkt.pkt_type != CLIPBOARD_FILE) {
            return;
        }

        if (pkt.pkt_type == CLIPBOARD_CONNECT) {
            // Sent on initial connection with timestamp
            debug ("clipboard connect from device %s", dev.to_string ());
            if (pkt.body.has_member ("content")) {
                string text = pkt.body.get_string_member ("content");
                clipboard_text_received (dev, text);
            }
            return;
        }

        if (pkt.pkt_type == CLIPBOARD_FILE) {
            // File clipboard transfer with binary payload
            debug ("clipboard file from device %s", dev.to_string ());
            handle_clipboard_file (dev, pkt);
            return;
        }

        // Regular clipboard text
        if (pkt.body.has_member ("content")) {
            string text = pkt.body.get_string_member ("content");
            debug ("got clipboard text '%s'", text);
            clipboard_text_received (dev, text);
            var display = Gdk.Display.get_default ();
            if (display != null) {
                var cb = Gtk.Clipboard.get_default (display);
                cb.set_text (text, -1);
                Utils.show_own_notification ("Text copied to clipboard",
                                             dev.device_name);
            }
        }
    }

    private void handle_clipboard_file (Device dev, Packet pkt) {
        if (pkt.payload == null) {
            warning ("clipboard file missing payload");
            return;
        }

        string filename = "clipboard_file";
        if (pkt.body.has_member ("filename")) {
            filename = pkt.body.get_string_member ("filename");
        }

        var downloaddir = Environment.get_user_special_dir (UserDirectory.DOWNLOAD);
        if (downloaddir == null) {
            downloaddir = Path.build_filename (Environment.get_home_dir (), "Downloads");
        }
        var dest_dir = Path.build_filename (downloaddir, "xconnect");
        DirUtils.create_with_parents (dest_dir, 0700);
        var dest_path = Path.build_filename (dest_dir, filename);

        debug ("receiving clipboard file: %s size: %s",
               filename, format_size (pkt.payload.size));

        var t = new DownloadTransfer (
            dev,
            new InetSocketAddress (dev.host,
                                   (uint16) pkt.payload.port),
            pkt.payload.size,
            dest_path);

        Core.instance ().transfer_manager.push_job (t);

        t.finished.connect (() => {
            clipboard_file_received (dev, dest_path);
            Utils.show_own_notification ("Clipboard file received: " + filename,
                                         dev.device_name);
        });

        t.start_async.begin ();
    }

    /**
     * Send clipboard text to device
     */
    public void send_clipboard_text (Device dev, string text) {
        var builder = new Json.Builder ();
        builder.begin_object ();
        builder.set_member_name ("content");
        builder.add_string_value (text);
        builder.end_object ();

        var pkt = new Packet (CLIPBOARD, builder.get_root ().get_object ());
        dev.send (pkt);
    }

    public signal void clipboard_text_received (Device dev, string text);
    public signal void clipboard_file_received (Device dev, string path);
}
