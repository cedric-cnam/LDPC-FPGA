# LDPC FPGA Programming TCL Script (Alveo-compatible)
# This script programs the FPGA with a specified .bit file

# Usage: vivado -mode batch -source program_fpga.tcl -tclargs <bitfile_path>

# Get the bitfile path from command line argument
if { $argc != 1 } {
    puts "ERROR: Bitfile path not provided"
    puts "Usage: vivado -mode batch -source program_fpga.tcl -tclargs <bitfile_path>"
    exit 1
}

set bitfile_path [lindex $argv 0]

# Check if bitfile exists
if { ![file exists $bitfile_path] } {
    puts "ERROR: Bitfile not found: $bitfile_path"
    exit 1
}

puts "=========================================="
puts "LDPC FPGA Programming"
puts "=========================================="
puts "Bitfile: $bitfile_path"
puts ""

# Open hardware manager
puts "Opening Hardware Manager..."
open_hw_manager

# Connect to hardware server
puts "Connecting to hardware server..."
connect_hw_server -allow_non_jtag

# Open hardware target
puts "Opening hardware target..."
open_hw_target

# Get the first device
puts "Getting FPGA device..."
set dev [lindex [get_hw_devices] 0]

if { $dev == "" } {
    puts "ERROR: No FPGA device found"
    close_hw_manager
    exit 1
}

puts "Using device: $dev"
current_hw_device $dev
refresh_hw_device $dev

# Set bitfile and program
puts ""
puts "Programming FPGA with: $bitfile_path"
puts "This may take 30-60 seconds..."
puts ""

set_property PROGRAM.FILE $bitfile_path $dev
program_hw_devices $dev

puts ""
puts "=========================================="
puts "FPGA Programming Complete"
puts "=========================================="
puts "Device: $dev"
puts "Bitfile: $bitfile_path"
puts ""
puts "STATUS: SUCCESS - FPGA programmed successfully"

# Cleanup
close_hw_target
disconnect_hw_server
close_hw_manager

puts "Hardware Manager closed"
exit 0
