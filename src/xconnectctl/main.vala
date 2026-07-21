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

namespace Xconnect {

    public class Client {

        private static bool log_debug = false;
        private static bool verbose = false;
        // some hints for valac about the array holding remaining args
        [CCode (array_length = false, array_null_terminated = true)]
        private static string[] remaining;
        private BusType bus_type = BusType.SESSION;

        private const OptionEntry[] options = {
            { "debug", 'd', 0, OptionArg.NONE, ref log_debug,
              "Show debug output", null },
            { "verbose", 'v', 0, OptionArg.NONE, ref verbose,
              "Be verbose", null },
            // there's no Vala const for G_OPTION_REMAINING (which is a #define
            // for "")
            { "", 0, 0, OptionArg.STRING_ARRAY, ref remaining, null,
              "[COMMAND ..]" },
            { null }
        };

        /**
         * Command:
         *
         * command line 'command' wrapper
         */
        private struct Command {
            unowned string command; // textual command, ex. list, show, etc.
            int arg_count; // number of required parameters, not including command
            unowned CommandFunc clbk; // callback

            Command (string command, int arg_count, CommandFunc clbk) {
                this.command = command;
                this.arg_count = arg_count;
                this.clbk = clbk;
            }
        }
        // command callback
        private delegate int CommandFunc (string[] args);

        public static int main (string[] args) {
            Intl.setlocale(LocaleCategory.ALL, "");
            try {
                var opt_context = new OptionContext ();
                opt_context.set_summary (
"""xconnectctl - Command line interface for xconnect

Usage:
  xconnectctl [OPTIONS] <command> [args...]

Available commands:
  list-devices                 List all discovered and paired devices
  show-device <path>           Show detailed info & capabilities of a device
  show-battery <path>          Show battery level and charging status
  allow-device <path>          Allow device connections
  remove-device <path>         Remove device completely from configuration

  pair-device <path>           Initiate pairing request to device (displays verification key)
  accept-pair <path>           Accept an incoming pairing request
  reject-pair <path>           Reject an incoming pairing request

  find-device <path>           Ring phone (Find My Phone)
  share-url <path> <url>       Open URL on device web browser
  share-text <path> <text>     Send text snippet to device
  share-file <path> <filepath> Transfer file to device
  send-sms <path> <num> <msg>  Send SMS message via phone

  start-daemon                 Start xconnect systemd user service
  stop-daemon                  Stop xconnect systemd user service
  help                         Show this help message
"""
                );
                opt_context.set_help_enabled (true);
                opt_context.add_main_entries (options, null);
                opt_context.parse (ref args);
            } catch (OptionError e) {
                stdout.printf ("error: %s\n", e.message);
                stdout.printf ("Run '%s --help' to see a full " +
                               "list of available command line options.\n",
                               args[0]);
                return 1;
            }

            if (log_debug == true)
                Environment.set_variable ("G_MESSAGES_DEBUG", "all", false);

            var cl = new Client ();

            // Try to start daemon if not running
            try {
                var manager = cl.get_manager ();
                if (manager != null) {
                    // Daemon is running
                } else {
                    throw new IOError.FAILED ("no manager");
                }
            } catch (Error e) {
                message ("daemon not running, attempting to start via systemd...");
                try {
                    Process.spawn_command_line_sync (
                        "systemctl --user start xconnect.service");
                    Thread.usleep (1000000); // Wait 1 second
                } catch (SpawnError e2) {
                    warning ("failed to start daemon via systemd: %s", e2.message);
                    stderr.printf ("Error: xconnect daemon is not running.\n");
                    stderr.printf ("Start it with: systemctl --user start xconnect.service\n");
                    return 1;
                }
            }
            Command[] commands = {
                Command ("list-devices", 0, cl.cmd_list_devices),
                Command ("list", 0, cl.cmd_list_devices),
                Command ("refresh", 0, cl.cmd_refresh),
                Command ("allow-device", 1, cl.cmd_allow_device),
                Command ("allow", 1, cl.cmd_allow_device),
                Command ("remove-device", 1, cl.cmd_remove_device),
                Command ("remove", 1, cl.cmd_remove_device),
                Command ("pair-device", 1, cl.cmd_pair_device),
                Command ("pair", 1, cl.cmd_pair_device),
                Command ("accept-pair", 1, cl.cmd_accept_pair),
                Command ("accept", 1, cl.cmd_accept_pair),
                Command ("reject-pair", 1, cl.cmd_reject_pair),
                Command ("reject", 1, cl.cmd_reject_pair),
                Command ("find-device", 1, cl.cmd_find_device),
                Command ("find", 1, cl.cmd_find_device),
                Command ("show-device", 1, cl.cmd_show_device),
                Command ("show", 1, cl.cmd_show_device),
                Command ("show-battery", 1, cl.cmd_show_battery),
                Command ("battery", 1, cl.cmd_show_battery),
                Command ("share-url", 2, cl.cmd_share_url),
                Command ("share-text", 2, cl.cmd_share_text),
                Command ("share-file", 2, cl.cmd_share_file),
                Command ("send-sms", 3, cl.cmd_send_sms),
                Command ("start-daemon", 0, cl.cmd_start_daemon),
                Command ("stop-daemon", 0, cl.cmd_stop_daemon),
                Command ("help", 0, cl.cmd_help),
            };
            handle_command (remaining, commands);

            return 0;
        }

        /**
         * handle_command:
         * @args: remaining command line arguments
         * @commands: supported commands array
         *
         * @return exit status of command or -1 on error
         */
        private static int handle_command (string[] args, Command[] commands) {
            // extract command and it's arguments if any
            string command = "list-devices";

            if (args.length > 0)
                command = remaining[0];
            debug ("command is: %s", command);

            string[] command_args = {};
            if (args.length > 1)
                command_args = args[1 : args.length];

            foreach (var cmden in commands) {
                if (cmden.command == command) {
                    debug ("found match for %s, args expect: %zd, have: %zd",
                           command, cmden.arg_count, command_args.length);

                    if (command_args.length != cmden.arg_count) {
                        stderr.printf ("Incorrect number of arguments " +
                                       "for command %s, see --help\n",
                                       command);
                        return -1;
                    }

                    debug ("running callback");
                    debug("TEST");
                    return cmden.clbk (command_args);
                }
            }

            stderr.printf ("Incorrect command, see --help\n");
            return -1;
        }

        private int cmd_list_devices (string[] args) {
            return checked_dbus_call (() => {
                var manager = get_manager ();
                debug ("list devices");
                var devs = manager.ListDevices ();
                print_paths (devs, "Devices",
                             (path) => {
                    try {
                        var dp = get_device (path);
                        var status = dp.is_paired ? "Paired" : "Unpaired (Available for pairing)";
                        var active = dp.is_active ? "Connected" : "Offline";
                        return "%s [%s] (%s, %s) - Address: %s".printf (
                            dp.name, dp.device_type, status, active, dp.address);
                    } catch (IOError e) {
                        warning ("error occurred: %s", e.message);
                        return "(error)";
                    }
                });
                return 0;
            });
        }

        private int cmd_refresh (string[] args) {
            return checked_dbus_call (() => {
                var manager = get_manager ();
                manager.Refresh ();
                stdout.printf ("Triggered network discovery scan\n");
                return 0;
            });
        }

        private int cmd_allow_device (string[] args) {
            return checked_dbus_call (() => {
                var dp = args[0];
                var manager = get_manager ();
                debug ("allow device device %s", dp);
                manager.AllowDevice (new ObjectPath (dp));
                return 0;
            });
        }

        private int cmd_remove_device (string[] args) {
            return checked_dbus_call (() => {
                var dp = args[0];
                var manager = get_manager ();
                debug ("remove device %s", dp);
                manager.RemoveDevice (new ObjectPath (dp));
                stdout.printf ("Device removed\n");
                return 0;
            });
        }

        private int cmd_pair_device (string[] args) {
            return checked_dbus_call (() => {
                var dp = args[0];
                var device = get_device (new ObjectPath (dp));
                device.Pair ();
                try {
                    var vkey = device.GetVerificationKey ();
                    if (vkey != null && vkey.length > 0) {
                        stdout.printf ("Pairing request sent to %s (Verification key: %s)\n", dp, vkey);
                    } else {
                        stdout.printf ("Pairing request sent to %s\n", dp);
                    }
                } catch (Error e) {
                    stdout.printf ("Pairing request sent to %s\n", dp);
                }
                return 0;
            });
        }

        private int cmd_accept_pair (string[] args) {
            return checked_dbus_call (() => {
                var dp = args[0];
                var device = get_device (new ObjectPath (dp));
                device.AcceptPair ();
                stdout.printf ("Accepted pairing request for %s\n", dp);
                return 0;
            });
        }

        private int cmd_reject_pair (string[] args) {
            return checked_dbus_call (() => {
                var dp = args[0];
                var device = get_device (new ObjectPath (dp));
                device.RejectPair ();
                stdout.printf ("Rejected pairing request for %s\n", dp);
                return 0;
            });
        }

        private int cmd_help (string[] args) {
            stdout.puts ("xconnectctl - Command line interface for xconnect\n\n");
            stdout.puts ("Usage:\n");
            stdout.puts ("  xconnectctl [OPTIONS] <command> [args...]\n\n");
            stdout.puts ("Device Commands:\n");
            stdout.puts ("  list-devices                 List all discovered and paired devices\n");
            stdout.puts ("  show-device <path>           Show detailed info & capabilities of a device\n");
            stdout.puts ("  show-battery <path>          Show battery level and charging status\n");
            stdout.puts ("  allow-device <path>          Allow device connections\n");
            stdout.puts ("  remove-device <path>         Remove device completely from configuration\n\n");
            stdout.puts ("Pairing Commands:\n");
            stdout.puts ("  pair-device <path>           Initiate pairing request to device (displays verification key)\n");
            stdout.puts ("  accept-pair <path>           Accept an incoming pairing request\n");
            stdout.puts ("  reject-pair <path>           Reject an incoming pairing request\n\n");
            stdout.puts ("Action & Share Commands:\n");
            stdout.puts ("  find-device <path>           Ring phone (Find My Phone)\n");
            stdout.puts ("  share-url <path> <url>       Open URL on device web browser\n");
            stdout.puts ("  share-text <path> <text>     Send text snippet to device\n");
            stdout.puts ("  share-file <path> <filepath> Transfer file to device\n");
            stdout.puts ("  send-sms <path> <num> <msg>  Send SMS message via phone\n\n");
            stdout.puts ("Service Commands:\n");
            stdout.puts ("  start-daemon                 Start xconnect systemd user service\n");
            stdout.puts ("  stop-daemon                  Stop xconnect systemd user service\n");
            stdout.puts ("  help                         Show this help message\n\n");
            stdout.puts ("Options:\n");
            stdout.puts ("  -d, --debug                  Show debug output\n");
            stdout.puts ("  -v, --verbose                Be verbose\n");
            stdout.puts ("  -h, --help                   Show command help\n");
            stdout.flush ();
            return 0;
        }

        private int cmd_share_url (string[] args) {
            return checked_dbus_call (() => {
                var dp = args[0];
                var share = get_share (new ObjectPath (dp));
                share.share_url (args[1]);
                return 0;
            });
        }

        private int cmd_share_text (string[] args) {
            return checked_dbus_call (() => {
                var dp = args[0];
                var share = get_share (new ObjectPath (dp));
                share.share_text (args[1]);
                return 0;
            });
        }


        private int cmd_find_device (string[] args) {
            return checked_dbus_call (() => {
                var dp = args[0];
                var device = get_find_my_phone (new ObjectPath (dp));
                device.find ();
                return 0;
            });
        }

        private int cmd_share_file (string[] args) {
            return checked_dbus_call (() => {
                var dp = args[0];
                var share = get_share (new ObjectPath (dp));
                var file = File.new_for_path (args[1]);
                var path = file.get_path ();
                debug ("share path: %s", path);
                share.share_file (path);
                return 0;
            });
        }

        private int cmd_send_sms (string[] args) {
            return checked_dbus_call (() => {
                var dp = args[0];
                var number = args[1];
                var message = args[2];
                var telephony = get_telephony (new ObjectPath (dp));
                telephony.send_sms (number, message);
                return 0;
            });
        }

        private void print_sorted_caps (string[] caps, string format) {
            // Simple bubble sort to avoid qsort warnings
            for (int i = 0; i < caps.length - 1; i++) {
                for (int j = 0; j < caps.length - i - 1; j++) {
                    if (GLib.strcmp (caps[j], caps[j+1]) > 0) {
                        string tmp = caps[j];
                        caps[j] = caps[j+1];
                        caps[j+1] = tmp;
                    }
                }
            }
            foreach (var cap in caps) {
                stdout.printf (format, cap);
            }
        }

        private int cmd_show_device (string[] args) {
            return checked_dbus_call (() => {
                var dp = get_device (new ObjectPath (args[0]));

                stdout.printf ("Device\n" +
                               "  Name: %s\n" +
                               "  ID: %s\n" +
                               "  Address: %s\n" +
                               "  Type: %s\n" +
                               "  Allowed: %s\n" +
                               "  Paired: %s\n" +
                               "  Active: %s\n" +
                               "  Connected: %s\n",
                               dp.name,
                               dp.id,
                               dp.address,
                               dp.device_type,
                               dp.allowed.to_string (),
                               dp.is_paired.to_string (),
                               dp.is_active.to_string (),
                               dp.is_connected.to_string ());
                if (verbose) {
                    stdout.printf ("  Capabilities (out):\n");
                    print_sorted_caps (dp.outgoing_capabilities, "    %s\n");
                    stdout.printf ("  Capabilities (in):\n");
                    print_sorted_caps (dp.incoming_capabilities, "    %s\n");
                    stdout.printf ("  Certificate:\n%s\n", dp.certificate);
                }
                return 0;
            });
        }

        private int cmd_show_battery(string[] args) {
            debug("DEBUG_0");
            return checked_dbus_call (() => {
                var bt = get_battery (new ObjectPath (args[0]));

                stdout.printf ("Level: %u\n" +
                               "Charging: %d\n",
                               bt.level,
                               bt.charging);
                return 0;
            });
        }

        private int cmd_start_daemon (string[] args) {
            try {
                Process.spawn_command_line_sync (
                    "systemctl --user start xconnect.service");
                stdout.printf ("Daemon started\n");
                return 0;
            } catch (SpawnError e) {
                stderr.printf ("Failed to start daemon: %s\n", e.message);
                return 1;
            }
        }

        private int cmd_stop_daemon (string[] args) {
            try {
                Process.spawn_command_line_sync (
                    "systemctl --user stop xconnect.service");
                stdout.printf ("Daemon stopped\n");
                return 0;
            } catch (SpawnError e) {
                stderr.printf ("Failed to stop daemon: %s\n", e.message);
                return 1;
            }
        }
        private delegate int CheckDBusCallFunc () throws Error;

        /**
         * checked_dbus_call:
         * @clbk: function to wrap
         *
         * Catch any DBus errors and return appropriate status
         */
        private static int checked_dbus_call (CheckDBusCallFunc clbk) {
            try {
                return clbk ();
            } catch (IOError e) {
                warning ("communication returned an error: %s", e.message);
                return -1;
            } catch (DBusError e) {
                warning ("communication with service failed: %s", e.message);
            } catch (Error e) {
                warning ("error: %s", e.message);
            }
            return 0;
        }

        /**
         * get_xconnect_obj_proxy:
         * @path: DBus object path
         *
         * Obtain an interface to a DBus object avaialble at
         * Xconnect service under @path.
         *
         * @return null or interface
         */
        private T ? get_xconnect_obj_proxy<T>(ObjectPath path) throws IOError {
            T proxy_out = null;
            try {
                proxy_out = Bus.get_proxy_sync (bus_type,
                                                "org.xconnect",
                                                path);
            } catch (IOError e) {
                warning ("failed to obtain proxy to xconnect service: %s",
                         e.message);
                throw e;
            }
            return proxy_out;
        }

        /**
         * get_manager:
         *
         * Obtain DBus interface to Device Manager
         *
         * @return interface or null
         */
        private DeviceManagerIface ? get_manager () throws IOError {
            return get_xconnect_obj_proxy (
                new ObjectPath (DeviceManagerIface.OBJECT_PATH));
        }

        /**
         * get_device:
         * @path device object path
         *
         * Obtain DBus interface to Device
         *
         * @return interface or null
         */
        private DeviceIface ? get_device (ObjectPath path) throws IOError {
            return get_xconnect_obj_proxy (path);
        }

        /**
         * get_device:
         * @path device object path
         *
         * Obtain DBus interface to Device.Battery
         *
         * @return interface or null
         */
        private BatteryIface ? get_battery (ObjectPath path) throws IOError {
            return get_xconnect_obj_proxy (path);
        }

        /**
         * get_share:
         *
         * Obtain DBus interface to Share of given device
         *
         * @return interface or null
         */
        private ShareIface ? get_share (ObjectPath path) throws IOError {
            return get_xconnect_obj_proxy (path);
        }


        /**
         * get_find_my_phone:
         *
         * Obtain DBus interface to Share of given device
         *
         * @return interface or null
         */
        private FindMyPhoneIface ? get_find_my_phone (ObjectPath path) throws IOError {
            return get_xconnect_obj_proxy (path);
        }

        /**
         * get_telephony:
         *
         * Obtain DBus interface to Telephony of given device
         *
         * @return interface or null
         */
        private TelephonyIface ? get_telephony (ObjectPath path) throws IOError {
            return get_xconnect_obj_proxy (path);
        }

        /**
         * print_paths:
         * @objs: object paths
         * @header: header for printing,
         * @desc_clbk: callback for producing a meaningful description
         *
         * Print a list of object paths, possibly adding a description
         */
        private static void print_paths (ObjectPath[] objs, string header,
                                         GetDescFunc desc_clbk) {
            if (objs.length == 0)
                stdout.printf ("No objects were found\n");
            else {
                stdout.printf (header + ":\n");
                foreach (var o in objs) {
                    string desc = null;

                    if (desc_clbk != null) {
                        debug ("calling description callback for obj: %s",
                               o.to_string ());
                        desc = desc_clbk (o);
                    }

                    stdout.printf ("    %s", o.to_string ());
                    if (desc != null)
                        stdout.printf ("    %s", desc);
                    stdout.printf ("\n");
                }
            }
        }

        private delegate string GetDescFunc (ObjectPath obj_path);
    }
}
