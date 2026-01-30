#!/usr/bin/env python3
"""
LDPC Testbed Status Monitor
Checks system status and provides diagnostics
"""

import socket
import subprocess
import os
import sys

def check_item(name: str, check_func, fix_hint: str = "") -> bool:
    """Check a single item and print status"""
    try:
        result, msg = check_func()
        if result:
            print(f"✅ {name}: {msg}")
            return True
        else:
            print(f"❌ {name}: {msg}")
            if fix_hint:
                print(f"   💡 {fix_hint}")
            return False
    except Exception as e:
        print(f"❌ {name}: Error - {e}")
        return False

def check_root():
    """Check if running as root"""
    if os.geteuid() == 0:
        return True, "Running as root"
    else:
        return False, "Not running as root"

def check_python_version():
    """Check Python version"""
    import sys
    version = sys.version_info
    if version >= (3, 8):
        return True, f"Python {version.major}.{version.minor}.{version.micro}"
    else:
        return False, f"Python {version.major}.{version.minor}.{version.micro} (need 3.8+)"

def check_hw_server():
    """Check if hw_server is running"""
    try:
        result = subprocess.run(['pgrep', '-f', 'hw_server'], 
                              capture_output=True, text=True, timeout=2)
        if result.returncode == 0:
            pids = result.stdout.strip().split('\n')
            return True, f"Running (PID: {', '.join(pids)})"
        else:
            return False, "Not running"
    except Exception as e:
        return False, f"Check failed: {e}"

def check_controller():
    """Check if controller is reachable"""
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(2)
        result = sock.connect_ex(('192.168.1.1', 8000))
        sock.close()
        if result == 0:
            return True, "Controller reachable on port 8000"
        else:
            return False, "Controller not reachable on port 8000"
    except Exception as e:
        return False, f"Check failed: {e}"

def check_fpga_network():
    """Check if FPGA is reachable"""
    try:
        result = subprocess.run(['ping', '-c', '1', '-W', '2', '192.168.1.128'],
                              capture_output=True, timeout=3)
        if result.returncode == 0:
            return True, "FPGA reachable at 192.168.1.128"
        else:
            return False, "FPGA not reachable at 192.168.1.128"
    except Exception as e:
        return False, f"Check failed: {e}"

def check_interface():
    """Check network interface"""
    interface = "enp2s0f0"
    try:
        result = subprocess.run(['ip', 'link', 'show', interface],
                              capture_output=True, text=True, timeout=2)
        if result.returncode == 0:
            # Check if up
            if "UP" in result.stdout:
                return True, f"Interface {interface} is UP"
            else:
                return False, f"Interface {interface} is DOWN"
        else:
            return False, f"Interface {interface} not found"
    except Exception as e:
        return False, f"Check failed: {e}"

def check_vivado():
    """Check if Vivado is installed"""
    vivado_paths = [
        "/tools/Xilinx/Vivado/2023.2/bin/vivado",
        "/opt/Xilinx/Vivado/2023.2/bin/vivado",
        "/tools/Xilinx/Vivado/2022.2/bin/vivado",
    ]
    
    for path in vivado_paths:
        if os.path.exists(path):
            return True, f"Found at {path}"
    
    return False, "Not found in common locations"

def check_bitfiles():
    """Check if bitfiles exist"""
    bitfile_dir = "/home/fpga/bitfiles"
    
    if not os.path.exists(bitfile_dir):
        return False, f"Directory {bitfile_dir} does not exist"
    
    bitfiles = [f for f in os.listdir(bitfile_dir) if f.endswith('.bit')]
    
    if bitfiles:
        return True, f"Found {len(bitfiles)} bitfiles: {', '.join(bitfiles[:3])}"
    else:
        return False, f"No .bit files in {bitfile_dir}"

def check_directories():
    """Check if project directories exist"""
    required_dirs = [
        'client',
        'controller',
        'fpga_programmer',
        'common',
        'configs',
        'docs'
    ]
    
    missing = []
    for d in required_dirs:
        if not os.path.exists(d):
            missing.append(d)
    
    if not missing:
        return True, "All project directories present"
    else:
        return False, f"Missing directories: {', '.join(missing)}"

def main():
    """Main status check"""
    print("=" * 70)
    print("LDPC Testbed Status Check")
    print("=" * 70)
    print()
    
    checks = [
        ("Python Version", check_python_version, ""),
        ("Root Privileges", check_root, "Run with: sudo python3 status.py"),
        ("Project Structure", check_directories, "Re-extract the project"),
        ("Vivado Installation", check_vivado, "Update VIVADO_PATH in configs/config.py"),
        ("Hardware Server", check_hw_server, "Start with: hw_server"),
        ("Network Interface", check_interface, "Run setup.sh or configure manually"),
        ("FPGA Network", check_fpga_network, "Check FPGA power and connection"),
        ("Controller Server", check_controller, "Start with: sudo python3 controller/controller_server.py"),
        ("Bitfiles", check_bitfiles, "Copy .bit files to /home/fpga/bitfiles/"),
    ]
    
    results = []
    for name, check_func, hint in checks:
        result = check_item(name, check_func, hint)
        results.append((name, result))
        print()
    
    # Summary
    print("=" * 70)
    print("Summary")
    print("=" * 70)
    
    passed = sum(1 for _, result in results if result)
    total = len(results)
    
    print(f"\nPassed: {passed}/{total}")
    
    if passed == total:
        print("\n✅ All checks passed! System is ready.")
        print("\nNext steps:")
        print("1. Start hw_server (if not running): hw_server")
        print("2. Start controller: sudo python3 controller/controller_server.py")
        print("3. Run client: sudo python3 client/client.py 96")
    else:
        print(f"\n⚠️  {total - passed} check(s) failed. Please fix the issues above.")
        print("\nCommon fixes:")
        print("- Run as root: sudo python3 status.py")
        print("- Start hw_server: hw_server")
        print("- Configure network: sudo ./setup.sh")
        print("- Start controller: sudo python3 controller/controller_server.py")
    
    print()
    
    # Detailed diagnostic info
    if len(sys.argv) > 1 and sys.argv[1] == "-v":
        print("=" * 70)
        print("Detailed Diagnostic Information")
        print("=" * 70)
        print()
        
        print("Network Configuration:")
        try:
            result = subprocess.run(['ip', 'addr'], capture_output=True, text=True)
            print(result.stdout)
        except:
            print("  Could not get network info")
        
        print("\nProcesses:")
        try:
            result = subprocess.run(['ps', 'aux'], capture_output=True, text=True)
            lines = [l for l in result.stdout.split('\n') 
                    if 'hw_server' in l or 'controller' in l or 'vivado' in l]
            for line in lines:
                print(f"  {line}")
        except:
            print("  Could not get process info")
    
    sys.exit(0 if passed == total else 1)

if __name__ == "__main__":
    main()
