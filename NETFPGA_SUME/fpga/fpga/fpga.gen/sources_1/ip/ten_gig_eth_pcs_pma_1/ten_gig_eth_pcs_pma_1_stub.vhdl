-- Copyright 1986-2018 Xilinx, Inc. All Rights Reserved.
-- --------------------------------------------------------------------------------
-- Tool Version: Vivado v.2018.2 (lin64) Build 2258646 Thu Jun 14 20:02:38 MDT 2018
-- Date        : Fri Jun 27 09:18:34 2025
-- Host        : fpga running 64-bit Ubuntu 24.04.2 LTS
-- Command     : write_vhdl -force -mode synth_stub
--               /home/hassan/Downloads/verilog-ethernet/example/NetFPGA_SUME/fpga/fpga/fpga.srcs/sources_1/ip/ten_gig_eth_pcs_pma_1/ten_gig_eth_pcs_pma_1_stub.vhdl
-- Design      : ten_gig_eth_pcs_pma_1
-- Purpose     : Stub declaration of top-level module interface
-- Device      : xc7vx690tffg1761-3
-- --------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity ten_gig_eth_pcs_pma_1 is
  Port ( 
    dclk : in STD_LOGIC;
    rxrecclk_out : out STD_LOGIC;
    coreclk : in STD_LOGIC;
    txusrclk : in STD_LOGIC;
    txusrclk2 : in STD_LOGIC;
    txoutclk : out STD_LOGIC;
    areset : in STD_LOGIC;
    areset_coreclk : in STD_LOGIC;
    gttxreset : in STD_LOGIC;
    gtrxreset : in STD_LOGIC;
    sim_speedup_control : in STD_LOGIC;
    txuserrdy : in STD_LOGIC;
    qplllock : in STD_LOGIC;
    qplloutclk : in STD_LOGIC;
    qplloutrefclk : in STD_LOGIC;
    reset_counter_done : in STD_LOGIC;
    xgmii_txd : in STD_LOGIC_VECTOR ( 63 downto 0 );
    xgmii_txc : in STD_LOGIC_VECTOR ( 7 downto 0 );
    xgmii_rxd : out STD_LOGIC_VECTOR ( 63 downto 0 );
    xgmii_rxc : out STD_LOGIC_VECTOR ( 7 downto 0 );
    txp : out STD_LOGIC;
    txn : out STD_LOGIC;
    rxp : in STD_LOGIC;
    rxn : in STD_LOGIC;
    configuration_vector : in STD_LOGIC_VECTOR ( 535 downto 0 );
    status_vector : out STD_LOGIC_VECTOR ( 447 downto 0 );
    core_status : out STD_LOGIC_VECTOR ( 7 downto 0 );
    tx_resetdone : out STD_LOGIC;
    rx_resetdone : out STD_LOGIC;
    signal_detect : in STD_LOGIC;
    tx_fault : in STD_LOGIC;
    drp_req : out STD_LOGIC;
    drp_gnt : in STD_LOGIC;
    drp_den_o : out STD_LOGIC;
    drp_dwe_o : out STD_LOGIC;
    drp_daddr_o : out STD_LOGIC_VECTOR ( 15 downto 0 );
    drp_di_o : out STD_LOGIC_VECTOR ( 15 downto 0 );
    drp_drdy_o : out STD_LOGIC;
    drp_drpdo_o : out STD_LOGIC_VECTOR ( 15 downto 0 );
    drp_den_i : in STD_LOGIC;
    drp_dwe_i : in STD_LOGIC;
    drp_daddr_i : in STD_LOGIC_VECTOR ( 15 downto 0 );
    drp_di_i : in STD_LOGIC_VECTOR ( 15 downto 0 );
    drp_drdy_i : in STD_LOGIC;
    drp_drpdo_i : in STD_LOGIC_VECTOR ( 15 downto 0 );
    pma_pmd_type : in STD_LOGIC_VECTOR ( 2 downto 0 );
    tx_disable : out STD_LOGIC
  );

end ten_gig_eth_pcs_pma_1;

architecture stub of ten_gig_eth_pcs_pma_1 is
attribute syn_black_box : boolean;
attribute black_box_pad_pin : string;
attribute syn_black_box of stub : architecture is true;
attribute black_box_pad_pin of stub : architecture is "dclk,rxrecclk_out,coreclk,txusrclk,txusrclk2,txoutclk,areset,areset_coreclk,gttxreset,gtrxreset,sim_speedup_control,txuserrdy,qplllock,qplloutclk,qplloutrefclk,reset_counter_done,xgmii_txd[63:0],xgmii_txc[7:0],xgmii_rxd[63:0],xgmii_rxc[7:0],txp,txn,rxp,rxn,configuration_vector[535:0],status_vector[447:0],core_status[7:0],tx_resetdone,rx_resetdone,signal_detect,tx_fault,drp_req,drp_gnt,drp_den_o,drp_dwe_o,drp_daddr_o[15:0],drp_di_o[15:0],drp_drdy_o,drp_drpdo_o[15:0],drp_den_i,drp_dwe_i,drp_daddr_i[15:0],drp_di_i[15:0],drp_drdy_i,drp_drpdo_i[15:0],pma_pmd_type[2:0],tx_disable";
attribute X_CORE_INFO : string;
attribute X_CORE_INFO of stub : architecture is "ten_gig_eth_pcs_pma_v6_0_13,Vivado 2018.2";
begin
end;
