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


create_ip -name ten_gig_eth_pcs_pma -vendor xilinx.com -library ip -module_name ten_gig_eth_pcs_pma_0

set_property -dict [list \
    CONFIG.MDIO_Management {false} \
    CONFIG.base_kr {BASE-R} \
    CONFIG.SupportLevel {1} \
    CONFIG.DClkRate {125} \
] [get_ips ten_gig_eth_pcs_pma_0]
