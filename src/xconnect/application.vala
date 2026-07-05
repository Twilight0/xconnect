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

namespace Xconn {

    public class Application : GLib.Application {

        private Core core = null;

        private static bool log_debug = false;
        private static bool log_debug_verbose = false;

        private const GLib.OptionEntry[] options = {
            { "debug", 'd', 0, OptionArg.NONE, ref log_debug,
              "Show debug output", null },
            { "verbose-debug", 0, 0, OptionArg.NONE, ref log_debug_verbose,
              "Show verbose debug output", null },
            { null }
        };

        private Discovery discovery = null;
        private DeviceManager manager = null;
        private DeviceManagerDBusProxy bus_manager = null;
        private TransferManager transfer = null;
        private TransferManagerDBusProxy bus_transfer = null;
        private SocketService tcp_listener = null;

        public Application () {
            Object (application_id: "org.xconnect");
            add_main_option_entries (options);
            hold ();

            discovery = new Discovery ();
            manager = new DeviceManager ();
            transfer = new TransferManager ();
        }

        protected override void startup () {
            debug ("startup");

            base.startup ();

            if (log_debug_verbose == true) {
                Logging.enable_vdebug ();
                // enable debug logging when verbose is enabled
                log_debug = true;
            }

            if (log_debug == true)
                Environment.set_variable ("G_MESSAGES_DEBUG", "all", false);

            core = Core.instance ();
            if (core == null)
                error ("cannot initialize core");

            // Set up a file monitor to watch the config file for external changes
            try {
                var config_file = File.new_for_path (core.config.path);
                var monitor = config_file.monitor (FileMonitorFlags.NONE);
                monitor.changed.connect (() => {
                    // Reload configuration and notify manager of changes
                    core.config.reload ();
                    manager.reload_config (); // will implement method to handle updates
                });
            } catch (Error e) {
                warning ("Failed to set up config file monitor: %s", e.message);
            }

            core.transfer_manager = this.transfer;

            if (core.config.is_debug_on () == true)
                Environment.set_variable ("G_MESSAGES_DEBUG", "all", false);

            Notify.init ("xconnect");

            discovery.device_found.connect ((disc, discdev) => {
                manager.handle_discovered_device (discdev);
            });

            try {
                discovery.listen ();
            } catch (Error e) {
                message ("failed to setup device listener: %s", e.message);
            }

            this.tcp_listener = new SocketService ();
            uint16 tcp_port = core.config.get_tcp_port ();
            try {
                this.tcp_listener.add_inet_port (tcp_port, null);
                this.tcp_listener.incoming.connect (this.on_tcp_connection_incoming);
                this.tcp_listener.start ();
                message ("TCP listener started on port %u", tcp_port);
            } catch (Error e) {
                warning ("failed to start TCP listener on port %u: %s", tcp_port, e.message);
            }
        }

        protected override void activate () {
            debug ("activate");
            // reload devices from cache
            manager.load_cache ();
            // load custom device addresses from config
            manager.load_custom_devices ();
        }

        public override bool dbus_register (DBusConnection conn,
                                            string object_path) throws Error {

            this.bus_manager = new DeviceManagerDBusProxy.with_manager (conn,
                                                                        this.manager);
            this.bus_manager.publish ();

            this.bus_transfer = new TransferManagerDBusProxy.with_manager (conn,
                                                                           this.transfer);
            this.bus_transfer.publish ();

            base.dbus_register (conn, object_path);
            debug ("dbus register, path %s", object_path);

            return true;
        }

        public override void dbus_unregister (DBusConnection conn,
                                              string object_path) {

            base.dbus_unregister (conn, object_path);
            debug ("dbus unregister, path %s", object_path);
        }

        private bool on_tcp_connection_incoming (SocketConnection conn, Object? source_object) {
            message ("incoming TCP connection from %s", conn.get_remote_address ().to_string ());
            handle_incoming_connection.begin (conn);
            return true;
        }

        private async void handle_incoming_connection (SocketConnection conn) {
            message ("handling incoming TCP connection...");
            var channel = new DeviceChannel.from_connection (conn);

            Packet ? first_pkt = null;
            try {
                first_pkt = yield channel.receive_identity_plain_text ();
            } catch (Error e) {
                warning ("failed to receive identity packet: %s", e.message);
                channel.close ();
                return;
            }

            if (first_pkt == null || first_pkt.pkt_type != Packet.IDENTITY) {
                warning ("failed to receive a valid identity packet from incoming connection");
                channel.close ();
                return;
            }

            // We got the remote identity packet! Let's build a DiscoveredDevice.
            var host = ((InetSocketAddress) conn.get_remote_address ()).address;
            var discdev = new DiscoveredDevice.from_identity (first_pkt, host);
            message ("received identity from incoming TCP peer: %s (%s)", discdev.device_name, discdev.device_id);

            if (discdev.device_id == core.config.get_uuid ()) {
                message ("ignoring incoming TCP connection from ourselves");
                channel.close ();
                return;
            }



            // Pass to DeviceManager to associate the channel and activate it
            message ("forwarding incoming TCP connection to DeviceManager for device %s", discdev.device_name);
            manager.handle_incoming_device_connection (discdev, channel);
        }
    }
}
