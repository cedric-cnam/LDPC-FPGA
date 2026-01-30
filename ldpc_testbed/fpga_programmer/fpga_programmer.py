#!/usr/bin/env python3
"""
FPGA Programmer - Vivado TCL Wrapper
Programs the FPGA using Vivado Hardware Manager
"""

import subprocess
import os
import time
from typing import Optional, Tuple
import logging

class FPGAProgrammer:
    """Manages FPGA programming via Vivado"""
    
    def __init__(self, vivado_path: str, tcl_script_path: str):
        self.vivado_path = vivado_path
        self.tcl_script_path = tcl_script_path
        self.logger = logging.getLogger(__name__)
        
        # Validate paths
        if not os.path.exists(vivado_path):
            raise FileNotFoundError(f"Vivado not found at: {vivado_path}")
        
        if not os.path.exists(tcl_script_path):
            raise FileNotFoundError(f"TCL script not found at: {tcl_script_path}")
        
        self.logger.info(f"FPGA Programmer initialized")
        self.logger.info(f"  Vivado: {vivado_path}")
        self.logger.info(f"  TCL Script: {tcl_script_path}")
    
    def program_fpga(self, bitfile_path: str, timeout: int = 60) -> Tuple[bool, str]:
        """
        Program FPGA with specified bitfile
        
        Args:
            bitfile_path: Path to .bit file
            timeout: Timeout in seconds
            
        Returns:
            (success, message) tuple
        """
        # Validate bitfile
        if not os.path.exists(bitfile_path):
            msg = f"Bitfile not found: {bitfile_path}"
            self.logger.error(msg)
            return False, msg
        
        if not bitfile_path.endswith('.bit'):
            msg = f"Invalid bitfile extension: {bitfile_path}"
            self.logger.error(msg)
            return False, msg
        
        self.logger.info(f"Programming FPGA with: {bitfile_path}")
        self.logger.info(f"Timeout: {timeout}s")
        
        # Build Vivado command
        cmd = [
            self.vivado_path,
            '-mode', 'batch',
            '-source', self.tcl_script_path,
            '-tclargs', bitfile_path
        ]
        
        try:
            start_time = time.time()
            
            # Run Vivado
            self.logger.debug(f"Executing: {' '.join(cmd)}")
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=timeout
            )
            
            elapsed = time.time() - start_time
            
            # Parse output
            stdout = result.stdout
            stderr = result.stderr
            returncode = result.returncode
            
            # Log output
            if stdout:
                self.logger.debug("Vivado stdout:")
                for line in stdout.split('\n'):
                    if line.strip():
                        self.logger.debug(f"  {line}")
            
            if stderr:
                self.logger.warning("Vivado stderr:")
                for line in stderr.split('\n'):
                    if line.strip():
                        self.logger.warning(f"  {line}")
            
            # Check result
            if returncode == 0:
                # Check for SUCCESS in output
                if "STATUS: SUCCESS" in stdout:
                    msg = f"FPGA programmed successfully in {elapsed:.1f}s"
                    self.logger.info(msg)
                    return True, msg
                else:
                    msg = f"Programming completed but success status unclear"
                    self.logger.warning(msg)
                    return False, msg
            else:
                msg = f"Programming failed with code {returncode}"
                self.logger.error(msg)
                return False, msg
                
        except subprocess.TimeoutExpired:
            msg = f"Programming timeout after {timeout}s"
            self.logger.error(msg)
            return False, msg
            
        except Exception as e:
            msg = f"Programming error: {e}"
            self.logger.error(msg)
            return False, msg
    
    def verify_hardware_server(self) -> Tuple[bool, str]:
        """
        Verify Vivado hardware server is running
        Returns: (is_running, message)
        """
        try:
            # Try to connect to hw_server
            result = subprocess.run(
                ['pgrep', '-f', 'hw_server'],
                capture_output=True,
                text=True,
                timeout=5
            )
            
            if result.returncode == 0:
                return True, "Hardware server is running"
            else:
                return False, "Hardware server not found. Start with: hw_server"
                
        except Exception as e:
            return False, f"Could not verify hardware server: {e}"

# Test function
if __name__ == "__main__":
    import sys
    
    logging.basicConfig(
        level=logging.DEBUG,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )
    
    if len(sys.argv) < 2:
        print("Usage: python3 fpga_programmer.py <bitfile_path>")
        sys.exit(1)
    
    bitfile = sys.argv[1]
    
    # Use default paths (update these for your system)
    vivado = "/home/ryuk/Xilinx2/Vivado/2020.2/bin/vivado"
    tcl = "program_fpga.tcl"
    
    programmer = FPGAProgrammer(vivado, tcl)
    
    # Check hardware server
    print("Checking hardware server...")
    running, msg = programmer.verify_hardware_server()
    print(f"  {msg}")
    
    if not running:
        print("\nPlease start hardware server first:")
        print("  hw_server")
        sys.exit(1)
    
    # Program FPGA
    print(f"\nProgramming FPGA with: {bitfile}")
    success, msg = programmer.program_fpga(bitfile)
    print(f"  Result: {msg}")
    
    sys.exit(0 if success else 1)
