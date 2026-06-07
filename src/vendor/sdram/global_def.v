`ifndef SDRAM_GLOBAL_DEF_V
`define SDRAM_GLOBAL_DEF_V

`define   DATA_WIDTH                32
`define   ADDR_WIDTH                21
`define   DM_WIDTH                  4

`define   ROW_WIDTH                 11
`define   BA_WIDTH                  2

// 125MHz SDRAM clock => 8ns period.
// Original expression used 2**(`ROW_WIDTH), which some TD parse paths reject
// when this header is included by encrypted sources. Keep it as a constant.
`define   SDR_CLK_PERIOD            8
`define   SELF_REFRESH_INTERVAL     3906

`endif
