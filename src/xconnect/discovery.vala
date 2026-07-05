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

class Discovery : GLib.Object {
    private Socket socket = null;
    private uint broadcast_source = 0;

    public signal void device_found (DiscoveredDevice dev);

    public Discovery () {
    }

    ~Discovery () {
        debug ("cleaning up discovery...");
        if (this.broadcast_source != 0) {
            Source.remove (this.broadcast_source);
            this.broadcast_source = 0;
        }
        if (this.socket != null) {
            try {
                this.socket.close ();
            } catch (Error e) {}
        }
    }

    public void listen () throws Error {
        var core = Core.instance ();
        uint16 udp_port = core.config.get_udp_port ();

        this.socket = new Socket (SocketFamily.IPV4,
                                   SocketType.DATAGRAM,
                                   SocketProtocol.UDP);
        var sa = new InetSocketAddress (new InetAddress.any (SocketFamily.IPV4),
                                        udp_port);
        debug ("start listening for new devices at: %s:%u",
               sa.address.to_string (), sa.port);

        try {
            socket.bind (sa, true);
            socket.set_broadcast (true);
        } catch (Error e) {
            try {
                this.socket.close ();
            } catch (Error close_err) {}
            this.socket = null;
            throw e;
        }

        var source = socket.create_source (IOCondition.IN);
        source.set_callback ((s, c) => {
            this.incomingPacket ();
            return true;
        });
        source.attach (MainContext.default ());

        // Broadcast identity immediately and then periodically
        broadcast_identity ();
        this.broadcast_source = Timeout.add_seconds (5, () => {
            broadcast_identity ();
            return true;
        });
    }

    /**
     * broadcast_identity:
     *
     * Broadcast our identity packet to UDP port 1716 where KDE Connect
     * phones listen for new devices.
     */
    private void broadcast_identity () {
        if (this.socket == null)
            return;

        var core = Core.instance ();
        if (core == null)
            return;

        string host_name = Environment.get_host_name ();
        string name = core.config.get_name ();
        string uuid = core.config.get_uuid ();
        uint16 udp_port = core.config.get_udp_port ();
        uint16 tcp_port = core.config.get_tcp_port ();

        var pkt = Packet.new_identity (name,
                                        uuid,
                                        core.handlers.interfaces,
                                        core.handlers.interfaces,
                                        "desktop",
                                        tcp_port);

        string data = pkt.to_string ();

        // Always broadcast globally first
        try {
            var global_broadcast = new InetAddress.from_string ("255.255.255.255");
            var global_dest = new InetSocketAddress (global_broadcast, udp_port);
            this.socket.send_to (global_dest, data.data);
            debug ("global identity broadcast sent to 255.255.255.255:%u", udp_port);
        } catch (Error e) {
            debug ("global broadcast failed: %s", e.message);
        }

        // Collect local IPv4 addresses by trying to reach external hosts
        // This forces the OS to pick the right source IP
        string[] local_ips = {};
        try {
            // Create a UDP socket and "connect" to an external address
            // to discover our local IP
            var probe = new Socket (SocketFamily.IPV4,
                                     SocketType.DATAGRAM,
                                     SocketProtocol.UDP);
            var remote = new InetAddress.from_string ("8.8.8.8");
            var remote_addr = new InetSocketAddress (remote, 53);
            probe.connect (remote_addr);
            var local_addr = probe.get_local_address ();
            if (local_addr != null) {
                var ip = local_addr.to_string ();
                if (!ip.has_prefix ("127.")) {
                    local_ips += ip;
                }
            }
            probe.close ();
        } catch (Error e) {
            debug ("probe socket failed: %s", e.message);
        }

        // Fallback: try hostname resolution
        if (local_ips.length == 0) {
            try {
                var resolver = Resolver.get_default ();
                var addrs = resolver.lookup_by_name (host_name, null);
                foreach (var addr in addrs) {
                    if (addr.get_family () == SocketFamily.IPV4) {
                        var ip = addr.to_string ();
                        if (!ip.has_prefix ("127.")) {
                            local_ips += ip;
                        }
                    }
                }
            } catch (Error e) {
                debug ("hostname resolution failed: %s", e.message);
            }
        }

        // Broadcast to each discovered subnet
        foreach (var ip in local_ips) {
            var parts = ip.split (".");
            if (parts.length == 4) {
                var broadcast_str = @"$(parts[0]).$(parts[1]).$(parts[2]).255";
                try {
                    var broadcast_addr = new InetAddress.from_string (broadcast_str);
                    var dest = new InetSocketAddress (broadcast_addr, udp_port);
                    this.socket.send_to (dest, data.data);
                    debug ("subnet identity broadcast sent to %s:%u", broadcast_str, udp_port);
                } catch (Error e) {
                    debug ("broadcast to %s failed: %s", broadcast_str, e.message);
                }
            }
        }

        // Send unicast to custom device addresses
        var custom_devs = core.config.get_custom_devices ();
        foreach (string addr_str in custom_devs) {
            try {
                var addr = new InetAddress.from_string (addr_str);
                var dest = new InetSocketAddress (addr, udp_port);
                this.socket.send_to (dest, data.data);
                debug ("unicast identity sent to %s:%u", addr_str, udp_port);
            } catch (Error e) {
                debug ("unicast to %s failed: %s", addr_str, e.message);
            }
        }
    }

    private void incomingPacket () {
        vdebug ("incoming packet");

        uint8 buffer[4096];
        SocketAddress sa;
        InetSocketAddress isa;

        try {
            ssize_t read = this.socket.receive_from (out sa, buffer);
            if (read >= 0) {
                if (read < 4096) {
                    buffer[read] = '\0';
                } else {
                    buffer[4095] = '\0';
                }
            } else {
                return;
            }
            isa = (InetSocketAddress) sa;
            vdebug ("got %zd bytes from: %s:%u", read,
                    isa.address.to_string (), isa.port);
        } catch (Error e) {
            warning ("failed to receive packet: %s", e.message);
            return;
        }

        vdebug ("message data: %s", (string) buffer);

        this.parsePacketFromHost ((string) buffer, isa.address);
    }

    private void parsePacketFromHost (string data, InetAddress host) {
        // expecing an identity packet
        var pkt = Packet.new_from_data (data);
        if (pkt.pkt_type != Packet.IDENTITY) {
            message ("unexpected packet type %s from device %s",
                     pkt.pkt_type, host.to_string ());
            return;
        }

        var dev = new DiscoveredDevice.from_identity (pkt, host);
        
        var core = Core.instance ();
        if (core != null && dev.device_id == core.config.get_uuid ()) {
            vdebug ("ignoring identity from ourselves");
            return;
        }

        message ("connection from device: \'%s\', responds at: %s:%u",
                 dev.device_name, host.to_string (), dev.tcp_port);

        device_found (dev);
    }
}
