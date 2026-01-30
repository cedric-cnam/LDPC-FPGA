# LDPC FPGA Testbed

A complete, production-ready testbed for LDPC (Low-Density Parity-Check) decoding with dynamic FPGA programming support.

## 🌟 Features

- **Dynamic FPGA Programming**: Automatically programs FPGA with the correct bitfile based on requested lifting size (Z)
- **Multiple Z Support**: Handles different lifting sizes (Z = 48, 96, 192, 256, 384)
- **Reliable Control Protocol**: TCP-based control messages for task management
- **High-Speed Data Transfer**: Raw Ethernet sockets for maximum throughput
- **Complete Workflow**: From task submission to receiving decoded bits
- **Production Ready**: Error handling, logging, testing, and documentation

## 📁 Project Structure

```
ldpc_testbed/
├── client/
│   └── client.py              # User client application
├── controller/
│   └── controller_server.py   # Controller server (orchestrates workflow)
├── fpga_programmer/
│   ├── program_fpga.tcl       # Vivado TCL script for programming
│   └── fpga_programmer.py     # Python wrapper for TCL script
├── common/
│   ├── protocol.py            # Shared protocol definitions
│   └── __init__.py
├── configs/
│   └── config.py              # Configuration settings
├── docs/
│   ├── README.md              # Detailed documentation
│   └── QUICKSTART.md          # Quick start guide
├── setup.sh                   # Setup script
├── test_system.py             # System tests
├── examples.py                # Usage examples
└── README.md                  # This file
```

## 🚀 Quick Start

### 1. Setup (one-time)
```bash
cd ldpc_testbed
sudo ./setup.sh
```

### 2. Start services

**Terminal 1 - Hardware Server:**
```bash
hw_server
```

**Terminal 2 - Controller:**
```bash
sudo python3 controller/controller_server.py
```

### 3. Run a decode task

**Terminal 3 - Client:**
```bash
sudo python3 client/client.py 96
```

That's it! See [QUICKSTART.md](docs/QUICKSTART.md) for detailed instructions.

## 📖 Documentation

- **[Quick Start Guide](docs/QUICKSTART.md)** - Get running in 5 minutes
- **[Full Documentation](docs/README.md)** - Complete reference
- **[Examples](examples.py)** - Usage examples and patterns

## 🎯 Use Cases

1. **Research**: Test LDPC decoding algorithms with different parameters
2. **Hardware Verification**: Validate FPGA implementations
3. **Performance Testing**: Benchmark throughput and latency
4. **Integration Testing**: Test complete communication systems
5. **Education**: Learn LDPC coding and FPGA programming

## 🏗️ Architecture

```
┌─────────────┐  Control    ┌──────────────┐  JTAG      ┌─────────┐
│    User     │  Messages   │  Controller  │  Programs  │  FPGA   │
│   Client    │ <────────> │   Server     │ ────────> │ Hardware│
└─────────────┘   (TCP)     └──────────────┘  (Vivado)  └─────────┘
       │                                                       │
       │               LLR Data Packets (Raw Ethernet)        │
       └───────────────────────────────────────────────────────┘
                       Decoded Bits (UDP)
```

## 🔧 Requirements

**Hardware:**
- FPGA board with LDPC decoder
- Network connection to FPGA
- JTAG programmer

**Software:**
- Python 3.8+
- Xilinx Vivado (with hw_server)
- Linux (Ubuntu/CentOS recommended)
- Root privileges (for raw sockets)

## 📊 Workflow

1. **Client** sends task request (Z, LLRs, bitfile) to **Controller**
2. **Controller** validates task and programs **FPGA** via Vivado
3. **Controller** notifies **Client** when FPGA is ready
4. **Client** sends LLR data packet to **FPGA**
5. **FPGA** decodes LLRs and returns decoded bits
6. **Client** receives and displays results

## 🧪 Testing

```bash
# Run system tests
sudo python3 test_system.py

# Run examples
sudo python3 examples.py 0  # All examples
sudo python3 examples.py 1  # Basic usage
sudo python3 examples.py 3  # Batch decoding
```

## 📝 Example Usage

```python
from client.client import LDPCClient, generate_test_llrs

# Create client
client = LDPCClient()

# Generate test data
Z = 96
llrs = generate_test_llrs(Z)  # 4800 LLRs for Z=96

# Submit decode task
success, msg, decoded_bits = client.submit_task(
    Z=96,
    llrs=llrs,
    bitfile_path="/home/fpga/bitfiles/ldpc_z96.bit"
)

if success:
    print(f"✅ Decoded {len(decoded_bits)} bits!")
    print(f"Results: {decoded_bits[:20]}...")  # First 20 bits
else:
    print(f"❌ Failed: {msg}")

client.cleanup()
```

## ⚙️ Configuration

Edit `configs/config.py`:

```python
# Network
CONTROLLER_HOST = "192.168.1.1"
FPGA_IP = "192.168.1.128"
FPGA_INTERFACE = "enp2s0f0"

# Vivado
VIVADO_PATH = "/tools/Xilinx/Vivado/2023.2/bin/vivado"

# Bitfiles
BITFILE_DIR = "/home/fpga/bitfiles"
BITFILE_MAP = {
    48:  "/home/fpga/bitfiles/ldpc_z48.bit",
    96:  "/home/fpga/bitfiles/ldpc_z96.bit",
    192: "/home/fpga/bitfiles/ldpc_z192.bit",
}
```

## 🔍 Supported Z Values

| Z   | LLRs  | Payload Bytes | Output Bits | Output Bytes |
|-----|-------|---------------|-------------|--------------|
| 48  | 2,400 | 1,200         | 480         | 60           |
| 96  | 4,800 | 2,400         | 960         | 120          |
| 192 | 9,600 | 4,800         | 1,920       | 240          |
| 256 | 12,800| 6,400         | 2,560       | 320          |
| 384 | 19,200| 9,600         | 3,840       | 480          |

## 🐛 Troubleshooting

| Issue | Solution |
|-------|----------|
| "No hardware targets found" | Start hw_server: `hw_server` |
| "Connection refused" | Check controller is running |
| "Root privileges required" | Run with `sudo` |
| "FPGA not responding" | Check: `ping 192.168.1.128` |
| "Bitfile not found" | Verify path in config |

See [docs/README.md](docs/README.md) for detailed troubleshooting.

## 📦 Components

### Controller Server
- Manages FPGA programming
- Handles task queue
- Coordinates workflow
- Logs all operations

### Client Application
- Submits decode tasks
- Sends LLR data to FPGA
- Receives decoded bits
- Provides Python API

### FPGA Programmer
- Wraps Vivado TCL script
- Programs FPGA via JTAG
- Validates programming
- Error handling

### Protocol Layer
- Task requests/responses
- Status messages
- Error handling
- Data serialization

## 🔐 Security Notes

- Raw sockets require root privileges
- Control protocol uses plain TCP (add TLS for production)
- Validate all inputs
- Limit concurrent connections

## 📈 Performance

- **Programming Time**: ~30-60 seconds per bitfile
- **Decode Latency**: ~100ms (hardware dependent)
- **Throughput**: Limited by FPGA processing speed
- **Network Overhead**: Minimal with raw sockets

## 🤝 Contributing

This testbed is designed to be extended. Some ideas:

- Add support for more Z values
- Implement TLS for control channel
- Add web interface for monitoring
- Support for multiple FPGAs
- Performance profiling tools
- Automated regression testing


**Ready to start decoding? Run `./setup.sh` and see the Quick Start guide!** 🚀
