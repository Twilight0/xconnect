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

    // Clipboard polling interval in milliseconds
    private const uint POLL_INTERVAL_MS = 1500;

    // Per-device state for outbound clipboard monitoring
    private Gee.HashMap<string, uint> _poll_sources;     // device_id → GLib source id
    private Gee.HashMap<string, string> _last_sent;      // device_id → last text sent to device
    private Gee.HashSet<Device> _active_devices;

    public string get_pkt_type () {
        return CLIPBOARD;
    }

    private ClipboardHandler () {
        _poll_sources = new Gee.HashMap<string, uint> ();
        _last_sent = new Gee.HashMap<string, string> ();
        _active_devices = new Gee.HashSet<Device> ();
    }

    public static ClipboardHandler instance () {
        return new ClipboardHandler ();
    }

    public void use_device (Device dev) {
        debug ("use device %s for Clipboard sharing", dev.to_string ());
        dev.message.connect (this.message);
        _active_devices.add (dev);
        _start_poll (dev);
    }

    public void release_device (Device dev) {
        debug ("release device %s", dev.to_string ());
        dev.message.disconnect (this.message);
        _stop_poll (dev);
        _active_devices.remove (dev);
    }

    // ── Outbound clipboard polling ──────────────────────────────────

    private void _start_poll (Device dev) {
        string id = dev.device_id;
        _stop_poll (dev);   // cancel any stale source first

        // Seed last_sent with current clipboard so we don't spam on connect
        _last_sent[id] = _read_clipboard ();

        uint src = GLib.Timeout.add (POLL_INTERVAL_MS, () => {
            _poll_tick (dev);
            return GLib.Source.CONTINUE;
        });
        _poll_sources[id] = src;
        debug ("clipboard poll started for %s (source %u)", id, src);
    }

    private void _stop_poll (Device dev) {
        string id = dev.device_id;
        if (_poll_sources.has_key (id)) {
            GLib.Source.remove (_poll_sources[id]);
            _poll_sources.unset (id);
            _last_sent.unset (id);
            debug ("clipboard poll stopped for %s", id);
        }
    }

    private void _poll_tick (Device dev) {
        if (!dev.is_active) {
            return;
        }

        string current = _read_clipboard ();
        if (current == null || current == "") {
            return;
        }

        string id = dev.device_id;
        string last = _last_sent.has_key (id) ? _last_sent[id] : "";

        if (current != last) {
            debug ("clipboard changed, sending to %s", dev.device_name);
            _last_sent[id] = current;
            send_clipboard_text (dev, current);
        }
    }

    /**
     * Read the current X11 clipboard content via xclip.
     * Returns null on failure.
     */
    private static string? _read_clipboard () {
        try {
            string stdout_str;
            string stderr_str;
            int exit_status;
            Process.spawn_command_line_sync (
                "xclip -selection clipboard -o",
                out stdout_str, out stderr_str, out exit_status);
            if (exit_status == 0) {
                return stdout_str;
            }
        } catch (Error e) {
            // xclip may exit non-zero if clipboard is empty – that's fine
        }
        return null;
    }

    // ── Inbound clipboard (phone → PC) ──────────────────────────────

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

            // Update our last-sent cache so the poller doesn't echo it back
            string id = dev.device_id;
            _last_sent[id] = text;

            set_clipboard_text (text, dev.device_name);
        }
    }

    private static void set_clipboard_text (string text, string device_name) {
        try {
            string[] argv = { "xclip", "-selection", "clipboard", "-in" };
            int stdin_fd;
            Pid child_pid;
            Process.spawn_async_with_pipes (
                null, argv, null,
                SpawnFlags.SEARCH_PATH | SpawnFlags.DO_NOT_REAP_CHILD,
                null,
                out child_pid, out stdin_fd, null, null);

            var chan = new IOChannel.unix_new (stdin_fd);
            chan.write_chars (text.to_utf8 (), null);
            chan.shutdown (true);

            ChildWatch.add (child_pid, (pid, status) => {
                Process.close_pid (pid);
            });

            Utils.show_own_notification ("Text copied to clipboard", device_name);
        } catch (Error e) {
            warning ("failed to copy text to clipboard via xclip: %s", e.message);
            var display = Gdk.Display.get_default ();
            if (display != null) {
                var cb = Gtk.Clipboard.get_default (display);
                cb.set_text (text, -1);
                Utils.show_own_notification ("Text copied to clipboard", device_name);
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
