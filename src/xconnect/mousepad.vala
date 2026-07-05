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

class MousepadHandler : Object, PacketHandlerInterface {

    public const string MOUSEPAD = "kdeconnect.mousepad.request";
    public const string MOUSEPAD_PACKET = "kdeconnect.mousepad";
    public const string MOUSEPAD_ECHO = "kdeconnect.mousepad.echo";
    public const string MOUSEPAD_KEYBOARDSTATE = "kdeconnect.mousepad.keyboardstate";
    private unowned X.Display _display;
    private uint[] SpecialKeysMap = {
                0,                   // Invalid
                Gdk.Key.BackSpace,   // 1
                Gdk.Key.Tab,         // 2
                Gdk.Key.Linefeed,    // 3
                Gdk.Key.Left,        // 4
                Gdk.Key.Up,          // 5
                Gdk.Key.Right,       // 6
                Gdk.Key.Down,        // 7
                Gdk.Key.Page_Up,     // 8
                Gdk.Key.Page_Down,   // 9
                Gdk.Key.Home,        // 10
                Gdk.Key.End,         // 11
                Gdk.Key.Return,      // 12
                Gdk.Key.Delete,      // 13
                Gdk.Key.Escape,      // 14
                Gdk.Key.Sys_Req,     // 15
                Gdk.Key.Scroll_Lock, // 16
                0,                   // 17
                0,                   // 18
                0,                   // 19
                0,                   // 20
                Gdk.Key.F1,          // 21
                Gdk.Key.F2,          // 22
                Gdk.Key.F3,          // 23
                Gdk.Key.F4,          // 24
                Gdk.Key.F5,          // 25
                Gdk.Key.F6,          // 26
                Gdk.Key.F7,          // 27
                Gdk.Key.F8,          // 28
                Gdk.Key.F9,          // 29
                Gdk.Key.F10,         // 30
                Gdk.Key.F11,         // 31
                Gdk.Key.F12,         // 32
            };

    public string get_pkt_type () {
        return MOUSEPAD;
    }

    private MousepadHandler () {
    }

    public static MousepadHandler instance () {
        var ms = new MousepadHandler ();
        ms._display = Gdk.X11.get_default_xdisplay ();
        if (ms._display == null) {
            warning ("failed to obtain display");
        }
        return ms;
    }



    public void use_device (Device dev) {
        debug ("use device %s for mouse/keyboard input", dev.to_string ());
        dev.message.connect (this.message);
    }

    public void release_device (Device dev) {
        debug ("release device %s ", dev.to_string ());
        dev.message.disconnect (this.message);
    }

    private void message (Device dev, Packet pkt) {
        if (pkt.pkt_type != MOUSEPAD_PACKET && pkt.pkt_type != MOUSEPAD) {
            return;
        }

        debug ("got mousepad packet");
        bool ctrl  = pkt.body.has_member("ctrl")  ? pkt.body.get_boolean_member("ctrl")  : false;
        bool alt   = pkt.body.has_member("alt")   ? pkt.body.get_boolean_member("alt")   : false;
        bool shift = pkt.body.has_member("shift") ? pkt.body.get_boolean_member("shift") : false;
        bool meta  = pkt.body.has_member("meta")  ? pkt.body.get_boolean_member("meta")  : false;

        Gdk.ModifierType mask = 0;
        if (ctrl)  mask |= Gdk.ModifierType.CONTROL_MASK;
        if (shift) mask |= Gdk.ModifierType.SHIFT_MASK;
        if (alt)   mask |= Gdk.ModifierType.MOD1_MASK;  // Alt key
        if (meta)  mask |= Gdk.ModifierType.META_MASK;  // Super key

        warning("ctrl %s alt %s shift %s meta %s", ctrl.to_string(), alt.to_string(), shift.to_string(), meta.to_string());


        if (_display == null) {
            warning ("display not initialized");
            return;
        }
        if (pkt.body.has_member ("singleclick")) {
            // single click
            debug ("single click");
            send_click (1);
        } else if (pkt.body.has_member ("doubleclick")) {
            send_click (1, true);
        } else if (pkt.body.has_member ("rightclick")) {
            send_click (3);
        } else if (pkt.body.has_member ("middleclick")) {
            send_click (2);
        } else if (pkt.body.has_member ("dx") && pkt.body.has_member ("dy")) {
            // motion/position or scrolling
            double dx = pkt.body.get_double_member ("dx");
            double dy = pkt.body.get_double_member ("dy");

            if (pkt.body.has_member ("scroll") && pkt.body.get_boolean_member ("scroll")) {
                // scroll with variable speed
                while (dy > 3.0) {
                    // scroll down
                    send_click (5);
                    dy /= 4.0;
                    debug ("scroll down");
                }
                while (dy < -3.0) {
                    // scroll up
                    send_click (4);
                    dy /= 4.0;
                    debug ("scroll up");
                }
            } else {
                debug ("position: %f x %f", dx, dy);

                move_cursor_relative (dx, dy);
            }
        } else if (pkt.body.has_member ("key")) {
            string key = pkt.body.get_string_member ("key");
            debug ("got key: %s", key);
            key_received (dev, key, 0, alt, ctrl, shift, meta);
            unichar c;
            for (int i = 0; key.get_next_char (ref i, out c);) {
                        uint keysym = Gdk.unicode_to_keyval(c);
                        send_key (keysym, mask);
            }
            // Send echo back to phone
            send_echo (dev, key, 0, alt, ctrl, shift, meta);
        } else if (pkt.body.has_member ("specialKey")) {
            var keynum = pkt.body.get_int_member ("specialKey");
            if (keynum < SpecialKeysMap.length) {
                var keysym = SpecialKeysMap[keynum];
                if (keysym != 0) {
                    debug ("got special key: %s", keynum.to_string ());
                    key_received (dev, null, (int) keynum, alt, ctrl, shift, meta);
                    send_key ((uint) keysym, mask);
                    // Send echo back to phone
                    send_echo (dev, null, (int) keynum, alt, ctrl, shift, meta);
                }
            }
        }
    }

    private void send_modifiersevent(Gdk.ModifierType flags, bool is_press) {
        if (Gdk.ModifierType.SHIFT_MASK in flags) {
            XTest.fake_key_event(_display, _display.keysym_to_keycode(Gdk.Key.Shift_L), is_press, 0);
        }
        if (Gdk.ModifierType.CONTROL_MASK in flags) {
            XTest.fake_key_event(_display, _display.keysym_to_keycode(Gdk.Key.Control_L), is_press, 0);
        }
        if (Gdk.ModifierType.MOD1_MASK in flags) {  // Alt key
            XTest.fake_key_event(_display, _display.keysym_to_keycode(Gdk.Key.Alt_L), is_press, 0);
        }
        if (Gdk.ModifierType.META_MASK in flags) {  // Meta key
            XTest.fake_key_event(_display, _display.keysym_to_keycode(Gdk.Key.Meta_L), is_press, 0);
        }
    }

    private void move_cursor_relative (double dx, double dy) {
        XTest.fake_relative_motion_event(_display, (int)dx, (int)dy, 0);
    }

    private void send_click (int button, bool doubleclick = false) {
        XTest.fake_button_event(_display, button, true, 0);
        XTest.fake_button_event(_display, button, false, 0);
        if (doubleclick) {
            XTest.fake_button_event(_display, button, true, 0);
            XTest.fake_button_event(_display, button, false, 0);
        }
    }

    private void send_key (uint keysym, Gdk.ModifierType mask) {
        var code = _display.keysym_to_keycode(keysym);
        send_modifiersevent(mask, true);
        XTest.fake_key_event(_display, code, true, 0);
        XTest.fake_key_event(_display, code, false, 0);
        send_modifiersevent(mask, false);
    }

    /**
     * Send echo packet back to device (for input confirmation)
     */
    public void send_echo (Device dev, string? key = null, int special_key = 0,
                            bool alt = false, bool ctrl = false, bool shift = false,
                            bool meta = false) {
        var builder = new Json.Builder ();
        builder.begin_object ();
        if (key != null) {
            builder.set_member_name ("key");
            builder.add_string_value (key);
        }
        if (special_key > 0) {
            builder.set_member_name ("specialKey");
            builder.add_int_value (special_key);
        }
        builder.set_member_name ("alt");
        builder.add_boolean_value (alt);
        builder.set_member_name ("ctrl");
        builder.add_boolean_value (ctrl);
        builder.set_member_name ("shift");
        builder.add_boolean_value (shift);
        builder.set_member_name ("meta");
        builder.add_boolean_value (meta);
        builder.end_object ();

        var pkt = new Packet (MOUSEPAD_ECHO, builder.get_root ().get_object ());
        dev.send (pkt);
    }

    /**
     * Send keyboard state to device (modifier key states)
     */
    public void send_keyboard_state (Device dev, bool alt = false, bool ctrl = false,
                                      bool shift = false, bool meta = false) {
        var builder = new Json.Builder ();
        builder.begin_object ();
        builder.set_member_name ("alt");
        builder.add_boolean_value (alt);
        builder.set_member_name ("ctrl");
        builder.add_boolean_value (ctrl);
        builder.set_member_name ("shift");
        builder.add_boolean_value (shift);
        builder.set_member_name ("meta");
        builder.add_boolean_value (meta);
        builder.end_object ();

        var pkt = new Packet (MOUSEPAD_KEYBOARDSTATE, builder.get_root ().get_object ());
        dev.send (pkt);
    }

    /**
     * Send a key press to the local display (for D-Bus remote keyboard)
     */
    public void send_key_press (uint keysym, bool alt = false, bool ctrl = false,
                                 bool shift = false, bool meta = false) {
        if (_display == null) {
            warning ("display not initialized");
            return;
        }

        Gdk.ModifierType mask = 0;
        if (ctrl)  mask |= Gdk.ModifierType.CONTROL_MASK;
        if (shift) mask |= Gdk.ModifierType.SHIFT_MASK;
        if (alt)   mask |= Gdk.ModifierType.MOD1_MASK;
        if (meta)  mask |= Gdk.ModifierType.META_MASK;

        send_key (keysym, mask);
    }

    public signal void key_received (Device dev, string? key, int special_key,
                                      bool alt, bool ctrl, bool shift, bool meta);
}
