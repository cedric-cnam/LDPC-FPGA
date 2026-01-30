#!/usr/bin/env python3
"""
Timing utilities for LDPC Testbed
Tracks latency at each communication step
"""

import time
from dataclasses import dataclass, asdict
from typing import Dict, Optional

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
        print(f"TIMING REPORT - Task {self.task_id}")
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