# LDPC-FPGA

Implementation of **Low-Density Parity-Check (LDPC) codes** on FPGA hardware.  
This project provides synthesizable VHDL/Verilog designs for high-performance LDPC decoding on the **NetFPGA-SUME** platform.

---

## ✨ Features

- FPGA-ready LDPC decoder architecture  
- Designed for **NetFPGA-SUME** boards  
- Modular HDL source code for easy adaptation  
- Scripts for Vivado project creation and synthesis  
- Example bitstream (`.bit`) included for quick deployment  

---

## 📂 Repository Structure

```text
LDPC-FPGA/
└── NETFPGA_SUME/
    ├── fpga/                # FPGA design sources and project scripts
    │   ├── common/          # Common makefiles / build utilities
    │   ├── fpga/            # Top-level design, constraints, generated IP
    │   └── ...              # Build artifacts, reports, and cache
    └── ...                  # Board-specific support files
```

---

## ⚙️ Prerequisites

- **Xilinx Vivado** (tested with ≥ 2018.3)  
- **NetFPGA-SUME** development board  
- (Optional) **ModelSim / QuestaSim** for simulation  

---

## 🚀 Usage

1. **Clone the repository**  
   ```bash
   git clone https://github.com/cedric-cnam/LDPC-FPGA.git
   cd LDPC-FPGA/NETFPGA_SUME/fpga
   ```

2. **Generate the Vivado project**  
   ```bash
   vivado -mode batch -source create_project.tcl
   ```

3. **Synthesize and implement** the design  
   - Run synthesis/implementation in Vivado  
   - Generate the FPGA bitstream  

4. **Load the bitstream** onto the NetFPGA-SUME board  

---

## 📜 License

This project is licensed under the GNU GPL v3.  
See the [LICENSE](LICENSE) file for details.

---

## 🤝 Contributing

Contributions are welcome!  
If you’d like to report a bug, suggest an improvement, or add support for another FPGA platform:

1. Fork the repository  
2. Create a new branch
3. Commit your changes  
4. Open a Pull Request  

---

## 📧 Contact

For questions, please reach out to:  
hassan.chreif.auditeur@lecnam.net
