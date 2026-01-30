#!/usr/bin/env python3
"""
LDPC Testbed User Client - WITH TIMING
Sends tasks to controller and communicates with FPGA
Includes detailed timing measurements at each step
"""

import socket
import struct
import time
import sys
import os
import logging
import uuid
from typing import List, Optional, Tuple

# Add parent directory to path
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from common.protocol import (
    ControlMessage, MessageType, TaskRequest, TimingInfo,
    create_task_request_message, pack_llrs_to_payload, unpack_decoded_bits
)
from configs.config import (
    CONTROLLER_HOST, CONTROLLER_CONTROL_PORT,
    CLIENT_IP, CLIENT_DATA_PORT,
    FPGA_IP, FPGA_MAC, FPGA_PORT, FPGA_INTERFACE,
    get_payload_size, get_output_size,
    DECODE_TIMEOUT, MAX_PACKET_RETRIES, PACKET_SEND_INTERVAL
)

class LDPCClient:
    """
    LDPC Testbed Client with Timing
    1. Sends task request to controller
    2. Waits for FPGA ready notification
    3. Sends LLR data packet to FPGA
    4. Receives decoded bits from FPGA
    
    Tracks detailed timing at each step
    """
    
    def __init__(self):
        self.controller_host = CONTROLLER_HOST
        self.controller_port = CONTROLLER_CONTROL_PORT
        
        self.client_ip = CLIENT_IP
        self.client_port = CLIENT_DATA_PORT
        
        self.fpga_ip = FPGA_IP
        self.fpga_mac = FPGA_MAC
        self.fpga_port = FPGA_PORT
        self.interface = FPGA_INTERFACE
        
        # Sockets
        self.control_socket = None
        self.raw_socket = None
        self.receive_socket = None
        
        # MAC address for raw socket
        self.pc_mac = '90E2BA9B4E54'  # Update this for your system
        
        # Timing
        self.timing = None
        
        # Logging
        self.logger = logging.getLogger(__name__)
        self.logger.info("LDPC Client initialized")
    
    def submit_task(self, Z: int, llrs: List[int], bitfile_path: str) -> Tuple[bool, str, Optional[List[int]], Optional[TimingInfo]]:
        """
        Submit a complete decode task
        
        Args:
            Z: Lifting size
            llrs: List of LLR values (must be 50*Z length)
            bitfile_path: Path to .bit file
            
        Returns:
            (success, message, decoded_bits, timing_info)
        """
        task_id = str(uuid.uuid4())[:8]
        
        # Initialize timing tracker
        self.timing = TimingInfo(task_id=task_id)
        
        self.logger.info(f"=" * 70)
        self.logger.info(f"Submitting Task: {task_id}")
        self.logger.info(f"  Z = {Z}")
        self.logger.info(f"  LLRs = {len(llrs)}")
        self.logger.info(f"  Bitfile = {bitfile_path}")
        self.logger.info(f"=" * 70)
        
        try:
            # Step 1: Send task request to controller
            self.logger.info("Step 1: Sending task request to controller...")
            
            # T1: Record timestamp BEFORE sending request
            self.timing.t1_client_send_request = time.time()
            
            task_req = TaskRequest(
                task_id=task_id,
                lifting_size=Z,
                num_llrs=len(llrs),
                llrs=llrs,
                bitfile_path=bitfile_path,
                expected_output_bits=Z * 10,
                timeout_seconds=DECODE_TIMEOUT
            )
            
            # Validate
            valid, error_msg = task_req.validate()
            if not valid:
                return False, f"Invalid task: {error_msg}", None, self.timing
            
            # Send to controller
            success, msg = self._send_task_request(task_req)
            if not success:
                return False, f"Failed to submit task: {msg}", None, self.timing
            
            self.logger.info(f"  ✅ Task accepted by controller")
            
            # Step 2: Wait for FPGA ready
            self.logger.info("Step 2: Waiting for FPGA to be programmed...")
            success, msg, controller_timing = self._wait_for_fpga_ready(task_id)
            if not success:
                return False, f"FPGA programming failed: {msg}", None, self.timing
            
            # T6: Record timestamp AFTER receiving ready
            self.timing.t6_client_recv_ready = time.time()
            
            # Merge controller timing info
            if controller_timing:
                self.timing.t2_controller_recv_request = controller_timing.get('t2')
                self.timing.t3_controller_start_program = controller_timing.get('t3')
                self.timing.t4_controller_finish_program = controller_timing.get('t4')
                self.timing.t5_controller_send_ready = controller_timing.get('t5')
            
            self.logger.info(f"  ✅ FPGA ready")
            
            # Step 3: Send data packet to FPGA
            self.logger.info("Step 3: Sending LLR data to FPGA...")
            
            # T7: Record timestamp BEFORE sending data
            self.timing.t7_client_send_data = time.time()
            
            success, msg = self._send_data_to_fpga(Z, llrs)
            if not success:
                return False, f"Failed to send data: {msg}", None, self.timing
            
            self.logger.info(f"  ✅ Data sent to FPGA")
            
            # Step 4: Receive decoded bits from FPGA
            self.logger.info("Step 4: Waiting for decoded bits from FPGA...")
            decoded_bits = self._receive_decoded_bits(Z)
            
            # T10: Record timestamp AFTER receiving result
            self.timing.t10_client_recv_result = time.time()
            
            if decoded_bits is None:
                return False, "No response from FPGA", None, self.timing
            
            self.logger.info(f"  ✅ Received {len(decoded_bits)} decoded bits")
            
            self.logger.info("=" * 70)
            self.logger.info(f"Task {task_id} completed successfully!")
            self.logger.info("=" * 70)
            
            return True, "Success", decoded_bits, self.timing
            
        except Exception as e:
            self.logger.error(f"Task failed: {e}")
            import traceback
            traceback.print_exc()
            return False, str(e), None, self.timing
    
    def _send_task_request(self, task_req: TaskRequest) -> Tuple[bool, str]:
        """Send task request to controller"""
        try:
            # Connect to controller
            self.control_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.control_socket.settimeout(10.0)
            self.control_socket.connect((self.controller_host, self.controller_port))
            
            # Create and send message
            msg = create_task_request_message(task_req, self.timing.t1_client_send_request)
            self.control_socket.send(msg.to_bytes())
            
            # Wait for response
            header = self._recv_exact(self.control_socket, 4)
            if not header:
                return False, "No response from controller"
            
            length = struct.unpack('!I', header)[0]
            msg_bytes = self._recv_exact(self.control_socket, length)
            if not msg_bytes:
                return False, "Incomplete response from controller"
            
            response = ControlMessage.from_bytes(header + msg_bytes)
            
            if response.msg_type == MessageType.TASK_ACCEPTED:
                return True, "Task accepted"
            elif response.msg_type == MessageType.ERROR:
                return False, response.payload.get('error', 'Unknown error')
            else:
                return False, f"Unexpected response: {response.msg_type.name}"
            
        except Exception as e:
            return False, str(e)
    
    def _wait_for_fpga_ready(self, task_id: str) -> Tuple[bool, str, Optional[dict]]:
        """Wait for FPGA ready notification from controller"""
        try:
            # Controller keeps connection open and will send ready message
            self.control_socket.settimeout(120.0)  # FPGA programming can take time
            
            header = self._recv_exact(self.control_socket, 4)
            if not header:
                return False, "Connection closed", None
            
            length = struct.unpack('!I', header)[0]
            msg_bytes = self._recv_exact(self.control_socket, length)
            if not msg_bytes:
                return False, "Incomplete message", None
            
            response = ControlMessage.from_bytes(header + msg_bytes)
            
            if response.msg_type == MessageType.FPGA_READY:
                # Extract controller timing info from payload
                controller_timing = response.payload.get('timing', {})
                return True, "FPGA ready", controller_timing
            elif response.msg_type == MessageType.ERROR:
                return False, response.payload.get('error', 'Unknown error'), None
            else:
                return False, f"Unexpected message: {response.msg_type.name}", None
            
        except socket.timeout:
            return False, "Timeout waiting for FPGA", None
        except Exception as e:
            return False, str(e), None
    
    def _recv_exact(self, sock: socket.socket, length: int) -> Optional[bytes]:
        """Receive exactly length bytes"""
        data = b''
        while len(data) < length:
            chunk = sock.recv(length - len(data))
            if not chunk:
                return None
            data += chunk
        return data
    
    def _send_data_to_fpga(self, Z: int, llrs: List[int]) -> Tuple[bool, str]:
        """Send LLR data packet to FPGA"""
        try:
            # Setup raw socket for sending
            self.raw_socket = socket.socket(socket.AF_PACKET, socket.SOCK_RAW)
            self.raw_socket.bind((self.interface, 0))
            
            # Calculate payload size
            payload_size = get_payload_size(Z)
            
            # Create payload
            payload = pack_llrs_to_payload(llrs, payload_size)
            
            # Create packet
            packet = self._create_packet(payload)
            
            # Send packet
            self.raw_socket.send(packet)
            
            self.logger.debug(f"Sent {len(packet)} byte packet to FPGA")
            
            return True, "Data sent"
            
        except PermissionError:
            return False, "Root privileges required for raw socket"
        except Exception as e:
            return False, str(e)
    
    def _create_packet(self, payload: bytes) -> bytes:
        """Create complete Ethernet/IP/UDP packet"""
        # UDP Header
        udp_length = len(payload) + 8
        udp_header = struct.pack('!HHHH',
            self.client_port,  # Source port
            self.fpga_port,    # Dest port
            udp_length,
            0  # Checksum (0 = no checksum)
        )
        
        # IP Header
        ip_total_length = 20 + udp_length
        ip_header = struct.pack('!BBHHHBBH4s4s',
            0x45,  # Version & IHL
            0,     # TOS
            ip_total_length,
            0x1234,  # ID
            0x4000,  # Flags & Fragment offset
            64,      # TTL
            17,      # Protocol (UDP)
            0,       # Checksum (calculated below)
            socket.inet_aton(self.client_ip),
            socket.inet_aton(self.fpga_ip)
        )
        
        # Calculate IP checksum
        checksum = 0
        for i in range(0, len(ip_header), 2):
            word = (ip_header[i] << 8) + (ip_header[i+1] if i+1 < len(ip_header) else 0)
            checksum += word
        checksum = (checksum >> 16) + (checksum & 0xFFFF)
        checksum += (checksum >> 16)
        ip_checksum = (~checksum) & 0xFFFF
        
        ip_header = ip_header[:10] + struct.pack('!H', ip_checksum) + ip_header[12:]
        
        # Ethernet Header
        fpga_mac = bytes.fromhex(self.fpga_mac.replace(':', ''))
        pc_mac = bytes.fromhex(self.pc_mac)
        eth_header = fpga_mac + pc_mac + struct.pack('!H', 0x0800)  # IPv4
        
        return eth_header + ip_header + udp_header + payload
    
    def _receive_decoded_bits(self, Z: int) -> Optional[List[int]]:
        """Receive decoded bits from FPGA"""
        try:
            # Setup UDP socket for receiving
            self.receive_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            self.receive_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            self.receive_socket.bind((self.client_ip, self.client_port))
            self.receive_socket.settimeout(DECODE_TIMEOUT)
            
            # Wait for response
            data, addr = self.receive_socket.recvfrom(4096)
            
            # Verify source
            if addr[0] != self.fpga_ip:
                self.logger.warning(f"Received packet from unexpected source: {addr[0]}")
                return None
            
            # Unpack decoded bits
            expected_bits = Z * 10
            decoded_bits = unpack_decoded_bits(data, expected_bits)
            
            self.logger.debug(f"Received {len(data)} bytes = {len(decoded_bits)} bits from FPGA")
            
            return decoded_bits
            
        except socket.timeout:
            self.logger.error("Timeout waiting for FPGA response")
            return None
        except Exception as e:
            self.logger.error(f"Receive error: {e}")
            return None
    
    def cleanup(self):
        """Clean up resources"""
        if self.control_socket:
            self.control_socket.close()
        if self.raw_socket:
            self.raw_socket.close()
        if self.receive_socket:
            self.receive_socket.close()

def generate_test_llrs(Z: int) -> List[int]:
    """Generate test LLRs for given Z"""
    num_llrs = 50 * Z
    llrs = []
    
    # Simple alternating pattern
    for i in range(num_llrs):
        if i % 2 == 0:
            llr = 3
        else:
            llr = -3
        
        # Add variation
        if i % 100 == 0:
            llr = 5 if i % 200 == 0 else -5
        
        # Clamp to 4-bit signed range [-8, 7]
        llr = max(-8, min(7, llr))
        llrs.append(llr)
    
    return llrs

def main():
    """Main function - example usage"""
    # Setup logging
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )
    
    logger = logging.getLogger(__name__)
    
    print("=" * 70)
    print("LDPC Testbed Client - WITH TIMING")
    print("=" * 70)
    
    # Check for root
    if os.geteuid() != 0:
        print("❌ Root privileges required for raw sockets")
        print("💡 Run with: sudo python3 client_with_timing.py")
        sys.exit(1)
    
    # Parse arguments
    if len(sys.argv) < 2:
        print("\nUsage: sudo python3 client_with_timing.py <Z> [bitfile_path]")
        print("\nExample:")
        print("  sudo python3 client_with_timing.py 96")
        print("  sudo python3 client_with_timing.py 192 /path/to/ldpc_z192.bit")
        print("\nSupported Z values: 48, 96, 192, 256, 384")
        sys.exit(1)
    
    try:
        Z = int(sys.argv[1])
        bitfile = sys.argv[2] if len(sys.argv) > 2 else f"/home/ryuk/LDPC_testbed/ldpc_testbed/fpga/bitfiles/ldpc_z{Z}.bit"
        
        print(f"\n🎯 Configuration:")
        print(f"   Z = {Z}")
        print(f"   LLRs = {50 * Z}")
        print(f"   Bitfile = {bitfile}")
        
        # Generate test LLRs
        print(f"\n📊 Generating test LLRs...")
        llrs = generate_test_llrs(Z)
        print(f"   Generated {len(llrs)} LLRs")
        print(f"   Range: [{min(llrs)}, {max(llrs)}]")
        
        # Create client
        client = LDPCClient()
        
        # Submit task
        print(f"\n🚀 Submitting decode task...")
        success, msg, decoded_bits, timing = client.submit_task(Z, llrs, bitfile)
        
        if success:
            print(f"\n✅ Task completed successfully!")
            print(f"   Received {len(decoded_bits)} decoded bits")
            print(f"   First 20 bits: {decoded_bits[:20]}")
            print(f"   Last 20 bits: {decoded_bits[-20:]}")
            
            # Calculate bit statistics
            ones = sum(decoded_bits)
            zeros = len(decoded_bits) - ones
            print(f"\n📈 Statistics:")
            print(f"   Ones: {ones} ({ones/len(decoded_bits)*100:.1f}%)")
            print(f"   Zeros: {zeros} ({zeros/len(decoded_bits)*100:.1f}%)")
            
            # Print timing report
            if timing:
                timing.print_timing_report()
        else:
            print(f"\n❌ Task failed: {msg}")
            
            # Still print timing if available
            if timing:
                timing.print_timing_report()
            
            sys.exit(1)
        
        # Cleanup
        client.cleanup()
        
    except KeyboardInterrupt:
        print("\n\n🛑 Interrupted by user")
    except Exception as e:
        logger.error(f"Error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
    
    print("\n👋 Client finished")

if __name__ == "__main__":
    main()