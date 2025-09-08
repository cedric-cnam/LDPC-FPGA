# This file is part of LDPC-FPGA.
#
# LDPC-FPGA is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# LDPC-FPGA is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with LDPC-FPGA.  If not, see <https://www.gnu.org/licenses/>.

create_project -force -part xc7vx690tffg1761-3 fpga
add_files -fileset sources_1 defines.v ../rtl/fpga.v ../rtl/fpga_core.v ../rtl/debounce_switch.v ../rtl/i2c_master.v ../rtl/si5324_i2c_init.v ../lib/eth/rtl/eth_mac_10g_fifo.v ../lib/eth/rtl/eth_mac_10g.v ../lib/eth/rtl/axis_xgmii_rx_64.v ../lib/eth/rtl/axis_xgmii_tx_64.v ../lib/eth/rtl/eth_phy_10g.v ../lib/eth/rtl/eth_phy_10g_rx.v ../lib/eth/rtl/eth_phy_10g_rx_if.v ../lib/eth/rtl/eth_phy_10g_rx_frame_sync.v ../lib/eth/rtl/eth_phy_10g_rx_ber_mon.v ../lib/eth/rtl/eth_phy_10g_tx.v ../lib/eth/rtl/eth_phy_10g_tx_if.v ../lib/eth/rtl/xgmii_baser_dec_64.v ../lib/eth/rtl/xgmii_baser_enc_64.v ../lib/eth/rtl/lfsr.v ../lib/eth/rtl/eth_axis_rx.v ../lib/eth/rtl/eth_axis_tx.v ../lib/eth/rtl/udp_complete_64.v ../lib/eth/rtl/udp_checksum_gen_64.v ../lib/eth/rtl/udp_64.v ../lib/eth/rtl/udp_ip_rx_64.v ../lib/eth/rtl/udp_ip_tx_64.v ../lib/eth/rtl/ip_complete_64.v ../lib/eth/rtl/ip_64.v ../lib/eth/rtl/ip_eth_rx_64.v ../lib/eth/rtl/ip_eth_tx_64.v ../lib/eth/rtl/ip_arb_mux.v ../lib/eth/rtl/arp.v ../lib/eth/rtl/arp_cache.v ../lib/eth/rtl/arp_eth_rx.v ../lib/eth/rtl/arp_eth_tx.v ../lib/eth/rtl/eth_arb_mux.v ../lib/eth/lib/axis/rtl/arbiter.v ../lib/eth/lib/axis/rtl/priority_encoder.v ../lib/eth/lib/axis/rtl/axis_fifo.v ../lib/eth/lib/axis/rtl/axis_async_fifo.v ../lib/eth/lib/axis/rtl/axis_async_fifo_adapter.v ../lib/eth/lib/axis/rtl/sync_reset.v
set_property top fpga [current_fileset]
add_files -fileset constrs_1 ../fpga.xdc ../lib/eth/syn/vivado/eth_mac_fifo.tcl ../lib/eth/lib/axis/syn/vivado/axis_async_fifo.tcl ../lib/eth/lib/axis/syn/vivado/sync_reset.tcl
source ../ip/ten_gig_eth_pcs_pma_0.tcl
source ../ip/ten_gig_eth_pcs_pma_1.tcl
