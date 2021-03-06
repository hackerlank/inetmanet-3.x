//
// Copyright (C) 2008 Alfonso Ariza
//
// This program is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License
// as published by the Free Software Foundation; either version 2
// of the License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program; if not, write to the Free Software
// Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
//


package inet.linklayer.ieee80211mesh.nodes;

import inet.linklayer.ieee80211mesh.Ieee80211NicMesh;
import inet.linklayer.ieee80211mesh.Ieee80211NicMeshMulti;
import inet.networklayer.common.InterfaceTable;
import inet.common.queue.Sink;

import inet.networklayer.common.InterfaceTable;
import inet.mobility.contract.IMobility;
import inet.linklayer.contract.IWirelessNic;
import inet.linklayer.contract.IWiredNic;
import inet.linklayer.contract.IExternalNic;
import inet.networklayer.contract.IRoutingTable;

module BasicNetLayer
{
    gates:
        input ifIn[1];
        output ifOut[1];
    submodules:
        sink: Sink {
            @display("p=100,193;i=block/sink");
            gates:
                in[1];
        }
    connections allowunconnected:
        ifIn[0] --> sink.in[0];
}

//
// Models a mobile host with a wireless (802.11b) card. This module is
// a WirelessHost less the \PPP and Ethernet interfaces, plus mobility
// support (BasicMobility). It is intended mainly for mobile ad-hoc
// networks.
//
module BasicMobileManetMesh
{
    parameters:
        @networkNode();
        @display("i=device/pocketpc_s");
        string mobilityType = default("StationaryMobility");
        string energyStorageType = default("");
        *.interfaceTableModule = default(absPath(".interfaceTable"));
        *.energySourceModule = default(energyStorageType != "" ? absPath(".energyStorage") : "");
        int meshChannels = default(1);
    gates:
        input radioIn[meshChannels] @directIn;

    submodules:
        interfaceTable: InterfaceTable {
            parameters:
                @display("p=159,62");
        }
        sink: BasicNetLayer {
            @display("p=159,294;i=block/sink");
        }
        // the name of radio interface must have "wlan", valid examples wlan, wlan802, localwlan ....
        wlan: Ieee80211NicMeshMulti {
            parameters:
                meshChannels = meshChannels;
                @display("p=159,386;q=queue");
        }
        // optional mobility module. Required only if wireless cards are present
        mobility: <mobilityType> like IMobility if mobilityType != "" && meshChannels > 0 {
            parameters:
                @display("p=30,62");
        }

    connections allowunconnected:

        // connections to network outside
        for i=0..sizeof(meshChannels)-1 {
            radioIn[i] --> wlan.radioIn[i];

        }
        wlan.upperLayerOut --> sink.ifIn++;
        wlan.upperLayerIn <-- sink.ifOut++;
}


