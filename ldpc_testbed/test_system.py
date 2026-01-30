#!/usr/bin/env python3
"""
LDPC Testbed System Test
Tests the complete system with various scenarios
"""

import sys
import os
import time
import logging

# Add parent to path
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from client.client import LDPCClient, generate_test_llrs

def test_single_z(Z: int, bitfile: str) -> bool:
    """Test a single Z value"""
    print(f"\n{'='*70}")
    print(f"Testing Z={Z}")
    print(f"{'='*70}")
    
    try:
        # Generate LLRs
        print(f"Generating {50*Z} LLRs...")
        llrs = generate_test_llrs(Z)
        
        # Create client
        client = LDPCClient()
        
        # Submit task
        print(f"Submitting task...")
        success, msg, decoded_bits = client.submit_task(Z, llrs, bitfile)
        
        # Cleanup
        client.cleanup()
        
        if success:
            print(f"✅ SUCCESS: Received {len(decoded_bits)} bits")
            
            # Validate
            expected_bits = Z * 10
            if len(decoded_bits) == expected_bits:
                print(f"✅ Correct output size ({expected_bits} bits)")
                return True
            else:
                print(f"❌ Wrong output size: {len(decoded_bits)} (expected {expected_bits})")
                return False
        else:
            print(f"❌ FAILED: {msg}")
            return False
            
    except Exception as e:
        print(f"❌ ERROR: {e}")
        import traceback
        traceback.print_exc()
        return False

def test_invalid_llr_count():
    """Test with invalid LLR count"""
    print(f"\n{'='*70}")
    print(f"Testing Invalid LLR Count (should fail gracefully)")
    print(f"{'='*70}")
    
    try:
        Z = 96
        # Wrong number of LLRs
        llrs = [3] * 100  # Should be 4800
        
        client = LDPCClient()
        success, msg, decoded_bits = client.submit_task(
            Z, 
            llrs, 
            "/home/fpga/bitfiles/ldpc_z96.bit"
        )
        client.cleanup()
        
        if not success:
            print(f"✅ Correctly rejected invalid input: {msg}")
            return True
        else:
            print(f"❌ Should have rejected invalid input")
            return False
            
    except Exception as e:
        print(f"✅ Exception thrown as expected: {e}")
        return True

def test_multiple_z_values():
    """Test multiple Z values in sequence"""
    print(f"\n{'='*70}")
    print(f"Testing Multiple Z Values in Sequence")
    print(f"{'='*70}")
    
    z_values = [48, 96, 192]
    results = {}
    
    for Z in z_values:
        bitfile = f"/home/fpga/bitfiles/ldpc_z{Z}.bit"
        result = test_single_z(Z, bitfile)
        results[Z] = result
        
        # Wait between tests
        if Z != z_values[-1]:
            print("\nWaiting 5 seconds before next test...")
            time.sleep(5)
    
    # Summary
    print(f"\n{'='*70}")
    print(f"Multi-Z Test Summary")
    print(f"{'='*70}")
    
    passed = sum(1 for r in results.values() if r)
    total = len(results)
    
    for Z, result in results.items():
        status = "✅ PASS" if result else "❌ FAIL"
        print(f"  Z={Z:3d}: {status}")
    
    print(f"\nTotal: {passed}/{total} passed")
    
    return passed == total

def main():
    """Main test function"""
    # Setup logging
    logging.basicConfig(
        level=logging.WARNING,  # Reduce noise during tests
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )
    
    print("=" * 70)
    print("LDPC Testbed System Test")
    print("=" * 70)
    print("\nThis will test the complete system workflow:")
    print("1. Single Z value test")
    print("2. Invalid input handling")
    print("3. Multiple Z values in sequence")
    print("\nMake sure controller is running!")
    print("=" * 70)
    
    # Check root
    if os.geteuid() != 0:
        print("❌ Root privileges required")
        print("💡 Run with: sudo python3 test_system.py")
        sys.exit(1)
    
    input("\nPress Enter to start tests...")
    
    all_passed = True
    
    # Test 1: Single Z
    print("\n\n" + "=" * 70)
    print("TEST 1: Single Z Value")
    print("=" * 70)
    result = test_single_z(96, "/home/fpga/bitfiles/ldpc_z96.bit")
    all_passed = all_passed and result
    
    time.sleep(3)
    
    # Test 2: Invalid input
    print("\n\n" + "=" * 70)
    print("TEST 2: Invalid Input Handling")
    print("=" * 70)
    result = test_invalid_llr_count()
    all_passed = all_passed and result
    
    time.sleep(3)
    
    # Test 3: Multiple Z values
    print("\n\n" + "=" * 70)
    print("TEST 3: Multiple Z Values")
    print("=" * 70)
    result = test_multiple_z_values()
    all_passed = all_passed and result
    
    # Final summary
    print("\n\n" + "=" * 70)
    print("FINAL TEST SUMMARY")
    print("=" * 70)
    
    if all_passed:
        print("\n✅ ALL TESTS PASSED!")
        print("\nThe testbed is working correctly.")
        sys.exit(0)
    else:
        print("\n❌ SOME TESTS FAILED")
        print("\nPlease check:")
        print("- Controller is running")
        print("- hw_server is running")
        print("- FPGA is connected and powered")
        print("- Bitfiles are in correct location")
        print("- Network configuration is correct")
        sys.exit(1)

if __name__ == "__main__":
    main()
