////////////////////////////////////////////////////////////////////////////////
// Red Pitaya TOP module. It connects external pins and PS part with
// other application modules.
// Authors: Matej Oblak, Iztok Jeras
// (c) Red Pitaya  http://www.redpitaya.com
////////////////////////////////////////////////////////////////////////////////

/**
 * GENERAL DESCRIPTION:
 *
 * Top module connects PS part with rest of Red Pitaya applications.  
 *
 *                   /-------\      
 *   PS DDR <------> |  PS   |      AXI <-> custom bus
 *   PS MIO <------> |   /   | <------------+
 *   PS CLK -------> |  ARM  |              |
 *                   \-------/              |
 *                                          |
 *                            /-------\     |
 *                         -> | SCOPE | <---+
 *                         |  \-------/     |
 *                         |                |
 *            /--------\   |   /-----\      |
 *   ADC ---> |        | --+-> |     |      |
 *            | ANALOG |       | PID | <----+
 *   DAC <--- |        | <---- |     |      |
 *            \--------/   ^   \-----/      |
 *                         |                |
 *                         |  /-------\     |
 *                         -- |  ASG  | <---+ 
 *                            \-------/     |
 *                                          |
 *             /--------\                   |
 *    RX ----> |        |                   |
 *   SATA      | DAISY  | <-----------------+
 *    TX <---- |        | 
 *             \--------/ 
 *               |    |
 *               |    |
 *               (FREE)
 *
 * Inside analog module, ADC data is translated from unsigned neg-slope into
 * two's complement. Similar is done on DAC data.
 *
 * Scope module stores data from ADC into RAM, arbitrary signal generator (ASG)
 * sends data from RAM to DAC. MIMO PID uses ADC ADC as input and DAC as its output.
 *
 * Daisy chain connects with other boards with fast serial link. Data which is
 * send and received is at the moment undefined. This is left for the user.
 */

module red_pitaya_top #(
  // identification
  bit [0:5*32-1] GITH = '0,
  // module numbers
  int unsigned MNA = 2,  // number of acquisition modules
  int unsigned MNG = 2   // number of generator   modules
)(
  // PS connections
  inout  logic [54-1:0] FIXED_IO_mio     ,
  inout  logic          FIXED_IO_ps_clk  ,
  inout  logic          FIXED_IO_ps_porb ,
  inout  logic          FIXED_IO_ps_srstb,
  inout  logic          FIXED_IO_ddr_vrn ,
  inout  logic          FIXED_IO_ddr_vrp ,
  // DDR
  inout  logic [15-1:0] DDR_addr   ,
  inout  logic [ 3-1:0] DDR_ba     ,
  inout  logic          DDR_cas_n  ,
  inout  logic          DDR_ck_n   ,
  inout  logic          DDR_ck_p   ,
  inout  logic          DDR_cke    ,
  inout  logic          DDR_cs_n   ,
  inout  logic [ 4-1:0] DDR_dm     ,
  inout  logic [32-1:0] DDR_dq     ,
  inout  logic [ 4-1:0] DDR_dqs_n  ,
  inout  logic [ 4-1:0] DDR_dqs_p  ,
  inout  logic          DDR_odt    ,
  inout  logic          DDR_ras_n  ,
  inout  logic          DDR_reset_n,
  inout  logic          DDR_we_n   ,

  // Red Pitaya periphery

  // ADC
  input  logic [MNA-1:0] [16-1:0] adc_dat_i,  // ADC data
  input  logic           [ 2-1:0] adc_clk_i,  // ADC clock {p,n}
  output logic           [ 2-1:0] adc_clk_o,  // optional ADC clock source (unused)
  output logic                    adc_cdcs_o, // ADC clock duty cycle stabilizer
  // DAC
  output logic [14-1:0] dac_dat_o  ,  // DAC combined data
  output logic          dac_wrt_o  ,  // DAC write
  output logic          dac_sel_o  ,  // DAC channel select
  output logic          dac_clk_o  ,  // DAC clock
  output logic          dac_rst_o  ,  // DAC reset
  // PWM DAC
  output logic [ 4-1:0] dac_pwm_o  ,  // 1-bit PWM DAC
  // XADC
  input  logic [ 5-1:0] vinp_i     ,  // voltages p
  input  logic [ 5-1:0] vinn_i     ,  // voltages n
  // Expansion connector
  inout  logic [ 8-1:0] exp_p_io   ,
  inout  logic [ 8-1:0] exp_n_io   ,
  // SATA connector
  output logic [ 2-1:0] daisy_p_o  ,  // line 1 is clock capable
  output logic [ 2-1:0] daisy_n_o  ,
  input  logic [ 2-1:0] daisy_p_i  ,  // line 1 is clock capable
  input  logic [ 2-1:0] daisy_n_i  ,
  // LED
  inout  logic [ 8-1:0] led_o
  //simulation
  // ,input clk
  // ,input [13:0] measure
  // ,input adc_rstn
  // ,input ladder_start_strobe
  // ,output [31:0] Q, Q2, Q3
  // ,output reg [14-1:0] x_apo_est, P_apo_est  
  
);
assign Q = K[47:16];
assign Q2 = out_divider_P_apo_est[63:32];
assign Q3 = out_divider_K_post_error[63:32];
////////////////////////////////////////////////////////////////////////////////
// local signals
//////////////////////////////////////////////////////////////////////////////// 
logic pio_tt = 0;
//logic [9:0] cnt_tt=0;
logic [12:0] cnt_A=13'd0, cnt_B=13'd0;

// GPIO parameter
localparam int unsigned GDW = 8+8;

logic [4-1:0] fclk ; //[0]-125MHz, [1]-250MHz, [2]-50MHz, [3]-200MHz
logic [4-1:0] frstn;

// PLL signals
logic                 adc_clk_in;
logic                 pll_adc_clk;
logic                 pll_dac_clk_1x;
logic                 pll_dac_clk_2x;
logic                 pll_dac_clk_2p;
logic                 pll_ser_clk;
logic                 pll_pwm_clk;
logic                 pll_locked;
// fast serial signals
logic                 ser_clk ;
// PWM clock and reset
logic                 pwm_clk ;
logic                 pwm_rstn;

// ADC clock/reset
logic                 adc_clk;
logic                 adc_rstn;

// stream bus type
localparam type SBA_T = logic signed [14-1:0];  // acquire
localparam type SBG_T = logic signed [14-1:0];  // generate

SBA_T [MNA-1:0]          adc_dat;

// DAC signals
logic                    dac_clk_1x;
logic                    dac_clk_2x;
logic                    dac_clk_2p;
logic                    dac_rst;

logic        [14-1:0] dac_dat_a, dac_dat_b;
logic        [14-1:0] dac_a    , dac_b    ;
logic signed [15-1:0] dac_a_sum, dac_b_sum;

// ASG
SBG_T [2-1:0]            asg_dat;

// PID
SBA_T [2-1:0]            pid_dat;

// configuration
logic                    digital_loop;

// system bus
sys_bus_if   ps_sys      (.clk (adc_clk), .rstn (adc_rstn));
sys_bus_if   sys [8-1:0] (.clk (adc_clk), .rstn (adc_rstn));

// GPIO interface
gpio_if #(.DW (24)) gpio ();

////////////////////////////////////////////////////////////////////////////////
// PLL (clock and reset)
////////////////////////////////////////////////////////////////////////////////

// diferential clock input
IBUFDS i_clk (.I (adc_clk_i[1]), .IB (adc_clk_i[0]), .O (adc_clk_in));  // differential clock input

red_pitaya_pll pll (
  // inputs
  .clk         (adc_clk_in),  // clock
  .rstn        (frstn[0]  ),  // reset - active low
  // output clocks
  .clk_adc     (pll_adc_clk   ),  // ADC clock
  .clk_dac_1x  (pll_dac_clk_1x),  // DAC clock 125MHz
  .clk_dac_2x  (pll_dac_clk_2x),  // DAC clock 250MHz
  .clk_dac_2p  (pll_dac_clk_2p),  // DAC clock 250MHz -45DGR
  .clk_ser     (pll_ser_clk   ),  // fast serial clock
  .clk_pdm     (pll_pwm_clk   ),  // PWM clock
  // status outputs
  .pll_locked  (pll_locked)
);

BUFG bufg_adc_clk    (.O (adc_clk   ), .I (pll_adc_clk   ));
BUFG bufg_dac_clk_1x (.O (dac_clk_1x), .I (pll_dac_clk_1x));
BUFG bufg_dac_clk_2x (.O (dac_clk_2x), .I (pll_dac_clk_2x));
BUFG bufg_dac_clk_2p (.O (dac_clk_2p), .I (pll_dac_clk_2p));
BUFG bufg_ser_clk    (.O (ser_clk   ), .I (pll_ser_clk   ));
BUFG bufg_pwm_clk    (.O (pwm_clk   ), .I (pll_pwm_clk   ));

// ADC reset (active low)
always @(posedge adc_clk)
adc_rstn <=  frstn[0] &  pll_locked;

// DAC reset (active high)
always @(posedge dac_clk_1x)
dac_rst  <= ~frstn[0] | ~pll_locked;

// PWM reset (active low)
always @(posedge pwm_clk)
pwm_rstn <=  frstn[0] &  pll_locked;

////////////////////////////////////////////////////////////////////////////////
//  Connections to PS
////////////////////////////////////////////////////////////////////////////////

red_pitaya_ps ps (
  .FIXED_IO_mio       (  FIXED_IO_mio                ),
  .FIXED_IO_ps_clk    (  FIXED_IO_ps_clk             ),
  .FIXED_IO_ps_porb   (  FIXED_IO_ps_porb            ),
  .FIXED_IO_ps_srstb  (  FIXED_IO_ps_srstb           ),
  .FIXED_IO_ddr_vrn   (  FIXED_IO_ddr_vrn            ),
  .FIXED_IO_ddr_vrp   (  FIXED_IO_ddr_vrp            ),
  // DDR
  .DDR_addr      (DDR_addr    ),
  .DDR_ba        (DDR_ba      ),
  .DDR_cas_n     (DDR_cas_n   ),
  .DDR_ck_n      (DDR_ck_n    ),
  .DDR_ck_p      (DDR_ck_p    ),
  .DDR_cke       (DDR_cke     ),
  .DDR_cs_n      (DDR_cs_n    ),
  .DDR_dm        (DDR_dm      ),
  .DDR_dq        (DDR_dq      ),
  .DDR_dqs_n     (DDR_dqs_n   ),
  .DDR_dqs_p     (DDR_dqs_p   ),
  .DDR_odt       (DDR_odt     ),
  .DDR_ras_n     (DDR_ras_n   ),
  .DDR_reset_n   (DDR_reset_n ),
  .DDR_we_n      (DDR_we_n    ),
  // system signals
  .fclk_clk_o    (fclk        ),
  .fclk_rstn_o   (frstn       ),
  // ADC analog inputs
  .vinp_i        (vinp_i      ),
  .vinn_i        (vinn_i      ),
  // GPIO
  .gpio          (gpio),
  // system read/write channel
  .bus           (ps_sys      )
);

////////////////////////////////////////////////////////////////////////////////
// system bus decoder & multiplexer (it breaks memory addresses into 8 regions)
////////////////////////////////////////////////////////////////////////////////

sys_bus_interconnect #(
  .SN (8),
  .SW (20)
) sys_bus_interconnect (
  .bus_m (ps_sys),
  .bus_s (sys)
);

// silence unused busses
generate
for (genvar i=5; i<8; i++) begin: for_sys
  sys_bus_stub sys_bus_stub_5_7 (sys[i]);
end: for_sys
endgenerate

////////////////////////////////////////////////////////////////////////////////
// Analog mixed signals (PDM analog outputs)
////////////////////////////////////////////////////////////////////////////////

logic [4-1:0] [24-1:0] pwm_cfg;

red_pitaya_ams i_ams (
  // power test
  .clk_i           (adc_clk ),  // clock
  .rstn_i          (adc_rstn),  // reset - active low
  // PWM configuration
  .dac_a_o         (pwm_cfg[0]),
  .dac_b_o         (pwm_cfg[1]),
  .dac_c_o         (pwm_cfg[2]),
  .dac_d_o         (pwm_cfg[3]),
  // System bus
  .sys_addr        (sys[4].addr ),
  .sys_wdata       (sys[4].wdata),
  .sys_wen         (sys[4].wen  ),
  .sys_ren         (sys[4].ren  ),
  .sys_rdata       (sys[4].rdata),
  .sys_err         (sys[4].err  ),
  .sys_ack         (sys[4].ack  )
);

red_pitaya_pwm pwm [4-1:0] (
  // system signals
  .clk   (pwm_clk ),
  .rstn  (pwm_rstn),
  // configuration
  .cfg   (pwm_cfg),
  // PWM outputs
  .pwm_o (dac_pwm_o),
  .pwm_s ()
);

////////////////////////////////////////////////////////////////////////////////
// Daisy dummy code
////////////////////////////////////////////////////////////////////////////////

assign daisy_p_o = 1'bz;
assign daisy_n_o = 1'bz;

////////////////////////////////////////////////////////////////////////////////
// ADC IO
////////////////////////////////////////////////////////////////////////////////

// generating ADC clock is disabled
assign adc_clk_o = 2'b10;
//ODDR i_adc_clk_p ( .Q(adc_clk_o[0]), .D1(1'b1), .D2(1'b0), .C(fclk[0]), .CE(1'b1), .R(1'b0), .S(1'b0));
//ODDR i_adc_clk_n ( .Q(adc_clk_o[1]), .D1(1'b0), .D2(1'b1), .C(fclk[0]), .CE(1'b1), .R(1'b0), .S(1'b0));

// ADC clock duty cycle stabilizer is enabled
assign adc_cdcs_o = 1'b1 ;

logic [2-1:0] [14-1:0] adc_dat_raw;

// IO block registers should be used here
// lowest 2 bits reserved for 16bit ADC
always @(posedge adc_clk)
begin
  adc_dat_raw[0] <= adc_dat_i[0][16-1:2];
  adc_dat_raw[1] <= adc_dat_i[1][16-1:2];
end
    
// transform into 2's complement (negative slope)
assign adc_dat[0] = digital_loop ? dac_a : {adc_dat_raw[0][14-1], ~adc_dat_raw[0][14-2:0]};
assign adc_dat[1] = digital_loop ? dac_b : {adc_dat_raw[1][14-1], ~adc_dat_raw[1][14-2:0]};

////////////////////////////////////////////////////////////////////////////////
// DAC IO
////////////////////////////////////////////////////////////////////////////////

// Sumation of ASG and PID signal perform saturation before sending to DAC 
//assign dac_a_sum = asg_dat[0] + pid_dat[0];
//assign dac_b_sum = asg_dat[1] + pid_dat[1];
logic signed [31:0] reg_mod_H, reg_mod_L;
logic [31:0] reg_mod_freq_cnt; 
logic [31:0] Init_stable_cnt;
logic [16:0] reg_err_gain;
logic [2:0] mv_shift = 3'd6, mv_mode;
logic [6:0] deMOD_mv_cnt = 7'd64;

//assign dac_a_sum = mod; //open loop, com1
//assign dac_b_sum = ADC_reg_Diff;  //fog_v1.bit
//assign dac_b_sum = ADC_reg_Diff_MV; //fog_v1_1.bit ~ fog_v1_10.bit

//assign dac_a_sum = dac_ladder_out_2[14:0]; //close loop, com2
//assign dac_b_sum = dac_ladder_pre[14:0];

//assign dac_a_sum = dac_ladder_out_2[14:0]; //com3
//assign dac_b_sum = ADC_reg_Diff;

//assign dac_a_sum = mod; //com4
//assign dac_b_sum = dac_ladder_2[14:0];

//assign dac_a_sum = dac_ladder[14:0]; //com5
//assign dac_b_sum = dac_ladder_2[14:0];

assign dac_a_sum = measure; 
assign dac_b_sum = out_divider_P_apo_est[45:32]; 
// assign dac_b_sum = x_apo_est;

// saturation
assign dac_a = (^dac_a_sum[15-1:15-2]) ? {dac_a_sum[15-1], {13{~dac_a_sum[15-1]}}} : dac_a_sum[14-1:0];
assign dac_b = (^dac_b_sum[15-1:15-2]) ? {dac_b_sum[15-1], {13{~dac_b_sum[15-1]}}} : dac_b_sum[14-1:0];

localparam mod_stat_H = 1'b1;
localparam mod_stat_L = 1'b0;

logic [31:0] mod_cnt = 32'd0, initial_cnt = Init_stable_cnt;
logic [6:0] mv_cnt = deMOD_mv_cnt;
logic signed [13:0] mod = reg_mod_H[13:0] ;
logic signed [13:0] ADC_reg_H, ADC_reg_L, measure;
logic signed [14:0] ADC_reg_Diff, ADC_reg_Diff_ex_vth, Diff_vth;
logic signed [31:0] ADC_reg_H_sum=32'd0, ADC_reg_L_sum=32'd0, step_MV_sum = 32'd0, ADC_reg_H_offset;
logic [9:0] step_MV_index = 10'd0;
logic mod_stat = mod_stat_H;
logic ladder_start_strobe = 1'b0;
logic err_polarity;
logic signed [31:0] test_sum = 32'd0, test_add = $signed(-32'd1000), test;

logic [2:0] SM_diff = 3'd0;

logic MV = 1'b0;
logic diff_MV_flag = 1'b0;

always @(posedge dac_clk_1x) //MV
begin
    if(mv_mode == 3'd1) begin //no MV
        deMOD_mv_cnt <= 7'd1;
        mv_shift <= 3'd0;
    end
    else if(mv_mode == 3'd2) begin//MV  2
        deMOD_mv_cnt <= 7'd2;
        mv_shift <= 3'd1;
    end    
    else if(mv_mode == 3'd3) begin// MV 4
        deMOD_mv_cnt <= 7'd4;
        mv_shift <= 3'd2;
    end
    else if(mv_mode == 3'd4) begin// MV 8
        deMOD_mv_cnt <= 7'd8;
        mv_shift <= 3'd3;
    end
    else if(mv_mode == 3'd5) begin// MV 16
        deMOD_mv_cnt <= 7'd16;
        mv_shift <= 3'd4;
    end
    else if(mv_mode == 3'd6) begin// MV 32
        deMOD_mv_cnt <= 7'd32;
        mv_shift <= 3'd5;
    end
    else if(mv_mode == 3'd7) begin// MV 64
        deMOD_mv_cnt <= 7'd64;
        mv_shift <= 3'd6;
    end
end

always @(posedge dac_clk_1x) //demodulation, MV
begin
    case (SM_diff)
        3'd0: begin
            if(mod_stat == mod_stat_H)
                SM_diff <= 3'd1;
            else 
                SM_diff <= 3'd0;
        end
        3'd1: begin
            if(initial_cnt != 32'd0) initial_cnt <= initial_cnt - 1'b1;
            else begin
                if(mv_cnt != 7'd0  && !MV) begin
                    mv_cnt <= mv_cnt - 1'b1;
                    ADC_reg_H_sum <= ADC_reg_H_sum + adc_dat[1];
                    test_sum <= test_sum + test_add;
                end
                else if(mv_cnt == 7'd0  && !MV) begin
                    ADC_reg_H <= (ADC_reg_H_sum >>> mv_shift) + ADC_reg_H_offset ;
                    test <= test_sum >> mv_shift;
                    MV = 1'b1;
                end
                else if(mod_stat == mod_stat_L) begin
                    SM_diff <= 3'd2;
                    initial_cnt <= Init_stable_cnt;
                    mv_cnt <= deMOD_mv_cnt;
                    test_sum <= 32'd0;
                    ADC_reg_H_sum <= 32'd0;
                    MV = 1'b0;
                end
                else 
                    SM_diff <= 3'd1;         
            end      
        end
        3'd2: begin
            if(initial_cnt != 32'd0) initial_cnt <= initial_cnt - 1'b1;
            else begin
                if(mv_cnt != 7'd0  && !MV) begin           
                    mv_cnt <= mv_cnt - 1'b1;
                    ADC_reg_L_sum <= ADC_reg_L_sum + adc_dat[1];
                end   
                else if(mv_cnt == 7'd0  && !MV) begin
                    ADC_reg_L <= ADC_reg_L_sum >>> mv_shift;
                    MV = 1'b1;
                end 
                else begin
                    SM_diff <= 3'd3;
                    initial_cnt <= Init_stable_cnt;
                    MV = 1'b0;
                    ADC_reg_L_sum <= 32'd0;
                    mv_cnt <= deMOD_mv_cnt;
                end
            end
        end
        3'd3: begin
            diff_MV_flag = 1'b1;
            if(!err_polarity)
                ADC_reg_Diff <= ADC_reg_H - ADC_reg_L;
            else 
                ADC_reg_Diff <= ADC_reg_L - ADC_reg_H;
            measure <= adc_dat[0];
            SM_diff <= 3'd4;
        end
        3'd4: begin
            if(ADC_reg_Diff>= $signed(Diff_vth) || ADC_reg_Diff<= $signed(-Diff_vth))
                ADC_reg_Diff_ex_vth <= ADC_reg_Diff;
            else
                ADC_reg_Diff_ex_vth <= 15'd0;
            diff_MV_flag = 1'b0;
            ladder_start_strobe <= 1'b1;
            SM_diff <= 3'd5;
        end
        3'd5: begin
            ladder_start_strobe <= 1'b0;
            SM_diff <= 3'd0;
        end
    endcase
end

// moving average for open loop
// var for step moving average
logic [2:0] step_MV_case_sel = 3'd0;
logic [10:0] step_array_idx = 11'd0;
logic signed [31:0] step_MV_sum = 32'd0, step_MV_sum_out = 32'd0;
logic signed [14:0] ADC_reg_Diff_MV;
//不同之bit檔需修改///////////////////////
localparam STEP_MV_TIMES = 512;
localparam STEP_MV_SHIFT = 9;
//////////////////////////////////////////////////////
logic signed [14:0] step_array [STEP_MV_TIMES-1:0] ;
integer i;
initial begin
    for(i=0; i<STEP_MV_TIMES; i=i+1) step_array[i] = 15'd0;
end
always@(posedge dac_clk_1x)
begin
    case(step_MV_case_sel)
        3'd0: begin
            if(diff_MV_flag) begin
                step_MV_sum <= step_MV_sum - step_array[step_array_idx] ; //substract old value first
                step_MV_case_sel <= 3'd1;
            end
        end
        3'd1: begin
            step_MV_sum <= step_MV_sum + ADC_reg_Diff; //add new value 
            step_array[step_array_idx] <= ADC_reg_Diff;
//            step_MV_sum <= step_MV_sum + $signed(-15'd1000);          
//            step_array[step_array_idx] <= $signed(-15'd1000);
            step_MV_case_sel <= 3'd2;
        end
        3'd2: begin
            if(step_array_idx < STEP_MV_TIMES-1) step_array_idx <= step_array_idx + 1'b1;
            else step_array_idx <= 11'd0;
            step_MV_sum_out <= step_MV_sum;
            ADC_reg_Diff_MV <= (step_MV_sum >>> STEP_MV_SHIFT);
            step_MV_case_sel <= 3'd0;        
        end
    endcase
end

logic [13:0] reg_vth, reg_vth_1st_int; //8191 = 1V
logic mod_off;
logic signed [31:0] dac_ladder = 32'd0, dac_ladder_pre_vth = 32'd0, dac_ladder_pre = 32'd0, dac_ladder_2 = 32'd0, dac_ladder_out = 32'd0, dac_ladder_out_2 = 32'd0, err_signal, err_signal_pre = 32'd0;
logic signed [13:0] rst_th_p = $signed(reg_vth), rst_th_n = $signed(-reg_vth);
logic signed [13:0] rst_th_p_1st_int = $signed(reg_vth_1st_int), rst_th_n_1st_int = $signed(-reg_vth_1st_int);
logic signed [19:0] err_signal_shift;
logic ladder_rst;
logic [4:0] err_shift_idx, err_shift_idx_pre;
logic [1:0] pre_ladder_index = 2'd0;

always@(posedge dac_clk_1x)
begin
    rst_th_p = $signed(reg_vth);
    rst_th_n = $signed(-reg_vth);
    rst_th_p_1st_int = $signed(reg_vth_1st_int);
    rst_th_n_1st_int = $signed(-reg_vth_1st_int);
end

logic [1:0] ladder_pre_case = 2'd0;

always@(posedge dac_clk_1x) //1st integrator
begin
    if(ladder_rst)
        dac_ladder_pre_vth <= 32'd0;
    else begin
        case(pre_ladder_index)
            2'd0: begin
                if(ladder_start_strobe == 1'b1) begin    
                        dac_ladder_pre_vth <= dac_ladder_pre_vth + err_signal;
                        pre_ladder_index = 2'd1;
                end
                else dac_ladder_pre_vth <= dac_ladder_pre_vth;
            end
            
            2'd1: begin
                case(err_shift_idx_pre)
                   5'd0: begin
                           if(dac_ladder_pre_vth >= rst_th_p_1st_int)
                               dac_ladder_pre_vth <= rst_th_p_1st_int;
                           else if(dac_ladder_pre_vth <= rst_th_n_1st_int)
                               dac_ladder_pre_vth <= rst_th_n_1st_int;                      
                         end 
                   5'd1: begin
                             if(dac_ladder_pre_vth >= (rst_th_p_1st_int<<<err_shift_idx_pre))
                                 dac_ladder_pre_vth <= (rst_th_p_1st_int<<<err_shift_idx_pre);
                             else if(dac_ladder_pre_vth <= (rst_th_n_1st_int<<<err_shift_idx_pre))
                                 dac_ladder_pre_vth <= (rst_th_n_1st_int<<<err_shift_idx_pre);   
                           end 
                   5'd2: begin
                             if(dac_ladder_pre_vth >= (rst_th_p_1st_int<<<err_shift_idx_pre))
                                 dac_ladder_pre_vth <= (rst_th_p_1st_int<<<err_shift_idx_pre);
                             else if(dac_ladder_pre_vth <= (rst_th_n_1st_int<<<err_shift_idx_pre))
                                 dac_ladder_pre_vth <= (rst_th_n_1st_int<<<err_shift_idx_pre);  
                           end                                      
                   5'd3: begin
                             if(dac_ladder_pre_vth >= (rst_th_p_1st_int<<<err_shift_idx_pre))
                                 dac_ladder_pre_vth <= (rst_th_p_1st_int<<<err_shift_idx_pre);
                             else if(dac_ladder_pre_vth <= (rst_th_n_1st_int<<<err_shift_idx_pre))
                                 dac_ladder_pre_vth <= (rst_th_n_1st_int<<<err_shift_idx_pre);  
                           end  
                   5'd4: begin
                             if(dac_ladder_pre_vth >= (rst_th_p_1st_int<<<err_shift_idx_pre))
                                 dac_ladder_pre_vth <= (rst_th_p_1st_int<<<err_shift_idx_pre);
                             else if(dac_ladder_pre_vth <= (rst_th_n_1st_int<<<err_shift_idx_pre))
                                 dac_ladder_pre_vth <= (rst_th_n_1st_int<<<err_shift_idx_pre);  
                           end  
                   5'd5: begin
                             if(dac_ladder_pre_vth >= (rst_th_p_1st_int<<<err_shift_idx_pre))
                                 dac_ladder_pre_vth <= (rst_th_p_1st_int<<<err_shift_idx_pre);
                             else if(dac_ladder_pre_vth <= (rst_th_n_1st_int<<<err_shift_idx_pre))
                                 dac_ladder_pre_vth <= (rst_th_n_1st_int<<<err_shift_idx_pre);  
                           end  
                   5'd6: begin
                             if(dac_ladder_pre_vth >= (rst_th_p_1st_int<<<err_shift_idx_pre))
                                 dac_ladder_pre_vth <= (rst_th_p_1st_int<<<err_shift_idx_pre);
                             else if(dac_ladder_pre_vth <= (rst_th_n_1st_int<<<err_shift_idx_pre))
                                 dac_ladder_pre_vth <= (rst_th_n_1st_int<<<err_shift_idx_pre);   
                           end 
                   5'd7: begin
                             if(dac_ladder_pre_vth >= (rst_th_p_1st_int<<<err_shift_idx_pre))
                                 dac_ladder_pre_vth <= (rst_th_p_1st_int<<<err_shift_idx_pre);
                             else if(dac_ladder_pre_vth <= (rst_th_n_1st_int<<<err_shift_idx_pre))
                                 dac_ladder_pre_vth <= (rst_th_n_1st_int<<<err_shift_idx_pre);  
                           end                                      
                   5'd8: begin
                             if(dac_ladder_pre_vth >= (rst_th_p_1st_int<<<err_shift_idx_pre))
                                 dac_ladder_pre_vth <= (rst_th_p_1st_int<<<err_shift_idx_pre);
                             else if(dac_ladder_pre_vth <= (rst_th_n_1st_int<<<err_shift_idx_pre))
                                 dac_ladder_pre_vth <= (rst_th_n_1st_int<<<err_shift_idx_pre);  
                           end  
                   5'd9: begin
                             if(dac_ladder_pre_vth >= (rst_th_p_1st_int<<<err_shift_idx_pre))
                                 dac_ladder_pre_vth <= (rst_th_p_1st_int<<<err_shift_idx_pre);
                             else if(dac_ladder_pre_vth <= (rst_th_n_1st_int<<<err_shift_idx_pre))
                                 dac_ladder_pre_vth <= (rst_th_n_1st_int<<<err_shift_idx_pre);  
                           end  
                   5'd10: begin
                             if(dac_ladder_pre_vth >= (rst_th_p_1st_int<<<err_shift_idx_pre))
                                 dac_ladder_pre_vth <= (rst_th_p_1st_int<<<err_shift_idx_pre);
                             else if(dac_ladder_pre_vth <= (rst_th_n_1st_int<<<err_shift_idx_pre))
                                 dac_ladder_pre_vth <= (rst_th_n_1st_int<<<err_shift_idx_pre);  
                           end
                   5'd11: begin
                             if(dac_ladder_pre_vth >= (rst_th_p_1st_int<<<err_shift_idx_pre))
                                 dac_ladder_pre_vth <= (rst_th_p_1st_int<<<err_shift_idx_pre);
                             else if(dac_ladder_pre_vth <= (rst_th_n_1st_int<<<err_shift_idx_pre))
                                 dac_ladder_pre_vth <= (rst_th_n_1st_int<<<err_shift_idx_pre);  
                           end
                   5'd12: begin
                                     if(dac_ladder_pre_vth >= (rst_th_p_1st_int<<<err_shift_idx_pre))
                                         dac_ladder_pre_vth <= (rst_th_p_1st_int<<<err_shift_idx_pre);
                                     else if(dac_ladder_pre_vth <= (rst_th_n_1st_int<<<err_shift_idx_pre))
                                         dac_ladder_pre_vth <= (rst_th_n_1st_int<<<err_shift_idx_pre);  
                                   end
                   5'd13: begin
                             if(dac_ladder_pre_vth >= (rst_th_p_1st_int<<<err_shift_idx_pre))
                                 dac_ladder_pre_vth <= (rst_th_p_1st_int<<<err_shift_idx_pre);
                             else if(dac_ladder_pre_vth <= (rst_th_n_1st_int<<<err_shift_idx_pre))
                                 dac_ladder_pre_vth <= (rst_th_n_1st_int<<<err_shift_idx_pre);  
                           end
                   5'd14: begin
                             if(dac_ladder_pre_vth >= (rst_th_p_1st_int<<<err_shift_idx_pre))
                                 dac_ladder_pre_vth <= (rst_th_p_1st_int<<<err_shift_idx_pre);
                             else if(dac_ladder_pre_vth <= (rst_th_n_1st_int<<<err_shift_idx_pre))
                                 dac_ladder_pre_vth <= (rst_th_n_1st_int<<<err_shift_idx_pre);  
                           end
                   5'd15: begin
                             if(dac_ladder_pre_vth >= (rst_th_p_1st_int<<<err_shift_idx_pre))
                                 dac_ladder_pre_vth <= (rst_th_p_1st_int<<<err_shift_idx_pre);
                             else if(dac_ladder_pre_vth <= (rst_th_n_1st_int<<<err_shift_idx_pre))
                                 dac_ladder_pre_vth <= (rst_th_n_1st_int<<<err_shift_idx_pre);  
                           end
                   5'd16: begin
                                     if(dac_ladder_pre_vth >= (rst_th_p_1st_int<<<err_shift_idx_pre))
                                         dac_ladder_pre_vth <= (rst_th_p_1st_int<<<err_shift_idx_pre);
                                     else if(dac_ladder_pre_vth <= (rst_th_n_1st_int<<<err_shift_idx_pre))
                                         dac_ladder_pre_vth <= (rst_th_n_1st_int<<<err_shift_idx_pre);  
                                   end
                   5'd17: begin
                             if(dac_ladder_pre_vth >= (rst_th_p_1st_int<<<err_shift_idx_pre))
                                 dac_ladder_pre_vth <= (rst_th_p_1st_int<<<err_shift_idx_pre);
                             else if(dac_ladder_pre_vth <= (rst_th_n_1st_int<<<err_shift_idx_pre))
                                 dac_ladder_pre_vth <= (rst_th_n_1st_int<<<err_shift_idx_pre);  
                           end
                   5'd18: begin
                             if(dac_ladder_pre_vth >= (rst_th_p_1st_int<<<err_shift_idx_pre))
                                 dac_ladder_pre_vth <= (rst_th_p_1st_int<<<err_shift_idx_pre);
                             else if(dac_ladder_pre_vth <= (rst_th_n_1st_int<<<err_shift_idx_pre))
                                 dac_ladder_pre_vth <= (rst_th_n_1st_int<<<err_shift_idx_pre);  
                           end
               endcase 
               pre_ladder_index = 2'd0;
            end
        endcase
    end
end

always@(posedge dac_clk_1x) 
begin 
    case(err_shift_idx_pre)
        5'd0: dac_ladder_pre <= dac_ladder_pre_vth;
        5'd1: dac_ladder_pre <= (dac_ladder_pre_vth >>> err_shift_idx_pre);   
        5'd2: dac_ladder_pre <= (dac_ladder_pre_vth >>> err_shift_idx_pre);
        5'd3: dac_ladder_pre <= (dac_ladder_pre_vth >>> err_shift_idx_pre); 
        5'd4: dac_ladder_pre <= (dac_ladder_pre_vth >>> err_shift_idx_pre);
        5'd5: dac_ladder_pre <= (dac_ladder_pre_vth >>> err_shift_idx_pre); 
        5'd6: dac_ladder_pre <= (dac_ladder_pre_vth >>> err_shift_idx_pre); 
        5'd7: dac_ladder_pre <= (dac_ladder_pre_vth >>> err_shift_idx_pre);   
        5'd8: dac_ladder_pre <= (dac_ladder_pre_vth >>> err_shift_idx_pre);
        5'd9: dac_ladder_pre <= (dac_ladder_pre_vth >>> err_shift_idx_pre); 
        5'd10: dac_ladder_pre <= (dac_ladder_pre_vth >>> err_shift_idx_pre);
        5'd11: dac_ladder_pre <= (dac_ladder_pre_vth >>> err_shift_idx_pre); 
        5'd12: dac_ladder_pre <= (dac_ladder_pre_vth >>> err_shift_idx_pre); 
        5'd13: dac_ladder_pre <= (dac_ladder_pre_vth >>> err_shift_idx_pre);
        5'd14: dac_ladder_pre <= (dac_ladder_pre_vth >>> err_shift_idx_pre); 
        5'd15: dac_ladder_pre <= (dac_ladder_pre_vth >>> err_shift_idx_pre); 
        5'd16: dac_ladder_pre <= (dac_ladder_pre_vth >>> err_shift_idx_pre);
        5'd17: dac_ladder_pre <= (dac_ladder_pre_vth >>> err_shift_idx_pre); 
        5'd18: dac_ladder_pre <= (dac_ladder_pre_vth >>> err_shift_idx_pre); 
     endcase
end

always@(posedge dac_clk_1x) //ladder wave mid
begin
    if(ladder_rst)
        dac_ladder <= 32'd0;
    else begin
        if(ladder_start_strobe == 1'b1) begin    
            dac_ladder <= dac_ladder + dac_ladder_pre;
        end
        else 
            dac_ladder <= dac_ladder;
                           
        case(err_shift_idx)
            5'd0: begin
                    if(dac_ladder >= rst_th_p)
                        dac_ladder <= dac_ladder - reg_vth;
                    else if(dac_ladder <= rst_th_n)
                        dac_ladder <= dac_ladder + reg_vth;   
                  end
            5'd1: begin
                    if(dac_ladder >= (rst_th_p<<<1))
                        dac_ladder <= dac_ladder - (reg_vth<<<1);
                    else if(dac_ladder <= (rst_th_n<<<1))
                        dac_ladder <= dac_ladder + (reg_vth<<<1);     
                  end
            5'd2: begin
                      if(dac_ladder >= (rst_th_p<<<2))
                          dac_ladder <= dac_ladder - (reg_vth<<<2);
                      else if(dac_ladder <= (rst_th_n<<<2))
                          dac_ladder <= dac_ladder + (reg_vth<<<2);      
                    end        
            5'd3: begin
                      if(dac_ladder >= (rst_th_p<<<3))
                          dac_ladder <= dac_ladder - (reg_vth<<<3);
                      else if(dac_ladder <= (rst_th_n<<<3))
                          dac_ladder <= dac_ladder + (reg_vth<<<3);             
                    end
            5'd4: begin
                      if(dac_ladder >= (rst_th_p<<<4))
                           dac_ladder <= dac_ladder - (reg_vth<<<4);
                      else if(dac_ladder <= (rst_th_n<<<4))
                          dac_ladder <= dac_ladder + (reg_vth<<<4);       
                    end
            5'd5: begin
                      if(dac_ladder >= (rst_th_p<<<5))
                          dac_ladder <= dac_ladder - (reg_vth<<<5);
                      else if(dac_ladder <= (rst_th_n<<<5))
                          dac_ladder <= dac_ladder + (reg_vth<<<5);            
                    end
            5'd6: begin
                      if(dac_ladder >= (rst_th_p<<<6))
                           dac_ladder <= dac_ladder - (reg_vth<<<6);
                      else if(dac_ladder <= (rst_th_n<<<6))
                           dac_ladder <= dac_ladder + (reg_vth<<<6);      
                    end
            5'd7: begin
                      if(dac_ladder >= (rst_th_p<<<7))
                          dac_ladder <= dac_ladder - (reg_vth<<<7);
                      else if(dac_ladder <= (rst_th_n<<<7))
                          dac_ladder <= dac_ladder + (reg_vth<<<7);                 
                    end
            5'd8: begin
                      if(dac_ladder >= (rst_th_p<<<8))
                          dac_ladder <= dac_ladder - (reg_vth<<<8);
                      else if(dac_ladder <= (rst_th_n<<<8))
                          dac_ladder <= dac_ladder + (reg_vth<<<8);          
                    end
            5'd9: begin
                      if(dac_ladder >= (rst_th_p<<<9))
                          dac_ladder <= dac_ladder - (reg_vth<<<9);
                      else if(dac_ladder <= (rst_th_n<<<9))
                          dac_ladder <= dac_ladder + (reg_vth<<<9);            
                    end
            5'd10: begin
                      if(dac_ladder >= (rst_th_p<<<10))
                          dac_ladder <= dac_ladder - (reg_vth<<<10);
                      else if(dac_ladder <= (rst_th_n<<<10))
                           dac_ladder <= dac_ladder + (reg_vth<<<10);        
                    end
            5'd11: begin
                      if(dac_ladder >= (rst_th_p<<<11))
                          dac_ladder <= dac_ladder - (reg_vth<<<11);
                      else if(dac_ladder <= (rst_th_n<<<11))
                           dac_ladder <= dac_ladder + (reg_vth<<<11);        
                    end
            5'd12: begin
                      if(dac_ladder >= (rst_th_p<<<12))
                          dac_ladder <= dac_ladder - (reg_vth<<<12);
                      else if(dac_ladder <= (rst_th_n<<<12))
                           dac_ladder <= dac_ladder + (reg_vth<<<12);        
                    end
            5'd13: begin
                      if(dac_ladder >= (rst_th_p<<<13))
                          dac_ladder <= dac_ladder - (reg_vth<<<13);
                      else if(dac_ladder <= (rst_th_n<<<13))
                           dac_ladder <= dac_ladder + (reg_vth<<<13);        
                    end                            
            5'd14: begin
                      if(dac_ladder >= (rst_th_p<<<14))
                          dac_ladder <= dac_ladder - (reg_vth<<<14);
                      else if(dac_ladder <= (rst_th_n<<<14))
                           dac_ladder <= dac_ladder + (reg_vth<<<14);        
                    end                           
            5'd15: begin
                      if(dac_ladder >= (rst_th_p<<<15))
                          dac_ladder <= dac_ladder - (reg_vth<<<15);
                      else if(dac_ladder <= (rst_th_n<<<15))
                           dac_ladder <= dac_ladder + (reg_vth<<<15);        
                    end                           
            5'd16: begin
                      if(dac_ladder >= (rst_th_p<<<16))
                          dac_ladder <= dac_ladder - (reg_vth<<<16);
                      else if(dac_ladder <= (rst_th_n<<<16))
                           dac_ladder <= dac_ladder + (reg_vth<<<16);        
                    end                           
            5'd17: begin
                      if(dac_ladder >= (rst_th_p<<<17))
                          dac_ladder <= dac_ladder - (reg_vth<<<17);
                      else if(dac_ladder <= (rst_th_n<<<17))
                           dac_ladder <= dac_ladder + (reg_vth<<<17);        
                    end                           
            5'd18: begin
                      if(dac_ladder >= (rst_th_p<<<18))
                          dac_ladder <= dac_ladder - (reg_vth<<<18);
                      else if(dac_ladder <= (rst_th_n<<<18))
                           dac_ladder <= dac_ladder + (reg_vth<<<18);        
                    end                           
                                                
        endcase
    end
     
end

always@(posedge dac_clk_1x) 
begin 
    case(err_shift_idx)
        5'd0: dac_ladder_2 <= dac_ladder;
        5'd1: dac_ladder_2 <= (dac_ladder >>> 1);   
        5'd2: dac_ladder_2 <= (dac_ladder >>> 2);
        5'd3: dac_ladder_2 <= (dac_ladder >>> 3); 
        5'd4: dac_ladder_2 <= (dac_ladder >>> 4);
        5'd5: dac_ladder_2 <= (dac_ladder >>> 5); 
        5'd6: dac_ladder_2 <= (dac_ladder >>> 6);    
        5'd7: dac_ladder_2 <= (dac_ladder >>> 7);  
        5'd8: dac_ladder_2 <= (dac_ladder >>> 8);   
        5'd9: dac_ladder_2 <= (dac_ladder >>> 9);   
        5'd10: dac_ladder_2 <= (dac_ladder >>> 10);
        5'd11: dac_ladder_2 <= (dac_ladder >>> 11);
        5'd12: dac_ladder_2 <= (dac_ladder >>> 12);
        5'd13: dac_ladder_2 <= (dac_ladder >>> 13);
        5'd14: dac_ladder_2 <= (dac_ladder >>> 14);
        5'd15: dac_ladder_2 <= (dac_ladder >>> 15);
        5'd16: dac_ladder_2 <= (dac_ladder >>> 16);
        5'd17: dac_ladder_2 <= (dac_ladder >>> 17);
        5'd18: dac_ladder_2 <= (dac_ladder >>> 18);
     endcase
end

always@(posedge dac_clk_1x) //ladder wave
begin 
    if(mod_off)
        dac_ladder_out <= dac_ladder_2;
    else
        dac_ladder_out <= dac_ladder_2 + mod; 
end

always@(posedge dac_clk_1x) //ladder wave
begin 
    if(dac_ladder_2 >= 0) begin
        if(dac_ladder_out > rst_th_p)
            dac_ladder_out_2 <= dac_ladder_out - reg_vth;
        else if(dac_ladder_out < 0)
            dac_ladder_out_2 <= dac_ladder_out + reg_vth;
        else dac_ladder_out_2 <= dac_ladder_out;
    end
    else begin
        if(dac_ladder_out <= rst_th_n)
            dac_ladder_out_2 <= dac_ladder_out + reg_vth;
        else if(dac_ladder_out > 0)
            dac_ladder_out_2 <= dac_ladder_out - reg_vth;
        else dac_ladder_out_2 <= dac_ladder_out;
    end
//    else if(dac_ladder_out <= rst_th_n)
//        dac_ladder_out_2 <= dac_ladder_out + reg_vth;
//    else 
//        dac_ladder_out_2 <= dac_ladder_out;
end

mult_gen_1 m2 (
  .CLK(dac_clk_1x),  // input wire CLK
  .A(ADC_reg_Diff_ex_vth),      // input wire [14 : 0] A
  .B(reg_err_gain),      // input wire [16 : 0] B
  .P(err_signal)      // output wire [31: 0] P
);

always @(posedge dac_clk_1x) //MOD
begin
    if(mod_cnt == 0)
    begin
        mod_cnt <= reg_mod_freq_cnt;
        if(mod_stat == mod_stat_L)
        begin
            mod <= reg_mod_H[13:0];
            mod_stat <= mod_stat_H;
        end
        else if(mod_stat == mod_stat_H)
        begin
            mod <= reg_mod_L[13:0];
            mod_stat <= mod_stat_L;
        end      
    end
    else
        mod_cnt <= mod_cnt - 1'b1;
end

//Kalman filter
logic signed [14-1:0] x_apo_est, P_apo_est;
logic signed [15-1:0] P_apri_est;
logic signed [16-1:0] out_adder_P_apri_est_R;
logic signed [48-1:0] K;
logic signed [32-1:0] out_subtractor_1_K;
logic signed [47-1:0] out_multiplier_P_apo_est;

logic signed [15-1:0] post_error;
logic signed [47-1:0] out_multiplier_K_post_error;
logic signed [64-1:0] out_divider_K_post_error;
logic signed [31:0] out_adder_x_apri_est_divided_K_post_error;

logic signed [16-1:0] out_adder_P_apri_est_R;



logic signed [64-1:0] out_divider_P_apo_est;

//  p
adder P_apo_est_shifted_Q //P_apo_est + Q
(
  .A(P_apo_est),      
  .B(14'd819),      //Q value set at 0.1 in decimal
  .CLK(dac_clk_1x),  // input wire CLK
  .CE(1'b1),    // input wire CE
  .S(P_apri_est)      // output wire [14 : 0] S
);
adder2 P_apri_est_R //R + P_apri_est
(
  .A(P_apri_est),      // input wire [14 : 0] A
  .B(14'd8191),      // input wire [13 : 0] B, R value set at 1 in decimal
  .CLK(dac_clk_1x),  // input wire CLK
  .CE(1'b1),    // input wire CE
  .S(out_adder_P_apri_est_R)      // output wire [15 : 0] S
);
divider P_apri_est_R_P_apri_est //P_apri_est/(R+P_apri_est)
(
  .aclk(dac_clk_1x),                                      // input wire aclk
  .s_axis_divisor_tvalid(1'b1),    // input wire s_axis_divisor_tvalid
 .s_axis_divisor_tdata(out_adder_P_apri_est_R),      // input wire [15 : 0] s_axis_divisor_tdata
  // .s_axis_divisor_tdata(1),      // input wire [15 : 0] s_axis_divisor_tdata
  .s_axis_dividend_tvalid(1'b1),  // input wire s_axis_dividend_tvalid
 .s_axis_dividend_tdata(P_apri_est <<< 13),    // input wire [31 : 0] s_axis_dividend_tdata
  // .s_axis_dividend_tdata(1 <<< 15),    // input wire [31 : 0] s_axis_dividend_tdata
  .m_axis_dout_tvalid(),          // output wire m_axis_dout_tvalid
  .m_axis_dout_tdata(K)            // output wire [47 : 0] m_axis_dout_tdata
);
subtractor _1_K  //1-K
(
  .A(32'd8191),      // input wire [31 : 0] A
  .B(K[47:16]),      // input wire [31 : 0] B
  .CLK(dac_clk_1x),  // input wire CLK
  .CE(1'b1),    // input wire CE
  .S(out_subtractor_1_K)      // output wire [31 : 0] S
);
multiplier P_apri_est_1_K					//P_apri_est * (1-K) 
(
  .CLK(dac_clk_1x),  // input wire CLK
  .A(P_apri_est),      // input wire [14 : 0] A
  .B(out_subtractor_1_K),      // input wire [31 : 0] B
  .P(out_multiplier_P_apo_est)      // output wire [46 : 0] P
);
divider2 shifted_P_apo_est			//Divide by 2^14
(
  .aclk(dac_clk_1x),                                      // input wire aclk
  .s_axis_divisor_tvalid(1'b1),    // input wire s_axis_divisor_tvalid
  .s_axis_divisor_tdata(32'd8192),      // input wire [31 : 0] s_axis_divisor_tdata
  .s_axis_dividend_tvalid(1'b1),  // input wire s_axis_dividend_tvalid
  .s_axis_dividend_tdata(out_multiplier_P_apo_est[31:0]),    // input wire [31 : 0] s_axis_dividend_tdata
  .m_axis_dout_tvalid(),          // output wire m_axis_dout_tvalid
  .m_axis_dout_tdata(out_divider_P_apo_est)            // output wire [63 : 0] m_axis_dout_tdata
);

// x
subtractor2 z_measured_x_apri_est //z_measure - x_apri_est
(
  .A(measure),      // input wire [13 : 0] A
  .B(x_apo_est),      // input wire [13 : 0] B
  .CLK(dac_clk_1x),  // input wire CLK
  .CE(1'b1),    // input wire CE
  .S(post_error)      // output wire [14 : 0] S
);
multiplier2 K_post_error		//K * (z_measure-x_apri_est)
(
  .CLK(dac_clk_1x),  // input wire CLK
  .A(K[47:16]),      // input wire [31 : 0] A
  // .A(32'd32768),      
  .B(post_error),      // input wire [14 : 0] B
  .P(out_multiplier_K_post_error)      // output wire [46 : 0] P
);
divider3 shifted_K_post_error  //K*(z_measure-x_apri_est) / 2^15
(
  .aclk(dac_clk_1x),                                      // input wire aclk
  .s_axis_divisor_tvalid(1'b1),    // input wire s_axis_divisor_tvalid
  .s_axis_divisor_tdata(32'd8192), // input wire [31 : 0] s_axis_divisor_tdata
  .s_axis_dividend_tvalid(1'b1),  // input wire s_axis_dividend_tvalid
  .s_axis_dividend_tdata(out_multiplier_K_post_error[31:0]),    // input wire [31 : 0] s_axis_dividend_tdata
  .m_axis_dout_tvalid(),          // output wire m_axis_dout_tvalid
  .m_axis_dout_tdata(out_divider_K_post_error)            // output wire [63 : 0] m_axis_dout_tdata
);
adder3 x_apri_est_shifted_K_post_error	//x_apri_est + K*(z_measure-x_apri_est)/2^15 
(
  .A(x_apo_est),      // input wire [13 : 0] A
  .B(out_divider_K_post_error[63:32]),      // input wire [31 : 0] B
  .CLK(dac_clk_1x),  // input wire CLK
  .CE(1'b1),    // input wire CE
  .S(out_adder_x_apri_est_divided_K_post_error)      // output wire [31 : 0] S
);

always @ (negedge adc_rstn or posedge ladder_start_strobe)
begin
	// Reset whenever the reset signal goes low, regardless of the busy
	if (!adc_rstn)
	begin
		P_apo_est <= 14'd8191;		//covariance starting value set at 1
		x_apo_est <= 14'd0;			//estimate starting value set at 0
	end
	// If not resetting, update the register output on the busy's falling edge
	else
	begin
		P_apo_est <= out_divider_P_apo_est[45:32];
		x_apo_est <= out_adder_x_apri_est_divided_K_post_error[13:0];
	end
end

reg [13:0] x_apo_est_r;
reg [9:0] x_apo_cnt = 10'd0;
localparam delay_cnt = 10'd125;

always @(posedge dac_clk_1x) // dac_clk_1x
begin
    // if(ladder_start_strobe) x_apo_cnt <= 10'd0;
    // if(x_apo_cnt != 10'd10) x_apo_cnt <= x_apo_cnt + 1'b1;
    // else begin
        // x_apo_cnt <= x_apo_cnt;
        // x_apo_est_r <= x_apo_est;
    // end
	if(x_apo_cnt != delay_cnt) x_apo_cnt <= x_apo_cnt + 1'b1;
	else if(x_apo_cnt == delay_cnt && ladder_start_strobe) begin
		x_apo_cnt <= 10'd0;
	end
    else begin
        x_apo_cnt <= x_apo_cnt;
        x_apo_est_r <= x_apo_est;
    end
end
// output registers + signed to unsigned (also to negative slope)
always @(posedge dac_clk_1x)
begin
  	dac_dat_a <= {dac_a[14-1], ~dac_a[14-2:0]};
  	dac_dat_b <= {dac_b[14-1], ~dac_b[14-2:0]};
//    dac_dat_b <= mod;	
    
	if(dac_a[14-1] == 1'b0 && dac_a[14-2:0] != 13'd0) //positive output and valur != 0
		pio_tt <= 1'b1;
	else
		pio_tt <= 1'b0;
end



//assign exp_n_io[0] = pio_tt;
assign exp_n_io[0] = mod;
// DDR outputs
ODDR oddr_dac_clk          (.Q(dac_clk_o), .D1(1'b0     ), .D2(1'b1     ), .C(dac_clk_2p), .CE(1'b1), .R(1'b0   ), .S(1'b0));
ODDR oddr_dac_wrt          (.Q(dac_wrt_o), .D1(1'b0     ), .D2(1'b1     ), .C(dac_clk_2x), .CE(1'b1), .R(1'b0   ), .S(1'b0));
ODDR oddr_dac_sel          (.Q(dac_sel_o), .D1(1'b1     ), .D2(1'b0     ), .C(dac_clk_1x), .CE(1'b1), .R(dac_rst), .S(1'b0));
ODDR oddr_dac_rst          (.Q(dac_rst_o), .D1(dac_rst  ), .D2(dac_rst  ), .C(dac_clk_1x), .CE(1'b1), .R(1'b0   ), .S(1'b0));
ODDR oddr_dac_dat [14-1:0] (.Q(dac_dat_o), .D1(dac_dat_b), .D2(dac_dat_a), .C(dac_clk_1x), .CE(1'b1), .R(dac_rst), .S(1'b0));

////////////////////////////////////////////////////////////////////////////////
//  House Keeping
////////////////////////////////////////////////////////////////////////////////

red_pitaya_id i_id (
  // system signals
  .clk_i           (adc_clk ),  // clock
  .rstn_i          (adc_rstn),  // reset - active low
  // global configuration
  .digital_loop    (digital_loop),
   // System bus
  .sys_addr        (sys[0].addr ),
  .sys_wdata       (sys[0].wdata),
  .sys_wen         (sys[0].wen  ),
  .sys_ren         (sys[0].ren  ),
  .sys_rdata       (sys[0].rdata),
  .sys_err         (sys[0].err  ),
  .sys_ack         (sys[0].ack  ),
  .reg_mod_H    (reg_mod_H),
  .reg_mod_L    (reg_mod_L),
  .reg_mod_freq_cnt (reg_mod_freq_cnt),
  .deMOD_mv_cnt (deMOD_mv_cnt),
  .reg_err_gain (reg_err_gain),
  .reg_vth (reg_vth),
  .reg_vth_1st_int(reg_vth_1st_int),
  .dac_ladder(dac_ladder),
  .err_polarity(err_polarity),
  .mod_off(mod_off),
  .ADC_reg_H(ADC_reg_H),
  .ADC_reg_L(ADC_reg_L),
  .ADC_reg_Diff(ADC_reg_Diff),
  .err_signal(err_signal),
  .ADC_reg_H_sum(ADC_reg_H_sum),
  .Init_stable_cnt(Init_stable_cnt),
  .ADC_reg_H_offset(ADC_reg_H_offset),
  .mv_mode(mv_mode),
  .test_add(test_add),
  .test(test),
  .ladder_rst(ladder_rst),
  .err_shift_idx(err_shift_idx),
  .err_signal_shift(err_signal_shift),
  .step_MV_sum(step_MV_sum),
  .ADC_reg_Diff_MV(ADC_reg_Diff_MV),
  .Diff_vth(Diff_vth),
  .step_MV_sum_out(step_MV_sum_out),
  .dac_ladder_pre(dac_ladder_pre),
  .err_shift_idx_pre(err_shift_idx_pre),
  .err_signal_pre(err_signal_pre),
  .dac_ladder_pre_vth(dac_ladder_pre_vth)
);

////////////////////////////////////////////////////////////////////////////////
// LED and GPIO
////////////////////////////////////////////////////////////////////////////////

IOBUF iobuf_led   [8-1:0] (.O(gpio.i[ 7: 0]), .IO(led_o)   , .I(gpio.o[ 7: 0]), .T(gpio.t[ 7: 0]));
IOBUF iobuf_exp_p [8-1:0] (.O(gpio.i[15: 8]), .IO(exp_p_io), .I(gpio.o[15: 8]), .T(gpio.t[15: 8]));
//IOBUF iobuf_exp_n [8-1:0] (.O(gpio.i[23:16]), .IO(exp_n_io), .I(gpio.o[23:16]), .T(gpio.t[23:16]));
IOBUF iobuf_exp_n [8-1:1] (.O(gpio.i[23:17]), .IO(exp_n_io[7:1]), .I(gpio.o[23:17]), .T(gpio.t[23:17]));


////////////////////////////////////////////////////////////////////////////////
// oscilloscope
////////////////////////////////////////////////////////////////////////////////

logic trig_asg_out;

red_pitaya_scope i_scope (
  // ADC
  .adc_a_i       (adc_dat[0]  ),  // CH 1
  .adc_b_i       (adc_dat[1]  ),  // CH 2
  .adc_clk_i     (adc_clk     ),  // clock
  .adc_rstn_i    (adc_rstn    ),  // reset - active low
  .trig_ext_i    (gpio.i[8]   ),  // external trigger
  .trig_asg_i    (trig_asg_out),  // ASG trigger
  // System bus
  .sys_addr      (sys[1].addr ),
  .sys_wdata     (sys[1].wdata),
  .sys_wen       (sys[1].wen  ),
  .sys_ren       (sys[1].ren  ),
  .sys_rdata     (sys[1].rdata),
  .sys_err       (sys[1].err  ),
  .sys_ack       (sys[1].ack  )
);

////////////////////////////////////////////////////////////////////////////////
//  DAC arbitrary signal generator
////////////////////////////////////////////////////////////////////////////////


red_pitaya_asg i_asg (
   // DAC
  .dac_a_o         (asg_dat[0]  ),  // CH 1
  .dac_b_o         (asg_dat[1]  ),  // CH 2
  .dac_clk_i       (adc_clk     ),  // clock
  .dac_rstn_i      (adc_rstn    ),  // reset - active low
  .trig_a_i        (gpio.i[8]   ),
  .trig_b_i        (gpio.i[8]   ),
  .trig_out_o      (trig_asg_out),
  // System bus
  .sys_addr        (sys[2].addr ),
  .sys_wdata       (sys[2].wdata),
  .sys_wen         (sys[2].wen  ),
  .sys_ren         (sys[2].ren  ),
  .sys_rdata       (sys[2].rdata),
  .sys_err         (sys[2].err  ),
  .sys_ack         (sys[2].ack  )
);

////////////////////////////////////////////////////////////////////////////////
//  MIMO PID controller
////////////////////////////////////////////////////////////////////////////////

red_pitaya_pid i_pid (
   // signals
  .clk_i           (adc_clk   ),  // clock
  .rstn_i          (adc_rstn  ),  // reset - active low
  .dat_a_i         (adc_dat[0]),  // in 1
  .dat_b_i         (adc_dat[1]),  // in 2
  .dat_a_o         (pid_dat[0]),  // out 1
  .dat_b_o         (pid_dat[1]),  // out 2
  // System bus
  .sys_addr        (sys[3].addr ),
  .sys_wdata       (sys[3].wdata),
  .sys_wen         (sys[3].wen  ),
  .sys_ren         (sys[3].ren  ),
  .sys_rdata       (sys[3].rdata),
  .sys_err         (sys[3].err  ),
  .sys_ack         (sys[3].ack  )
);

endmodule: red_pitaya_top
