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

class ConnectivityReportHandler : Object, PacketHandlerInterface {

    public const string CONNECTIVITY_REPORT = "kdeconnect.connectivity_report";

    public string get_pkt_type () {
        return CONNECTIVITY_REPORT;
    }

    private ConnectivityReportHandler () {
    }

    public static ConnectivityReportHandler instance () {
        return new ConnectivityReportHandler ();
    }

    public void use_device (Device dev) {
        debug ("use device %s for connectivity report", dev.to_string ());
        dev.message.connect (this.message);
    }

    public void release_device (Device dev) {
        debug ("release device %s", dev.to_string ());
        dev.message.disconnect (this.message);
    }

    public void message (Device dev, Packet pkt) {
        if (pkt.pkt_type != CONNECTIVITY_REPORT) {
            return;
        }

        debug ("got connectivity report packet");

        // Parse signalStrengths object
        // Format: { "0": { "networkType": "LTE", "signalStrength": 80 }, ... }
        // Each key is a SIM subscription ID
        if (!pkt.body.has_member ("signalStrengths")) {
            warning ("connectivity report missing signalStrengths");
            return;
        }

        var strengths = pkt.body.get_object_member ("signalStrengths");
        if (strengths == null) {
            return;
        }

        // Emit signal with the raw JSON for the proxy to parse
        connectivity_update (dev, strengths);
    }

    /**
     * Emitted when connectivity info is received.
     * @dev: the device
     * @strengths: Json.Object mapping sub_id -> {networkType, signalStrength}
     */
    public signal void connectivity_update (Device dev, Json.Object strengths);
}
