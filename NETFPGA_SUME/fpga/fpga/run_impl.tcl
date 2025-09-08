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

open_project fpga.xpr
reset_run impl_1
launch_runs -jobs 4 impl_1
wait_on_run impl_1
open_run impl_1
report_utilization -file fpga_utilization.rpt
report_utilization -hierarchical -file fpga_utilization_hierarchical.rpt
