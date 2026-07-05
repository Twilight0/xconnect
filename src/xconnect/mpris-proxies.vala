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
 * Raphael Vogelgsang <rap.vog (at] gmail.com>
 */

[DBus (name = "org.freedesktop.DBus")]
public interface DBusProxy : Object {

    public abstract string[] list_names () throws Error;

    public signal void name_owner_changed (string name, string old_owner, string new_owner);
}

[DBus (name = "org.freedesktop.DBus.Properties")]
public interface DBusPropertiesProxy : Object {

    public signal void properties_changed (string interface_name, HashTable<string, Variant> changed_properties, string[] invalidated_properties);
}

[DBus (name = "org.mpris.MediaPlayer2.Player")]
public interface MprisPlayerProxy : Object {

    public abstract void next () throws Error;
    public abstract void previous () throws Error;
    public abstract void play_pause () throws Error;
    public abstract void play () throws Error;
    public abstract void pause () throws Error;
    public abstract void seek (int64 Offset) throws Error;

    public abstract string playback_status {
        owned get;
    }
    public abstract HashTable<string, Variant> metadata {
        owned get;
    }
    public abstract double volume {
        get; set;
    }
    public abstract int64 position {
        get;
    }
    public abstract bool can_go_next {
        get;
    }
    public abstract bool can_go_previous {
        get;
    }
    public abstract bool can_play {
        get;
    }
    public abstract bool can_pause {
        get;
    }
    public abstract bool can_seek {
        get;
    }
    public abstract bool can_control {
        get;
    }
}

[DBus (name = "org.mpris.MediaPlayer2")]
public interface MprisProxy : Object {

    public abstract string identity {
        owned get;
    }
}

[DBus (name = "org.xconnect.Device.Mpris")]
class MprisHandlerProxy : Object, PacketHandlerInterfaceProxy {

    private Device device = null;
    private MprisHandler mpris_handler = null;
    private uint register_id = 0;

    public string player_list { owned get; set; default = ""; }
    public string player { owned get; set; default = ""; }
    public string title { owned get; set; default = ""; }
    public string artist { owned get; set; default = ""; }
    public string album { owned get; set; default = ""; }
    public string album_art_url { owned get; set; default = ""; }
    public int64 length { get; set; default = 0; }
    public int64 pos { get; set; default = 0; }
    public bool is_playing { get; set; default = false; }
    public bool can_pause { get; set; default = false; }
    public bool can_play { get; set; default = false; }
    public bool can_go_next { get; set; default = false; }
    public bool can_go_previous { get; set; default = false; }
    public bool can_seek { get; set; default = false; }
    public int volume { get; set; default = 100; }

    public MprisHandlerProxy.for_device_handler (Device dev,
                                                  PacketHandlerInterface iface) {
        this.device = dev;
        this.mpris_handler = (MprisHandler) iface;
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

    public void send_action (string action) throws Error {
        // Forward action to phone if needed
    }

    public void change_volume (int volume) throws Error {
        // Forward volume change to phone if needed
    }

    public void seek (int64 position) throws Error {
        // Forward seek to phone if needed
    }

    public void set_position (int64 position) throws Error {
        // Forward position change to phone if needed
    }

    public void request_player_list () throws Error {
        // Request player list from phone
    }

    public void request_now_playing () throws Error {
        // Request now playing info from phone
    }

    public void request_volume () throws Error {
        // Request volume from phone
    }
}
