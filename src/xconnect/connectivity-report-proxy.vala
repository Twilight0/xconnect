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

[DBus (name = "org.xconnect.Device.ConnectivityReport")]
class ConnectivityReportHandlerProxy : Object, PacketHandlerInterfaceProxy {

    private Device device = null;
    private ConnectivityReportHandler handler = null;
    private uint register_id = 0;
    private DBusPropertyNotifier prop_notifier = null;

    public string cellular_network_type {
        get; private set; default = "Unknown";
    }

    public int32 cellular_network_strength {
        get; private set; default = 0;
    }

    public ConnectivityReportHandlerProxy.for_device_handler (Device dev,
                                                               PacketHandlerInterface iface) {
        this.device = dev;
        this.handler = (ConnectivityReportHandler) iface;
        this.handler.connectivity_update.connect (this.on_connectivity_update);
    }

    private void on_connectivity_update (Device dev, Json.Object strengths) {
        if (this.device != dev)
            return;

        // Use the first SIM slot (sub_id "0") as primary
        if (strengths.has_member ("0")) {
            var sim_info = strengths.get_object_member ("0");
            if (sim_info != null) {
                if (sim_info.has_member ("networkType")) {
                    this.cellular_network_type = sim_info.get_string_member ("networkType");
                }
                if (sim_info.has_member ("signalStrength")) {
                    this.cellular_network_strength = (int32) sim_info.get_int_member ("signalStrength");
                }
            }
        } else {
            // Try the first available member
            var members = strengths.get_members ();
            if (members.length () > 0) {
                var first_key = members.nth_data (0);
                var sim_info = strengths.get_object_member (first_key);
                if (sim_info != null) {
                    if (sim_info.has_member ("networkType")) {
                        this.cellular_network_type = sim_info.get_string_member ("networkType");
                    }
                    if (sim_info.has_member ("signalStrength")) {
                        this.cellular_network_strength = (int32) sim_info.get_int_member ("signalStrength");
                    }
                }
            }
        }

        debug ("connectivity: type=%s strength=%d",
               this.cellular_network_type,
               this.cellular_network_strength);
    }

    [DBus (visible = false)]
    public void bus_register (DBusConnection conn, string path) throws IOError {
        if (this.register_id == 0)
            this.register_id = conn.register_object (path, this);

        this.prop_notifier = new DBusPropertyNotifier (conn,
                                                        "org.xconnect.Device.ConnectivityReport",
                                                        path);

        this.notify.connect (this.send_property_change);
    }

    [DBus (visible = false)]
    public void bus_unregister (DBusConnection conn) throws IOError {
        if (this.register_id != 0)
            conn.unregister_object (this.register_id);
        this.register_id = 0;

        this.notify.disconnect (this.send_property_change);
    }

    private void send_property_change (ParamSpec p) {
        assert (this.prop_notifier != null);

        Variant v = null;

        if (p.name == "cellular-network-type") {
            v = this.cellular_network_type;
        }
        if (p.name == "cellular-network-strength") {
            v = this.cellular_network_strength;
        }

        if (v == null)
            return;

        this.prop_notifier.queue_property_change (p.name, v);
    }
}
