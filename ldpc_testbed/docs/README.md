# LDPC FPGA Testbed

A complete testbed for LDPC (Low-Density Parity-Check) decoding using FPGA hardware with dynamic programming support.

## 🏗️ Architecture

```
┌─────────────┐                    ┌──────────────┐
│    User     │  (1) Task Request  │  Controller  │
│   Client    │ ──────────────────>│   Server     │
│             │                     │              │
│             │  (2) FPGA Ready    │  • Programs  │
│             │ <──────────────────│    FPGA      │
└─────────────┘                    │  • Manages   │
       │                            │    Tasks     │
       │ (3) LLR Data              └──────────────┘
       │                                    │
       v                                    │ Programs
┌─────────────┐                    ┌──────────────┐
│    FPGA     │                    │   Vivado     │
│   Hardware  │  (4) Decoded Bits  │   Hardware   │
│             │ ──────────────────>│   Manager    │
└─────────────┘        to Client   └──────────────┘
```

## 📋 Features

- **Dynamic FPGA Programming**: Automatically programs FPGA with correct bitfile for requested lifting size (Z)
- **Multiple Z Support**: Handles Z = 48, 96, 192, 256, 384
- **Control Protocol**: TCP-based reliable control messages between client and controller
- **High-Speed Data**: Raw socket Ethernet packets for LLR data to FPGA
- **Complete Workflow**: From task submission to receiving decoded bits

## 🗂️ Project Structure

```
ldpc_testbed/
├── client/
│   └── client.py              # User client application
├── controller/
│   └── controller_server.py   # Controller server
├── fpga_programmer/
│   ├── program_fpga.tcl       # Vivado TCL script
│   └── fpga_programmer.py     # Python wrapper for TCL
├── common/
│   └── protocol.py            # Shared protocol definitions
├── configs/
│   └── config.py              # Configuration file
├── docs/
│   └── README.md              # This file
└── logs/                      # Log files
```

## 🚀 Quick Start

### Prerequisites

1. **Hardware**:
   - FPGA board with LDPC decoder core
   - Network connection to FPGA (192.168.1.128)
   - PC with network interface (enp2s0f0)

2. **Software**:
   - Python 3.8+
   - Xilinx Vivado (with hw_server)
   - Root privileges (for raw sockets)

3. **Network Setup**:
   ```bash
   # Set PC IP
   sudo ip addr add 192.168.1.1/24 dev enp2s0f0
   sudo ip link set enp2s0f0 up
   
   # Increase MTU if needed
   sudo ip link set enp2s0f0 mtu 9000
   ```

### Installation

1. **Clone and setup**:
   ```bash
   cd ldpc_testbed
   
   # Create log directory
   mkdir -p logs
   
   # Make scripts executable
   chmod +x client/client.py
   chmod +x controller/controller_server.py
   chmod +x fpga_programmer/fpga_programmer.py
   ```

2. **Configure paths** in `configs/config.py`:
   - Update `VIVADO_PATH` to your Vivado installation
   - Update `BITFILE_DIR` to your bitfile directory
   - Update `FPGA_INTERFACE` to your network interface

3. **Prepare bitfiles**:
   ```bash
   mkdir -p /home/fpga/bitfiles
   # Copy your .bit files:
   # ldpc_z48.bit, ldpc_z96.bit, ldpc_z192.bit, etc.
   ```

### Running the Testbed

#### Step 1: Start Vivado Hardware Server

```bash
# In a terminal
hw_server
```

Should output:
```
****** Xilinx hw_server v2023.2
  **** Build date : Sep 10 2023-23:18:34
    ** Copyright 1986-2023 Xilinx, Inc. All Rights Reserved.

INFO: hw_server application started
INFO: Use Ctrl-C to exit hw_server application
```

#### Step 2: Start Controller Server

```bash
# In another terminal (may need root for raw sockets later)
cd ldpc_testbed
sudo python3 controller/controller_server.py
```

Should output:
```
======================================================================
LDPC Testbed Controller Server
======================================================================
✅ Controller running
   Control port: 8000
   Data port: 5000

Press Ctrl+C to stop
```

#### Step 3: Run Client

```bash
# In another terminal
cd ldpc_testbed
sudo python3 client/client.py <Z> [bitfile_path]

# Example: Test with Z=96
sudo python3 client/client.py 96

# Example: Test with custom bitfile
sudo python3 client/client.py 192 /path/to/my_ldpc.bit
```

## 📖 Usage Examples

### Example 1: Basic Decode Task

```python
from client.client import LDPCClient, generate_test_llrs

# Create client
client = LDPCClient()

# Generate test LLRs for Z=96
Z = 96
llrs = generate_test_llrs(Z)

# Submit task
success, msg, decoded_bits = client.submit_task(
    Z=96,
    llrs=llrs,
    bitfile_path="/home/fpga/bitfiles/ldpc_z96.bit"
)

if success:
    print(f"Decoded {len(decoded_bits)} bits!")
    print(f"First 10: {decoded_bits[:10]}")
else:
    print(f"Failed: {msg}")

client.cleanup()
```

### Example 2: Custom LLRs

```python
from client.client import LDPCClient

Z = 48
num_llrs = 50 * Z  # Must be exactly 50*Z

# Create your own LLRs (4-bit signed: -8 to +7)
llrs = []
for i in range(num_llrs):
    # Your LLR generation logic
    llr = compute_llr(...)  # Your function
    llr = max(-8, min(7, llr))  # Clamp to valid range
    llrs.append(llr)

# Submit
client = LDPCClient()
success, msg, bits = client.submit_task(Z, llrs, "ldpc_z48.bit")
```

### Example 3: Batch Processing

```python
from client.client import LDPCClient, generate_test_llrs

client = LDPCClient()

# Test multiple Z values
z_values = [48, 96, 192]
results = {}

for Z in z_values:
    print(f"\nTesting Z={Z}...")
    llrs = generate_test_llrs(Z)
    
    success, msg, bits = client.submit_task(
        Z=Z,
        llrs=llrs,
        bitfile_path=f"/home/fpga/bitfiles/ldpc_z{Z}.bit"
    )
    
    results[Z] = {
        'success': success,
        'message': msg,
        'bits': len(bits) if bits else 0
    }

# Print results
for Z, result in results.items():
    status = "✅" if result['success'] else "❌"
    print(f"{status} Z={Z}: {result['message']}")

client.cleanup()
```

## 🔧 Configuration

### Network Configuration (configs/config.py)

```python
# Controller
CONTROLLER_HOST = "192.168.1.1"
CONTROLLER_CONTROL_PORT = 8000
CONTROLLER_DATA_PORT = 5000

# FPGA
FPGA_IP = "192.168.1.128"
FPGA_MAC = "02:00:00:00:00:00"
FPGA_PORT = 1234
FPGA_INTERFACE = "enp2s0f0"
```

### Bitfile Mapping

```python
BITFILE_MAP = {
    48:  "/home/fpga/bitfiles/ldpc_z48.bit",
    96:  "/home/fpga/bitfiles/ldpc_z96.bit",
    192: "/home/fpga/bitfiles/ldpc_z192.bit",
    256: "/home/fpga/bitfiles/ldpc_z256.bit",
    384: "/home/fpga/bitfiles/ldpc_z384.bit",
}
```

### Timeouts

```python
FPGA_PROGRAM_TIMEOUT = 60  # seconds
DECODE_TIMEOUT = 10        # seconds
CONTROL_SOCKET_TIMEOUT = 1.0  # seconds
```

## 📡 Protocol Specification

### Control Messages (TCP)

All control messages use JSON-over-TCP with a 4-byte length header:

```
[4-byte length][JSON payload]
```

#### Message Types

1. **TASK_REQUEST** (Client → Controller)
   ```json
   {
     "msg_type": 1,
     "task_id": "abc123",
     "payload": {
       "task_id": "abc123",
       "lifting_size": 96,
       "num_llrs": 4800,
       "llrs": [3, -3, 5, -5, ...],
       "bitfile_path": "/path/to/ldpc_z96.bit",
       "expected_output_bits": 960,
       "timeout_seconds": 30
     },
     "timestamp": 1706634000.0
   }
   ```

2. **TASK_ACCEPTED** (Controller → Client)
   ```json
   {
     "msg_type": 16,
     "task_id": "abc123",
     "payload": {
       "message": "Task accepted, programming FPGA..."
     },
     "timestamp": 1706634001.0
   }
   ```

3. **FPGA_READY** (Controller → Client)
   ```json
   {
     "msg_type": 17,
     "task_id": "abc123",
     "payload": {
       "fpga_ip": "192.168.1.128",
       "fpga_port": 1234,
       "message": "FPGA programmed and ready for data"
     },
     "timestamp": 1706634030.0
   }
   ```

4. **ERROR** (Controller → Client)
   ```json
   {
     "msg_type": 21,
     "task_id": "abc123",
     "payload": {
       "error": "FPGA programming failed: ..."
     },
     "timestamp": 1706634025.0
   }
   ```

### Data Packets (UDP/Raw Ethernet)

**Client → FPGA**: LLR data packets
- Format: Ethernet + IP + UDP + Payload
- Payload: 16 LLRs per 64-bit word (4 bits per LLR)
- Size: Z * 25 bytes

**FPGA → Client**: Decoded bits
- Format: UDP packet
- Payload: Packed bits (8 bits per byte)
- Size: (Z * 10 + 7) / 8 bytes

## 🐛 Troubleshooting

### Controller won't start

**Problem**: "No hardware targets found"
- **Solution**: Make sure hw_server is running: `hw_server`

**Problem**: "Vivado not found"
- **Solution**: Update `VIVADO_PATH` in configs/config.py

### Client can't connect

**Problem**: "Connection refused"
- **Solution**: Check controller is running and firewall allows port 8000

**Problem**: "Root privileges required"
- **Solution**: Run client with `sudo python3 client/client.py ...`

### FPGA not responding

**Problem**: "Timeout waiting for FPGA response"
- **Solution**: 
  1. Check FPGA is powered and connected
  2. Verify network: `ping 192.168.1.128`
  3. Check FPGA IP/MAC in configs/config.py
  4. Verify correct bitfile was programmed

**Problem**: "Received wrong response size"
- **Solution**: 
  1. Check Z value matches programmed bitfile
  2. Verify LLR count is exactly 50*Z
  3. Check FPGA hardware design output size

### Programming fails

**Problem**: "FPGA programming failed"
- **Solution**:
  1. Check bitfile exists and is valid
  2. Check JTAG cable connected
  3. Try programming manually with Vivado GUI
  4. Check hardware server logs

## 📊 Performance Tips

1. **Network MTU**: Increase for larger Z values
   ```bash
   sudo ip link set enp2s0f0 mtu 9000
   ```

2. **Logging**: Reduce logging level for production
   ```python
   LOG_LEVEL = "WARNING"  # in configs/config.py
   ```

3. **Batch Processing**: Reuse client connection for multiple tasks

4. **Bitfile Caching**: Keep programmed Z value to avoid reprogramming

## 🔐 Security Notes

- Raw sockets require root privileges
- Control protocol uses plain TCP (consider TLS for production)
- Validate all user inputs before processing
- Limit concurrent connections to controller

## 📝 Logging

Logs are written to:
- `logs/controller.log` - Controller server logs
- Console output - Real-time status

Log levels: DEBUG, INFO, WARNING, ERROR

## 🤝 Contributing

When adding new features:
1. Update protocol.py for new message types
2. Update both client and controller
3. Add tests
4. Update documentation

## 📄 License

[Your License Here]

## 🙋 Support

For issues:
1. Check logs in `logs/` directory
2. Verify configuration in `configs/config.py`
3. Test individual components
4. Check network connectivity

## 🔄 Workflow Summary

```
1. User runs client with Z and LLRs
   ↓
2. Client sends TASK_REQUEST to controller
   ↓
3. Controller validates and accepts task
   ↓
4. Controller programs FPGA with correct bitfile
   ↓
5. Controller sends FPGA_READY to client
   ↓
6. Client sends LLR data packet to FPGA (raw Ethernet)
   ↓
7. FPGA decodes LLRs
   ↓
8. FPGA sends decoded bits back to client (UDP)
   ↓
9. Client receives and displays results
```

## 📚 Additional Resources

- Vivado Documentation: https://www.xilinx.com/support/documentation/
- LDPC Coding: [Your reference materials]
- Python Socket Programming: https://docs.python.org/3/library/socket.html
