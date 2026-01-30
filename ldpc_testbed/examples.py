#!/usr/bin/env python3
"""
Example Scripts for LDPC Testbed
Shows various usage patterns
"""

import sys
import os
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from client.client import LDPCClient, generate_test_llrs
import time

def example_basic_usage():
    """
    Example 1: Basic usage - decode with Z=96
    """
    print("\n" + "="*70)
    print("Example 1: Basic Usage")
    print("="*70)
    
    # Parameters
    Z = 96
    bitfile = "/home/fpga/bitfiles/ldpc_z96.bit"
    
    # Generate test LLRs
    llrs = generate_test_llrs(Z)
    
    # Create client and submit task
    client = LDPCClient()
    success, msg, decoded_bits = client.submit_task(Z, llrs, bitfile)
    client.cleanup()
    
    if success:
        print(f"\n✅ Success! Decoded {len(decoded_bits)} bits")
        print(f"First 20 bits: {decoded_bits[:20]}")
    else:
        print(f"\n❌ Failed: {msg}")

def example_custom_llrs():
    """
    Example 2: Using custom LLRs
    """
    print("\n" + "="*70)
    print("Example 2: Custom LLRs")
    print("="*70)
    
    Z = 48
    num_llrs = 50 * Z
    
    # Create custom LLRs (e.g., from your channel estimation)
    llrs = []
    for i in range(num_llrs):
        # Your custom LLR calculation
        if i % 10 < 5:
            llr = 5  # Strong positive
        else:
            llr = -5  # Strong negative
        
        # Clamp to valid range [-8, 7]
        llr = max(-8, min(7, llr))
        llrs.append(llr)
    
    print(f"Created {len(llrs)} custom LLRs")
    print(f"Range: [{min(llrs)}, {max(llrs)}]")
    
    # Submit task
    client = LDPCClient()
    success, msg, decoded_bits = client.submit_task(
        Z=Z,
        llrs=llrs,
        bitfile_path="/home/fpga/bitfiles/ldpc_z48.bit"
    )
    client.cleanup()
    
    if success:
        ones = sum(decoded_bits)
        zeros = len(decoded_bits) - ones
        print(f"\n✅ Decoded {len(decoded_bits)} bits")
        print(f"Statistics: {ones} ones ({ones/len(decoded_bits)*100:.1f}%), "
              f"{zeros} zeros ({zeros/len(decoded_bits)*100:.1f}%)")

def example_batch_decode():
    """
    Example 3: Batch decoding - multiple frames
    """
    print("\n" + "="*70)
    print("Example 3: Batch Decoding")
    print("="*70)
    
    Z = 96
    num_frames = 5
    
    print(f"Decoding {num_frames} frames with Z={Z}...")
    
    client = LDPCClient()
    results = []
    
    for frame_num in range(num_frames):
        print(f"\nFrame {frame_num + 1}/{num_frames}:")
        
        # Generate LLRs for this frame
        llrs = generate_test_llrs(Z)
        
        # Decode
        success, msg, decoded_bits = client.submit_task(
            Z=Z,
            llrs=llrs,
            bitfile_path="/home/fpga/bitfiles/ldpc_z96.bit"
        )
        
        results.append({
            'frame': frame_num + 1,
            'success': success,
            'bits': len(decoded_bits) if decoded_bits else 0
        })
        
        if success:
            print(f"  ✅ Decoded {len(decoded_bits)} bits")
        else:
            print(f"  ❌ Failed: {msg}")
        
        # Small delay between frames
        if frame_num < num_frames - 1:
            time.sleep(1)
    
    client.cleanup()
    
    # Summary
    print(f"\n{'='*70}")
    print("Batch Results:")
    successful = sum(1 for r in results if r['success'])
    print(f"  Successful: {successful}/{num_frames}")
    print(f"  Failed: {num_frames - successful}/{num_frames}")

def example_different_z_values():
    """
    Example 4: Testing different Z values
    """
    print("\n" + "="*70)
    print("Example 4: Different Z Values")
    print("="*70)
    
    z_configs = [
        {'Z': 48, 'bitfile': '/home/fpga/bitfiles/ldpc_z48.bit'},
        {'Z': 96, 'bitfile': '/home/fpga/bitfiles/ldpc_z96.bit'},
        {'Z': 192, 'bitfile': '/home/fpga/bitfiles/ldpc_z192.bit'},
    ]
    
    client = LDPCClient()
    
    for config in z_configs:
        Z = config['Z']
        bitfile = config['bitfile']
        
        print(f"\nTesting Z={Z}...")
        
        llrs = generate_test_llrs(Z)
        success, msg, decoded_bits = client.submit_task(Z, llrs, bitfile)
        
        if success:
            print(f"  ✅ Z={Z}: {len(decoded_bits)} bits decoded")
        else:
            print(f"  ❌ Z={Z}: {msg}")
        
        # Wait between different Z values (FPGA needs reprogramming)
        if config != z_configs[-1]:
            print("  Waiting for next Z value...")
            time.sleep(5)
    
    client.cleanup()

def example_error_handling():
    """
    Example 5: Error handling
    """
    print("\n" + "="*70)
    print("Example 5: Error Handling")
    print("="*70)
    
    client = LDPCClient()
    
    # Test 1: Invalid Z value
    print("\nTest 1: Invalid Z value (should fail)")
    llrs = [3] * 100
    success, msg, bits = client.submit_task(
        Z=999,  # Invalid Z
        llrs=llrs,
        bitfile_path="/invalid/path.bit"
    )
    print(f"  Result: {msg}")
    
    # Test 2: Wrong LLR count
    print("\nTest 2: Wrong LLR count (should fail)")
    llrs = [3] * 100  # Wrong count
    success, msg, bits = client.submit_task(
        Z=96,
        llrs=llrs,
        bitfile_path="/home/fpga/bitfiles/ldpc_z96.bit"
    )
    print(f"  Result: {msg}")
    
    # Test 3: Invalid LLR values
    print("\nTest 3: Invalid LLR values (should fail)")
    Z = 48
    llrs = [999] * (50 * Z)  # Out of range
    success, msg, bits = client.submit_task(
        Z=Z,
        llrs=llrs,
        bitfile_path="/home/fpga/bitfiles/ldpc_z48.bit"
    )
    print(f"  Result: {msg}")
    
    client.cleanup()

def example_save_results():
    """
    Example 6: Save results to file
    """
    print("\n" + "="*70)
    print("Example 6: Save Results")
    print("="*70)
    
    Z = 96
    llrs = generate_test_llrs(Z)
    
    client = LDPCClient()
    success, msg, decoded_bits = client.submit_task(
        Z=Z,
        llrs=llrs,
        bitfile_path="/home/fpga/bitfiles/ldpc_z96.bit"
    )
    client.cleanup()
    
    if success:
        # Save to file
        filename = f"decoded_bits_z{Z}_{int(time.time())}.txt"
        with open(filename, 'w') as f:
            f.write(f"Z={Z}\n")
            f.write(f"Total bits: {len(decoded_bits)}\n")
            f.write(f"Decoded bits: {decoded_bits}\n")
            f.write(f"Bit string: {''.join(map(str, decoded_bits))}\n")
        
        print(f"\n✅ Results saved to: {filename}")
        
        # Also save as binary
        bin_filename = f"decoded_bits_z{Z}_{int(time.time())}.bin"
        with open(bin_filename, 'wb') as f:
            # Pack bits into bytes
            byte_array = bytearray()
            for i in range(0, len(decoded_bits), 8):
                byte_val = 0
                for j in range(8):
                    if i + j < len(decoded_bits):
                        byte_val |= (decoded_bits[i + j] << j)
                byte_array.append(byte_val)
            f.write(bytes(byte_array))
        
        print(f"✅ Binary saved to: {bin_filename}")

def main():
    """Run all examples"""
    if os.geteuid() != 0:
        print("❌ Root privileges required")
        print("💡 Run with: sudo python3 examples.py [example_number]")
        sys.exit(1)
    
    examples = {
        '1': ('Basic Usage', example_basic_usage),
        '2': ('Custom LLRs', example_custom_llrs),
        '3': ('Batch Decoding', example_batch_decode),
        '4': ('Different Z Values', example_different_z_values),
        '5': ('Error Handling', example_error_handling),
        '6': ('Save Results', example_save_results),
    }
    
    print("="*70)
    print("LDPC Testbed Examples")
    print("="*70)
    print("\nAvailable examples:")
    for num, (name, _) in examples.items():
        print(f"  {num}. {name}")
    print("  0. Run all examples")
    
    if len(sys.argv) > 1:
        choice = sys.argv[1]
    else:
        choice = input("\nSelect example (0-6): ").strip()
    
    if choice == '0':
        print("\nRunning all examples...\n")
        for num, (name, func) in examples.items():
            try:
                func()
                time.sleep(2)
            except KeyboardInterrupt:
                print("\n\nInterrupted by user")
                break
            except Exception as e:
                print(f"\n❌ Example {num} failed: {e}")
                import traceback
                traceback.print_exc()
    elif choice in examples:
        name, func = examples[choice]
        print(f"\nRunning: {name}\n")
        try:
            func()
        except Exception as e:
            print(f"\n❌ Example failed: {e}")
            import traceback
            traceback.print_exc()
    else:
        print("Invalid choice")
        sys.exit(1)
    
    print("\n" + "="*70)
    print("Examples completed")
    print("="*70)

if __name__ == "__main__":
    main()
