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

class RunCommandHandler : Object, PacketHandlerInterface {

    public const string RUN_COMMMAND = "kdeconnect.runcommand";

    public string get_pkt_type () {
        return RUN_COMMMAND;
    }

    private RunCommandHandler () {
    }

    public static RunCommandHandler instance () {
        return new RunCommandHandler ();
    }

    public void use_device (Device dev) {
        debug ("use device %s for runcommand", dev.to_string ());
        dev.message.connect (this.message);
    }


    public void release_device (Device dev) {
        debug ("release device %s", dev.to_string ());
        dev.message.disconnect (this.message);
    }

    public void message (Device dev, Packet pkt) {
        if (pkt.pkt_type != RUN_COMMMAND) {
            return;
        }
        GLib.message ("run command from device %s %s", dev.to_string (), pkt.to_string());

    }

}


class RunRequestCommandHandler : Object, PacketHandlerInterface {

    public const string RUN_REQ_COMMMAND = "kdeconnect.runcommand.request";

    public string get_pkt_type () {
        return RUN_REQ_COMMMAND;
    }

    private RunRequestCommandHandler () {
    }

    public static RunRequestCommandHandler instance () {
        return new RunRequestCommandHandler ();
    }

    private signal void update_status (Packet pkt);

    public void use_device (Device dev) {
        debug ("use device %s for runcommand", dev.to_string ());
        dev.message.connect (this.message);
        update_status.connect (dev.send);
    }

    private void send_commands () {
        var builder = new Json.Builder ();
        builder.begin_object();
        builder.set_member_name ("commandList");
        builder.begin_object();
        var core = Core.instance();
        foreach (string value in core.config.list_commands()) {
            builder.set_member_name (value);
            builder.begin_object();
            builder.set_member_name ("name");
            builder.add_string_value (value);
            builder.set_member_name ("command");
            builder.add_string_value (core.config.get_command(value));
            builder.end_object();

        }
        builder.end_object();
        builder.end_object();
        var pkg = new Packet("kdeconnect.runcommand", builder.get_root ().get_object ());
        GLib.message ("sending package for runcommand %s", pkg.to_string());
        update_status(pkg);

    }

    public void release_device (Device dev) {
        debug ("release device %s", dev.to_string ());
        dev.message.disconnect (this.message);
    }

    public void message (Device dev, Packet pkt) {
        if (pkt.pkt_type != RUN_REQ_COMMMAND) {
            return;
        }
        if (pkt.body.has_member("requestCommandList")) {
            send_commands();
        } else if (pkt.body.has_member("key")) {
            var core = Core.instance();
            var key = pkt.body.get_string_member("key");
            var command = core.config.get_command(key);
            GLib.message ("run command from device %s %s %s", dev.to_string (), key, command);
            Posix.system(command);
        }
    }

}
