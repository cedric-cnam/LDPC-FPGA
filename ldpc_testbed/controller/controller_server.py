#!/usr/bin/env python3
"""
LDPC Testbed Controller Server - WITH TIMING
Manages FPGA programming and orchestrates decode tasks
Includes detailed timing measurements at each step
"""

import socket
import threading
import time
import logging
import sys
import os
from typing import Optional, Dict
from queue import Queue, Empty

# Add parent directory to path
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from common.protocol import (
    ControlMessage, MessageType, TaskRequest, FPGAStatus, TimingInfo,
    create_status_response, create_fpga_ready_message, create_error_message
)
from configs.config import (
    CONTROLLER_HOST, CONTROLLER_CONTROL_PORT, CONTROLLER_DATA_PORT,
    FPGA_IP, FPGA_PORT, BITFILE_MAP,
    FPGA_PROGRAM_TIMEOUT, DECODE_TIMEOUT, CONTROL_SOCKET_TIMEOUT
)
from fpga_programmer.fpga_programmer import FPGAProgrammer

class ControllerServer:
    """
    Main controller server with timing
    - Listens for control messages from clients
    - Programs FPGA with appropriate bitfile
    - Notifies clients when FPGA is ready
    - Monitors decode process
    - Tracks timing at each step
    """
    
    def __init__(self, vivado_path: str, tcl_script_path: str):
        self.host = CONTROLLER_HOST
        self.control_port = CONTROLLER_CONTROL_PORT
        self.data_port = CONTROLLER_DATA_PORT
        
        # FPGA Programmer
        self.fpga_programmer = FPGAProgrammer(vivado_path, tcl_script_path)
        
        # State
        self.fpga_status = FPGAStatus.IDLE
        self.current_task: Optional[TaskRequest] = None
        self.running = False
        
        self.last_programmed_bitfile = None
        
        # Timing tracking
        self.task_timings: Dict[str, TimingInfo] = {}
        
        # Sockets
        self.control_socket = None
        self.data_socket = None
        
        # Threads
        self.control_thread = None
        self.monitor_thread = None
        
        # Task queue
        self.task_queue = Queue()
        
        # Logging
        self.logger = logging.getLogger(__name__)
        self.logger.info(f"Controller initialized")
        self.logger.info(f"  Control: {self.host}:{self.control_port}")
        self.logger.info(f"  Data: {self.host}:{self.data_port}")
    
    def start(self):
        """Start the controller server"""
        self.logger.info("Starting controller server...")
        
        # Setup sockets
        if not self._setup_sockets():
            return False
        
        # Verify hardware server
        self.logger.info("Verifying Vivado hardware server...")
        running, msg = self.fpga_programmer.verify_hardware_server()
        if not running:
            self.logger.error(msg)
            self.logger.error("Start hardware server with: hw_server")
            return False
        self.logger.info(msg)
        
        # Start threads
        self.running = True
        
        self.control_thread = threading.Thread(target=self._control_loop, daemon=True)
        self.control_thread.start()
        
        self.monitor_thread = threading.Thread(target=self._monitor_loop, daemon=True)
        self.monitor_thread.start()
        
        self.logger.info("✅ Controller server started")
        return True
    
    def _setup_sockets(self) -> bool:
        """Setup control and data sockets"""
        try:
            # Control socket (TCP for reliable control messages)
            self.control_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.control_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            self.control_socket.bind((self.host, self.control_port))
            self.control_socket.listen(5)
            self.control_socket.settimeout(CONTROL_SOCKET_TIMEOUT)
            
            # Data socket (UDP for receiving decoded data from FPGA)
            self.data_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            self.data_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            self.data_socket.bind((self.host, self.data_port))
            self.data_socket.settimeout(1.0)
            
            self.logger.info("Sockets ready")
            return True
            
        except Exception as e:
            self.logger.error(f"Socket setup failed: {e}")
            return False
    
    def _control_loop(self):
        """Handle control connections from clients"""
        self.logger.info("Control loop started")
        
        while self.running:
            try:
                # Accept client connection
                client_sock, client_addr = self.control_socket.accept()
                self.logger.info(f"Client connected: {client_addr}")
                
                # Handle client in separate thread
                client_thread = threading.Thread(
                    target=self._handle_client,
                    args=(client_sock, client_addr),
                    daemon=True
                )
                client_thread.start()
                
            except socket.timeout:
                continue
            except Exception as e:
                if self.running:
                    self.logger.error(f"Control loop error: {e}")
    
    def _handle_client(self, client_sock: socket.socket, client_addr: tuple):
        """Handle a single client connection"""
        try:
            # Receive control message
            # First get length
            header = self._recv_exact(client_sock, 4)
            if not header:
                return
            
            import struct
            length = struct.unpack('!I', header)[0]
            
            # Get full message
            msg_bytes = self._recv_exact(client_sock, length)
            if not msg_bytes:
                return
            
            full_msg = header + msg_bytes
            
            # Parse message
            msg = ControlMessage.from_bytes(full_msg)
            
            # T2: Record when controller receives request
            t2_recv = time.time()
            
            self.logger.info(f"Received {msg.msg_type.name} from {client_addr}")
            
            # Handle message
            if msg.msg_type == MessageType.TASK_REQUEST:
                self._handle_task_request(msg, client_sock, client_addr, t2_recv)
            
            elif msg.msg_type == MessageType.STATUS_QUERY:
                self._handle_status_query(msg, client_sock)
            
            elif msg.msg_type == MessageType.CANCEL_TASK:
                self._handle_cancel_task(msg, client_sock)
            
            else:
                self.logger.warning(f"Unknown message type: {msg.msg_type}")
            
        except Exception as e:
            self.logger.error(f"Client handler error: {e}")
            import traceback
            traceback.print_exc()
        finally:
            pass
    
    def _recv_exact(self, sock: socket.socket, length: int) -> Optional[bytes]:
        """Receive exactly length bytes"""
        data = b''
        while len(data) < length:
            chunk = sock.recv(length - len(data))
            if not chunk:
                return None
            data += chunk
        return data
    
    def _handle_task_request(self, msg: ControlMessage, client_sock: socket.socket, 
                            client_addr: tuple, t2_recv: float):
        """Handle task request from client"""
        task_req = TaskRequest.from_dict(msg.payload)
        
        # Create timing tracker for this task
        timing = TimingInfo(task_id=task_req.task_id)
        timing.t1_client_send_request = msg.client_timestamp  # Get from message
        timing.t2_controller_recv_request = t2_recv
        self.task_timings[task_req.task_id] = timing
        
        self.logger.info(f"Task request: {task_req.task_id} (Z={task_req.lifting_size})")
        
        # Validate task
        valid, error_msg = task_req.validate()
        if not valid:
            self.logger.error(f"Invalid task: {error_msg}")
            response = create_error_message(task_req.task_id, error_msg, time.time())
            client_sock.send(response.to_bytes())
            return
        
        # Check if FPGA is busy
        if self.fpga_status != FPGAStatus.IDLE:
            error_msg = f"FPGA busy (status: {self.fpga_status.value})"
            self.logger.warning(error_msg)
            response = create_error_message(task_req.task_id, error_msg, time.time())
            client_sock.send(response.to_bytes())
            return
        
        # Accept task
        self.current_task = task_req
        self.fpga_status = FPGAStatus.PROGRAMMING
        
        # Send acceptance
        accept_msg = ControlMessage(
            msg_type=MessageType.TASK_ACCEPTED,
            task_id=task_req.task_id,
            payload={'message': 'Task accepted, programming FPGA...'},
            timestamp=time.time()
        )
        client_sock.send(accept_msg.to_bytes())
        
        # Store client info for later notification
        self.client_sock = client_sock
        self.client_addr = client_addr
        
        # Add to queue for processing
        self.task_queue.put(task_req)
    
    def _handle_status_query(self, msg: ControlMessage, client_sock: socket.socket):
        """Handle status query"""
        status_msg = "FPGA is " + self.fpga_status.value
        if self.current_task:
            status_msg += f" (Task: {self.current_task.task_id})"
        
        response = create_status_response(
            msg.task_id,
            self.fpga_status,
            status_msg,
            time.time()
        )
        client_sock.send(response.to_bytes())
    
    def _handle_cancel_task(self, msg: ControlMessage, client_sock: socket.socket):
        """Handle task cancellation"""
        if self.current_task and self.current_task.task_id == msg.task_id:
            self.logger.info(f"Cancelling task: {msg.task_id}")
            self.current_task = None
            self.fpga_status = FPGAStatus.IDLE
            
            response = ControlMessage(
                msg_type=MessageType.TASK_COMPLETE,
                task_id=msg.task_id,
                payload={'message': 'Task cancelled'},
                timestamp=time.time()
            )
            client_sock.send(response.to_bytes())
        else:
            response = create_error_message(
                msg.task_id,
                "No such task running",
                time.time()
            )
            client_sock.send(response.to_bytes())
    
    def _monitor_loop(self):
        """Monitor and process tasks"""
        self.logger.info("Monitor loop started")
        
        while self.running:
            try:
                # Get task from queue (blocking with timeout)
                task = self.task_queue.get(timeout=1.0)
                
                # Process task
                self._process_task(task)
                
            except Empty:
                continue
            except Exception as e:
                self.logger.error(f"Monitor loop error: {e}")
                import traceback
                traceback.print_exc()
    
    def _process_task(self, task: TaskRequest):
        """Process a decode task"""
        self.logger.info(f"Processing task: {task.task_id}")
        
        # Get timing tracker
        timing = self.task_timings.get(task.task_id)
        if not timing:
            timing = TimingInfo(task_id=task.task_id)
            self.task_timings[task.task_id] = timing
        
        try:
            # Get bitfile for this Z
            bitfile = task.bitfile_path
            if not os.path.exists(bitfile):
                # Try from BITFILE_MAP
                bitfile = BITFILE_MAP.get(task.lifting_size)
                if not bitfile or not os.path.exists(bitfile):
                    raise FileNotFoundError(f"Bitfile not found for Z={task.lifting_size}")
            
            # Check if FPGA already programmed with this bitfile
            if hasattr(self, 'last_programmed_bitfile') and self.last_programmed_bitfile == bitfile:
                self.logger.info(f"FPGA already programmed with {bitfile}, skipping programming")
                success = True
                msg = "Using already-programmed FPGA"
                
                # Set dummy timing for skipped programming
                timing.t3_controller_start_program = time.time()
                timing.t4_controller_finish_program = time.time()
            else:
                # Program FPGA
                self.logger.info(f"Programming FPGA with: {bitfile}")
                self.fpga_status = FPGAStatus.PROGRAMMING
                
                # T3: Record when programming starts
                timing.t3_controller_start_program = time.time()
                
                success, msg = self.fpga_programmer.program_fpga(bitfile, FPGA_PROGRAM_TIMEOUT)
                
                # T4: Record when programming finishes
                timing.t4_controller_finish_program = time.time()
                
                if not success:
                    raise Exception(f"FPGA programming failed: {msg}")
                
                # Remember what we programmed
                self.last_programmed_bitfile = bitfile
                self.logger.info(f"FPGA programmed successfully")
            
            # Notify client FPGA is ready
            self.fpga_status = FPGAStatus.READY
            
            # T5: Record when sending ready message
            timing.t5_controller_send_ready = time.time()
            
            # Create ready message with timing info
            ready_msg = create_fpga_ready_message(
                task.task_id,
                FPGA_IP,
                FPGA_PORT,
                timing.t5_controller_send_ready
            )
            
            # Add timing info to payload
            ready_msg.payload['timing'] = {
                't2': timing.t2_controller_recv_request,
                't3': timing.t3_controller_start_program,
                't4': timing.t4_controller_finish_program,
                't5': timing.t5_controller_send_ready
            }
            
            if hasattr(self, 'client_sock'):
                self.client_sock.send(ready_msg.to_bytes())
                self.logger.info(f"Notified client that FPGA is ready")
                
                # Log controller-side timing
                prog_time = (timing.t4_controller_finish_program - timing.t3_controller_start_program) * 1000
                self.logger.info(f"⏱️  Programming time: {prog_time:.2f} ms")
                
                self.client_sock.close()
            
            # Wait for decode to complete (client will send data to FPGA)
            # Monitor for decoded response from FPGA
            self.fpga_status = FPGAStatus.DECODING
            
            # For now, just wait and mark as complete
            # In real system, would monitor FPGA responses
            time.sleep(1.0)
            
            self.fpga_status = FPGAStatus.IDLE
            self.current_task = None
            
            self.logger.info(f"Task completed: {task.task_id}")
            
        except Exception as e:
            self.logger.error(f"Task processing error: {e}")
            self.fpga_status = FPGAStatus.ERROR
            
            # Notify client of error
            if hasattr(self, 'client_sock'):
                try:
                    error_msg = create_error_message(task.task_id, str(e), time.time())
                    self.client_sock.send(error_msg.to_bytes())
                except:
                    pass
            
            # Reset state
            time.sleep(2.0)
            self.fpga_status = FPGAStatus.IDLE
            self.current_task = None
    
    def stop(self):
        """Stop the controller"""
        self.logger.info("Stopping controller...")
        self.running = False
        
        if self.control_socket:
            self.control_socket.close()
        if self.data_socket:
            self.data_socket.close()
        
        self.logger.info("Controller stopped")

def main():
    """Main function"""
    # Setup logging
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
        handlers=[
            logging.FileHandler('controller.log'),
            logging.StreamHandler()
        ]
    )
    
    logger = logging.getLogger(__name__)
    
    print("=" * 70)
    print("LDPC Testbed Controller Server - WITH TIMING")
    print("=" * 70)
    
    # Paths (update these for your system)
    vivado_path = "/home/ryuk/Xilinx2/Vivado/2020.2/bin/vivado"
    tcl_script_path = os.path.join(
        os.path.dirname(os.path.abspath(__file__)),
        "../fpga_programmer/program_fpga.tcl"
    )
    
    try:
        controller = ControllerServer(vivado_path, tcl_script_path)
        
        if not controller.start():
            logger.error("Failed to start controller")
            sys.exit(1)
        
        print("\n✅ Controller running")
        print(f"   Control port: {CONTROLLER_CONTROL_PORT}")
        print(f"   Data port: {CONTROLLER_DATA_PORT}")
        print("\nPress Ctrl+C to stop")
        
        # Run until interrupted
        while True:
            time.sleep(1)
            
    except KeyboardInterrupt:
        print("\n\n🛑 Shutting down...")
        controller.stop()
    except Exception as e:
        logger.error(f"Fatal error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == "__main__":
    main()