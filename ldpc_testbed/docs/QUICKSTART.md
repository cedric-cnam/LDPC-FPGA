# LDPC Testbed Quick Start Guide

Get up and running in 5 minutes!

## Prerequisites

- FPGA board connected to network
- Vivado with hw_server installed
- Root access (for raw sockets)
- Python 3.8+

## Step 1: Setup (One-time)

```bash
# Clone/extract the testbed
cd ldpc_testbed

# Run setup script
sudo ./setup.sh

# Follow the prompts to:
# - Configure network interface
# - Set Vivado path
# - Create directories
```

## Step 2: Prepare Bitfiles

```bash
# Create bitfile directory
sudo mkdir -p /home/fpga/bitfiles

# Copy your FPGA bitfiles
sudo cp ldpc_z48.bit /home/fpga/bitfiles/
sudo cp ldpc_z96.bit /home/fpga/bitfiles/
sudo cp ldpc_z192.bit /home/fpga/bitfiles/
# etc.
```

## Step 3: Start Services

### Terminal 1: Hardware Server
```bash
hw_server
```

Expected output:
```
****** Xilinx hw_server v2023.2
INFO: hw_server application started
```

### Terminal 2: Controller
```bash
cd ldpc_testbed
sudo python3 controller/controller_server.py
```

Expected output:
```
======================================================================
LDPC Testbed Controller Server
======================================================================
✅ Controller running
   Control port: 8000
```

## Step 4: Run Your First Decode

### Terminal 3: Client
```bash
cd ldpc_testbed
sudo python3 client/client.py 96
```

Expected output:
```
======================================================================
Submitting Task: abc12345
  Z = 96
  LLRs = 4800
======================================================================
Step 1: Sending task request to controller...
  ✅ Task accepted by controller
Step 2: Waiting for FPGA to be programmed...
  ✅ FPGA ready
Step 3: Sending LLR data to FPGA...
  ✅ Data sent to FPGA
Step 4: Waiting for decoded bits from FPGA...
  ✅ Received 960 decoded bits
======================================================================
Task abc12345 completed successfully!
======================================================================
✅ Task completed successfully!
   Received 960 decoded bits
```

## Common Commands

### Decode with specific Z value
```bash
sudo python3 client/client.py 48   # Z=48
sudo python3 client/client.py 96   # Z=96
sudo python3 client/client.py 192  # Z=192
```

### Use custom bitfile
```bash
sudo python3 client/client.py 96 /path/to/my_ldpc.bit
```

### Run examples
```bash
sudo python3 examples.py 1  # Basic usage
sudo python3 examples.py 3  # Batch decoding
sudo python3 examples.py 0  # All examples
```

### Test the system
```bash
sudo python3 test_system.py
```

## Troubleshooting Quick Fixes

### "No hardware targets found"
→ Start hw_server: `hw_server`

### "Connection refused" from client
→ Check controller is running

### "Root privileges required"
→ Run with `sudo`

### "FPGA not responding"
→ Check: `ping 192.168.1.128`

### "Bitfile not found"
→ Check: `ls /home/fpga/bitfiles/`

## Configuration Files

All settings are in `configs/config.py`:

```python
# Network
CONTROLLER_HOST = "192.168.1.1"
CONTROLLER_CONTROL_PORT = 8000

FPGA_IP = "192.168.1.128"
FPGA_PORT = 1234
FPGA_INTERFACE = "enp2s0f0"

# Vivado
VIVADO_PATH = "/tools/Xilinx/Vivado/2023.2/bin/vivado"

# Bitfiles
BITFILE_DIR = "/home/fpga/bitfiles"
```

## Python API Usage

```python
from client.client import LDPCClient, generate_test_llrs

# Create client
client = LDPCClient()

# Generate LLRs
Z = 96
llrs = generate_test_llrs(Z)

# Decode
success, msg, decoded_bits = client.submit_task(
    Z=Z,
    llrs=llrs,
    bitfile_path="/home/fpga/bitfiles/ldpc_z96.bit"
)

if success:
    print(f"Decoded {len(decoded_bits)} bits!")
    print(f"Bits: {decoded_bits}")

# Cleanup
client.cleanup()
```

## Custom LLRs

```python
# Create your own LLRs
Z = 48
num_llrs = 50 * Z  # Must be exactly 50*Z

llrs = []
for i in range(num_llrs):
    llr = compute_my_llr(i)  # Your function
    llr = max(-8, min(7, llr))  # Clamp to [-8, 7]
    llrs.append(llr)

# Use them
client.submit_task(Z, llrs, "ldpc_z48.bit")
```

## What's Happening Under the Hood

1. **Client** sends task request to **Controller** (TCP)
2. **Controller** programs **FPGA** with correct bitfile (JTAG via Vivado)
3. **Controller** notifies **Client** FPGA is ready (TCP)
4. **Client** sends LLR data to **FPGA** (Raw Ethernet/UDP)
5. **FPGA** decodes and sends result back to **Client** (UDP)

## Next Steps

- Read full documentation: `docs/README.md`
- Try examples: `sudo python3 examples.py 0`
- Run system tests: `sudo python3 test_system.py`
- Customize for your application

## Support

Check logs:
- `logs/controller.log` - Controller logs
- Console output - Real-time status

Common issues:
- Network connectivity: `ping 192.168.1.128`
- Hardware server: `pgrep hw_server`
- Bitfiles: `ls /home/fpga/bitfiles/`
- Permissions: Run with `sudo`

## Architecture Diagram

```
User PC (192.168.1.1)          FPGA (192.168.1.128)
├── Controller Server          └── LDPC Decoder Core
│   ├── Control (TCP:8000)         ├── Receives LLRs (UDP:1234)
│   └── FPGA Programmer            └── Sends Decoded Bits
└── Client
    ├── Sends Control Msgs
    ├── Sends LLR Data
    └── Receives Results
```

---

**That's it! You're ready to start decoding with your FPGA!** 🚀
