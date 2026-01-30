#!/usr/bin/env python3
"""
LDPC Testbed Protocol Definitions
Shared between Controller and Client
"""

import json
import struct
import time
from enum import Enum
from typing import List, Dict, Optional
from dataclasses import dataclass, asdict


class MessageType(Enum):
    """Control message types"""
    # Client -> Controller
    TASK_REQUEST = 0x01          # Request to program FPGA and decode
    STATUS_QUERY = 0x02          # Query controller status
    CANCEL_TASK = 0x03           # Cancel current task
    
    # Controller -> Client
    TASK_ACCEPTED = 0x10         # Task accepted, programming FPGA
    FPGA_READY = 0x11           # FPGA programmed, ready for data
    TASK_COMPLETE = 0x12        # Decoding complete
    TASK_FAILED = 0x13          # Task failed
    STATUS_RESPONSE = 0x14      # Status response
    ERROR = 0x15                # Error message


class FPGAStatus(Enum):
    """FPGA status states"""
    IDLE = "idle"
    PROGRAMMING = "programming"
    READY = "ready"
    DECODING = "decoding"
    ERROR = "error"


@dataclass
class TaskRequest:
    """Task request from client to controller"""
    task_id: str
    lifting_size: int          # Z value (48, 96, 192, etc.)
    num_llrs: int             # Must equal 50 * Z
    llrs: List[int]           # List of LLR values (4-bit signed: -8 to 7)
    bitfile_path: str         # Path to .bit file for this Z
    expected_output_bits: int # Expected number of decoded bits
    timeout_seconds: int = 30 # Timeout for the task
    
    def validate(self) -> tuple:
        """Validate task request"""
        # Check Z value
        valid_z_values = [48, 96, 192, 256, 384]
        if self.lifting_size not in valid_z_values:
            return False, f"Invalid Z={self.lifting_size}. Valid: {valid_z_values}"
        
        # Check LLR count
        expected_llrs = 50 * self.lifting_size
        if self.num_llrs != expected_llrs:
            return False, f"num_llrs={self.num_llrs} but expected {expected_llrs} for Z={self.lifting_size}"
        
        if len(self.llrs) != self.num_llrs:
            return False, f"LLR list has {len(self.llrs)} values but declared {self.num_llrs}"
        
        # Check LLR values are in valid range
        for i, llr in enumerate(self.llrs):
            if not isinstance(llr, int) or llr < -8 or llr > 7:
                return False, f"LLR[{i}]={llr} invalid. Must be integer in [-8, 7]"
        
        # Check bitfile path
        if not self.bitfile_path or not self.bitfile_path.endswith('.bit'):
            return False, f"Invalid bitfile path: {self.bitfile_path}"
        
        return True, "Valid"
    
    def to_dict(self) -> dict:
        return asdict(self)
    
    @classmethod
    def from_dict(cls, data: dict) -> 'TaskRequest':
        return cls(**data)


@dataclass
class ControlMessage:
    """Generic control message"""
    msg_type: MessageType
    task_id: str
    payload: Dict
    timestamp: float
    client_timestamp: Optional[float] = None  # For timing measurements
    
    def to_json(self) -> str:
        """Serialize to JSON"""
        data = {
            'msg_type': self.msg_type.value,
            'task_id': self.task_id,
            'payload': self.payload,
            'timestamp': self.timestamp,
            'client_timestamp': self.client_timestamp
        }
        return json.dumps(data)
    
    @classmethod
    def from_json(cls, json_str: str) -> 'ControlMessage':
        """Deserialize from JSON"""
        data = json.loads(json_str)
        return cls(
            msg_type=MessageType(data['msg_type']),
            task_id=data['task_id'],
            payload=data['payload'],
            timestamp=data['timestamp'],
            client_timestamp=data.get('client_timestamp')
        )
    
    def to_bytes(self) -> bytes:
        """Convert to bytes for network transmission"""
        json_data = self.to_json()
        json_bytes = json_data.encode('utf-8')
        
        # Header: 4 bytes length + JSON data
        header = struct.pack('!I', len(json_bytes))
        return header + json_bytes
    
    @classmethod
    def from_bytes(cls, data: bytes) -> 'ControlMessage':
        """Parse from bytes"""
        if len(data) < 4:
            raise ValueError("Data too short for control message")
        
        length = struct.unpack('!I', data[:4])[0]
        json_bytes = data[4:4+length]
        json_str = json_bytes.decode('utf-8')
        return cls.from_json(json_str)


@dataclass
class TimingInfo:
    """Complete timing information for a task"""
    task_id: str
    
    # Client side timestamps
    t1_client_send_request: Optional[float] = None
    t6_client_recv_ready: Optional[float] = None
    t7_client_send_data: Optional[float] = None
    t10_client_recv_result: Optional[float] = None
    
    # Controller side timestamps
    t2_controller_recv_request: Optional[float] = None
    t3_controller_start_program: Optional[float] = None
    t4_controller_finish_program: Optional[float] = None
    t5_controller_send_ready: Optional[float] = None
    
    def calculate_latencies(self) -> Dict[str, float]:
        """Calculate all latencies in milliseconds"""
        latencies = {}
        
        # Control message latency (Client → Controller)
        if self.t1_client_send_request and self.t2_controller_recv_request:
            latencies['control_msg_latency_ms'] = \
                (self.t2_controller_recv_request - self.t1_client_send_request) * 1000
        
        # FPGA programming time
        if self.t3_controller_start_program and self.t4_controller_finish_program:
            latencies['fpga_program_time_ms'] = \
                (self.t4_controller_finish_program - self.t3_controller_start_program) * 1000
        
        # Ready notification latency (Controller → Client)
        if self.t5_controller_send_ready and self.t6_client_recv_ready:
            latencies['ready_msg_latency_ms'] = \
                (self.t6_client_recv_ready - self.t5_controller_send_ready) * 1000
        
        # FPGA processing time (Data send → Result receive)
        if self.t7_client_send_data and self.t10_client_recv_result:
            latencies['fpga_processing_time_ms'] = \
                (self.t10_client_recv_result - self.t7_client_send_data) * 1000
        
        # Total end-to-end time
        if self.t1_client_send_request and self.t10_client_recv_result:
            latencies['total_end_to_end_ms'] = \
                (self.t10_client_recv_result - self.t1_client_send_request) * 1000
        
        # Controller processing overhead (non-programming)
        if self.t2_controller_recv_request and self.t3_controller_start_program:
            latencies['controller_overhead_before_ms'] = \
                (self.t3_controller_start_program - self.t2_controller_recv_request) * 1000
        
        if self.t4_controller_finish_program and self.t5_controller_send_ready:
            latencies['controller_overhead_after_ms'] = \
                (self.t5_controller_send_ready - self.t4_controller_finish_program) * 1000
        
        return latencies
    
    def print_timing_report(self):
        """Print a detailed timing report"""
        latencies = self.calculate_latencies()
        
        print("\n" + "="*70)
        print(f"⏱️  TIMING REPORT - Task {self.task_id}")
        print("="*70)
        
        print("\n📊 Latency Breakdown:")
        print("-" * 70)
        
        if 'control_msg_latency_ms' in latencies:
            print(f"  Client → Controller (TCP):        {latencies['control_msg_latency_ms']:8.2f} ms")
        
        if 'controller_overhead_before_ms' in latencies:
            print(f"  Controller Processing (pre):      {latencies['controller_overhead_before_ms']:8.2f} ms")
        
        if 'fpga_program_time_ms' in latencies:
            print(f"  FPGA Programming (JTAG):          {latencies['fpga_program_time_ms']:8.2f} ms")
        
        if 'controller_overhead_after_ms' in latencies:
            print(f"  Controller Processing (post):     {latencies['controller_overhead_after_ms']:8.2f} ms")
        
        if 'ready_msg_latency_ms' in latencies:
            print(f"  Controller → Client (TCP):        {latencies['ready_msg_latency_ms']:8.2f} ms")
        
        if 'fpga_processing_time_ms' in latencies:
            print(f"  FPGA Processing (incl. network):  {latencies['fpga_processing_time_ms']:8.2f} ms")
        
        print("-" * 70)
        
        if 'total_end_to_end_ms' in latencies:
            print(f"  ⏱️  TOTAL END-TO-END:               {latencies['total_end_to_end_ms']:8.2f} ms")
            print(f"                                    ({latencies['total_end_to_end_ms']/1000:.2f} seconds)")
        
        print("="*70 + "\n")
        
        return latencies
    
    def to_dict(self) -> dict:
        """Convert to dictionary"""
        return asdict(self)


def create_task_request_message(task_req: TaskRequest, timestamp: float) -> ControlMessage:
    """Create a TASK_REQUEST control message"""
    return ControlMessage(
        msg_type=MessageType.TASK_REQUEST,
        task_id=task_req.task_id,
        payload=task_req.to_dict(),
        timestamp=timestamp,
        client_timestamp=timestamp
    )


def create_status_response(task_id: str, status: FPGAStatus, 
                          message: str, timestamp: float) -> ControlMessage:
    """Create a STATUS_RESPONSE control message"""
    return ControlMessage(
        msg_type=MessageType.STATUS_RESPONSE,
        task_id=task_id,
        payload={
            'status': status.value,
            'message': message
        },
        timestamp=timestamp
    )


def create_fpga_ready_message(task_id: str, fpga_ip: str, 
                              fpga_port: int, timestamp: float) -> ControlMessage:
    """Create FPGA_READY message"""
    return ControlMessage(
        msg_type=MessageType.FPGA_READY,
        task_id=task_id,
        payload={
            'fpga_ip': fpga_ip,
            'fpga_port': fpga_port,
            'message': 'FPGA programmed and ready for data'
        },
        timestamp=timestamp
    )


def create_error_message(task_id: str, error_msg: str, timestamp: float) -> ControlMessage:
    """Create ERROR message"""
    return ControlMessage(
        msg_type=MessageType.ERROR,
        task_id=task_id,
        payload={'error': error_msg},
        timestamp=timestamp
    )


def pack_llrs_to_payload(llrs: List[int], payload_size: int) -> bytes:
    """
    Pack LLRs into hardware-compatible payload format
    16 LLRs per 64-bit word, 4 bits per LLR
    """
    words_count = (len(llrs) + 15) // 16
    payload_words = []
    
    for word_idx in range(words_count):
        word_val = 0
        llr_base = word_idx * 16
        
        # Pack 16 LLRs into one 64-bit word
        for chunk_idx in range(16):
            llr_idx = llr_base + chunk_idx
            
            if llr_idx < len(llrs):
                llr_val = llrs[llr_idx] & 0xF
            else:
                llr_val = 0
            
            word_val |= (llr_val << (chunk_idx * 4))
        
        word_bytes = word_val.to_bytes(8, byteorder='little')
        payload_words.append(word_bytes)
    
    payload = b''.join(payload_words)
    
    # Trim or pad to exact size
    if len(payload) > payload_size:
        payload = payload[:payload_size]
    elif len(payload) < payload_size:
        payload += b'\x00' * (payload_size - len(payload))
    
    return payload


def unpack_decoded_bits(data: bytes, expected_bits: int) -> List[int]:
    """
    Unpack decoded bits from FPGA response
    Returns list of bits (0 or 1)
    """
    bits = []
    for byte in data:
        for bit_pos in range(8):
            if len(bits) >= expected_bits:
                break
            bit = (byte >> bit_pos) & 1
            bits.append(bit)
        if len(bits) >= expected_bits:
            break
    return bits[:expected_bits]