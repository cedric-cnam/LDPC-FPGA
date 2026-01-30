#!/usr/bin/env python3
"""
LDPC Testbed Configuration
"""

import os

# Network Configuration
CONTROLLER_HOST = "192.168.1.1"     # Controller server IP
CONTROLLER_CONTROL_PORT = 8000      # Port for control messages
CONTROLLER_DATA_PORT = 5000         # Port for receiving decoded data

FPGA_IP = "192.168.1.128"          # FPGA IP address
FPGA_MAC = "02:00:00:00:00:00"     # FPGA MAC address
FPGA_PORT = 1234                    # FPGA UDP port
FPGA_INTERFACE = "enp2s0f0"        # Network interface to FPGA

# Client Configuration
CLIENT_IP = "192.168.1.1"          # Client IP (same as controller for now)
CLIENT_DATA_PORT = 5000            # Port to receive decoded bits

# FPGA Programming
VIVADO_PATH = "/home/ryuk/Xilinx2/Vivado/2020.2/bin/vivado"  # Path to Vivado
TCL_SCRIPT_PATH = "fpga_programmer/program_fpga.tcl"    # TCL script path
BITFILE_DIR = "/home/ryuk/LDPC testbed/ldpc_testbed/fpga/bitfiles"                     # Directory with .bit files

# Bitfile mapping for different Z values
BITFILE_MAP = {
    48:  os.path.join(BITFILE_DIR, "ldpc_z48.bit"),
    96:  os.path.join(BITFILE_DIR, "ldpc_z96.bit"),
    192: os.path.join(BITFILE_DIR, "ldpc_z192.bit"),

}

# Hardware Parameters
SUPPORTED_Z_VALUES = [48, 96, 192]
LLRS_PER_Z = 50  # 50 LLRs per Z value

# Payload size calculation: Z * 25 bytes (from hardware design)
def get_payload_size(Z: int) -> int:
    """Calculate payload size for given Z"""
    return Z * 25

# Output size calculation: Z * 10 bits = Z * 10 / 8 bytes (rounded up)
def get_output_size(Z: int) -> int:
    """Calculate expected output size for given Z"""
    output_bits = Z * 10  # 10 bits per Z (hardware design)
    output_bytes = (output_bits + 7) // 8  # Round up to bytes
    return output_bytes

# Timeouts
FPGA_PROGRAM_TIMEOUT = 60  # seconds
DECODE_TIMEOUT = 10        # seconds
CONTROL_SOCKET_TIMEOUT = 1.0  # seconds

# Logging
LOG_DIR = "logs"
LOG_LEVEL = "INFO"  # DEBUG, INFO, WARNING, ERROR

# Performance
MAX_PACKET_RETRIES = 3
PACKET_SEND_INTERVAL = 0.1  # seconds between packets

# System
REQUIRE_ROOT = True  # Raw sockets need root privileges
