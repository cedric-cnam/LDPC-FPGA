#!/bin/bash
# LDPC Testbed Setup Script

echo "========================================"
echo "LDPC Testbed Setup"
echo "========================================"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored messages
print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ️  $1${NC}"
}

# Check if running as root for network setup
if [ "$EUID" -ne 0 ]; then 
    print_error "Please run as root (needed for network setup)"
    echo "Usage: sudo ./setup.sh"
    exit 1
fi

print_info "Starting setup..."
echo ""

# 1. Check Python version
print_info "Checking Python version..."
PYTHON_VERSION=$(python3 --version 2>&1 | awk '{print $2}')
REQUIRED_VERSION="3.8"

if python3 -c "import sys; exit(0 if sys.version_info >= (3, 8) else 1)"; then
    print_success "Python $PYTHON_VERSION (OK)"
else
    print_error "Python 3.8+ required (found $PYTHON_VERSION)"
    exit 1
fi

# 2. Create directory structure
print_info "Creating directory structure..."
mkdir -p logs
mkdir -p /home/fpga/bitfiles 2>/dev/null || print_info "Could not create /home/fpga/bitfiles (you may need to create manually)"
print_success "Directories created"

# 3. Make scripts executable
print_info "Making scripts executable..."
chmod +x client/client.py
chmod +x controller/controller_server.py
chmod +x fpga_programmer/fpga_programmer.py
print_success "Scripts are executable"

# 4. Check for Vivado
print_info "Checking for Vivado..."
VIVADO_PATHS=(
    "/home/ryuk/Xilinx2/Vivado/2020.2/bin/vivado"
    "/opt/Xilinx/Vivado/2023.2/bin/vivado"
    "/tools/Xilinx/Vivado/2022.2/bin/vivado"
    "/opt/Xilinx/Vivado/2022.2/bin/vivado"
)

VIVADO_FOUND=""
for path in "${VIVADO_PATHS[@]}"; do
    if [ -f "$path" ]; then
        VIVADO_FOUND="$path"
        break
    fi
done

if [ -n "$VIVADO_FOUND" ]; then
    print_success "Vivado found at: $VIVADO_FOUND"
    echo "   Update VIVADO_PATH in configs/config.py if different"
else
    print_error "Vivado not found in common locations"
    echo "   Please update VIVADO_PATH in configs/config.py"
fi

# 5. Network Interface Setup
echo ""
print_info "Network Interface Setup"
echo "----------------------------------------"

# List available interfaces
echo "Available network interfaces:"
ip link show | grep -E '^[0-9]+:' | awk '{print $2}' | sed 's/://g' | while read iface; do
    echo "  - $iface"
done

echo ""
read -p "Enter network interface for FPGA (default: enp2s0f0): " INTERFACE
INTERFACE=${INTERFACE:-enp2s0f0}

if ip link show "$INTERFACE" > /dev/null 2>&1; then
    print_success "Interface $INTERFACE exists"
    
    # Configure interface
    print_info "Configuring interface $INTERFACE..."
    
    # Set IP address
    ip addr add 192.168.1.1/24 dev "$INTERFACE" 2>/dev/null
    ip link set "$INTERFACE" up
    
    # Set MTU
    ip link set "$INTERFACE" mtu 9000 2>/dev/null
    
    print_success "Interface configured (IP: 192.168.1.1, MTU: 9000)"
else
    print_error "Interface $INTERFACE not found"
    echo "   Please update FPGA_INTERFACE in configs/config.py"
fi

# 6. Check for hw_server
echo ""
print_info "Checking for hw_server..."
if pgrep -f "hw_server" > /dev/null; then
    print_success "hw_server is running"
else
    print_error "hw_server is not running"
    echo "   Start with: hw_server"
    echo "   (Required for FPGA programming)"
fi

# 7. Test network connectivity
echo ""
print_info "Testing FPGA connectivity..."
if timeout 2 ping -c 1 192.168.1.128 > /dev/null 2>&1; then
    print_success "FPGA is reachable at 192.168.1.128"
else
    print_error "Cannot reach FPGA at 192.168.1.128"
    echo "   Make sure FPGA is powered on and connected"
    echo "   You may need to configure FPGA IP address"
fi

# 8. Summary
echo ""
echo "========================================"
echo "Setup Summary"
echo "========================================"
echo ""

if [ -n "$VIVADO_FOUND" ]; then
    print_success "Vivado: $VIVADO_FOUND"
else
    print_error "Vivado: Not found - update config"
fi

print_success "Interface: $INTERFACE configured"
print_success "Directories: Created"
print_success "Scripts: Executable"

echo ""
echo "Next Steps:"
echo "1. Copy bitfiles to /home/fpga/bitfiles/"
echo "   - ldpc_z48.bit"
echo "   - ldpc_z96.bit"
echo "   - ldpc_z192.bit"
echo "   etc."
echo ""
echo "2. Update configs/config.py with your settings"
echo "   - VIVADO_PATH (if not $VIVADO_FOUND)"
echo "   - FPGA_INTERFACE (if not $INTERFACE)"
echo "   - BITFILE_DIR"
echo ""
echo "3. Start hw_server (if not running):"
echo "   $ hw_server"
echo ""
echo "4. Start controller:"
echo "   $ sudo python3 controller/controller_server.py"
echo ""
echo "5. Run client:"
echo "   $ sudo python3 client/client.py 96"
echo ""
print_success "Setup complete!"
echo ""
