`include "ALU.v"
`include "Control.v"
`include "I_cache.v"
`include "D_cache.v"
`include "Pipeline_reg.v"
`include "Cope_with_Hazard.v"
`include "FSM.v"
`include "Decompressor.v"


`ifdef USE_LFSR_CONV_PERFECT
    `include "Branch_Predictor_LFSR_Conv_Perfect.v"
`else
    `ifdef USE_CONV_PERFECT
        `include "Branch_Predictor_Conv_Perfect.v"
    `else
        `ifdef USE_LFSR_PERFECT
            `include "Branch_Predictor_LFSR_Perfect.v"
        `else
            `ifdef USE_GSHARE
                `include "Branch_Predictor_Gshare.v"
            `else
                `include "Branch_Predictor_LFSR_Conv_Perfect.v"
            `endif
        `endif
    `endif
`endif

module CHIP (	
	input			clk, rst_n,
//----------for slow_memD------------
	output			mem_read_D,
	output			mem_write_D,
	output	[31:4]	mem_addr_D,
	output	[127:0]	mem_wdata_D,
	input	[127:0]	mem_rdata_D,
	input			mem_ready_D,
//----------for slow_memI------------
	output			mem_read_I,
	output			mem_write_I,
	output	[31:4]	mem_addr_I,
	output	[127:0]	mem_wdata_I,
	input	[127:0]	mem_rdata_I,
	input			mem_ready_I,
//----------for TestBed--------------				
	output			o_done
);

// ========================================
// ALU operation encoding
// ========================================
parameter OP_NOP  = 5'b00000;
parameter OP_ADD  = 5'b00001;
parameter OP_SUB  = 5'b00010;
parameter OP_AND  = 5'b00011;
parameter OP_OR   = 5'b00100;
parameter OP_XOR  = 5'b00101;

parameter OP_SLT  = 5'b00110;
parameter OP_SLL  = 5'b00111;
parameter OP_SRL  = 5'b01000;
parameter OP_SRA  = 5'b01001;

parameter OP_BEQ  = 5'b01010;
parameter OP_BNE  = 5'b01011;

parameter OP_JAL  = 5'b01110;
parameter OP_JALR = 5'b01111;

// Change the endien!
parameter INST_FLUSH_param = 32'h00_20_20_07;
parameter INST_NOP_param   = 32'h00_00_00_13;

// ======== To deal with outside reset ======== 
// If you want reset to be in specail form, here!
reg rst_n_core;
reg rst_n_ohoh;
always@(negedge clk) begin
    rst_n_ohoh <= rst_n;
end
always@ (posedge clk) begin
    rst_n_core <= rst_n_ohoh;
end

// ===================================

// ===== Global D_cache stall =====
wire         D_cache_stall;

// ======== In IF stage ========
wire [31:0]  instruction_IF;
wire         I_cache_stall;
// D-cache stalls the MEM stage, so it must freeze the whole pipe.
// I-cache stalls are handled locally by the IF FSM; older stages can drain.
wire         global_stall = D_cache_stall; 

wire [31:0]  instruction_or_NOP_IF; // For flushing the instruction in IF stage, we can convert it to NOP by changing it to a NOP instruction (ADDI x0, x0, 0)


// ======== In IDC stage ==========

wire [31:0]  PC_IDC;
wire [31:0]  PC_plus_4_IDC;
wire [31:0]  pre_instruction_IDC;     // can include RVC or RV32
wire [31:0]  instruction_full_IDC;    // extend to RV32
wire [31:0]  instruction_real_IDC;    // consider the flush, somethimes need NOP
wire [31:0]  instruction_or_NOP_IDC;  // consider the flush, somethimes need NOP (same but does not delete)

wire [31:0] decoded_instruction_IDC;  // Those RVC => RV32
wire        is_jal_IF;
wire        is_branch_IF;
wire        ctrl_real_jump_IF;
wire        accept_inst_IF;

wire        predict_taken_IF;
wire        predict_taken_IDC;
wire        predict_taken_ID;
wire        predict_taken_EX;
wire [31:0] PC_plus_imm_IDC;
wire [31:0] PC_plus_imm_ID;
wire [31:0] PC_plus_imm_EX;

// ======== In ID stage ========
wire [31:0]  data1_ID;
wire [31:0]  data2_ID;
wire [31:0]  imm_ID;
wire [4:0]   rd_loc_ID;
wire [4:0]   rs1_loc_ID;
wire [4:0]   rs2_loc_ID;
wire [31:0]  instruction_ID;
wire [31:0]  PC_plus_4_ID;
wire [31:0]  PC_ID;

wire [4:0]  ctrl_AluOp_ID;
wire        ctrl_ALUSrc_A_ID;
wire        ctrl_ALUSrc_B_ID;
wire        ctrl_is_branch_ID;
wire        ctrl_is_jalr_ID;
wire        ctrl_MemRead_ID;
wire        ctrl_MemWrite_ID;
wire        ctrl_FLUSH_ID;
wire        ctrl_RegWrite_ID;
wire        ctrl_MemToReg_ID;

wire        Hazard_Stall_ID;


// ======== In EX stage ========
wire [31:0] have_not_forward_data1_EX;
wire [31:0] have_not_forward_data2_EX;

wire [31:0] PC_EX;
wire [31:0] PC_plus_4_EX;
wire [31:0] data1_EX;
wire [31:0] data2_EX;
wire [31:0] imm_EX;
wire [4:0]  rd_loc_EX;
wire [4:0]  rs1_loc_EX;
wire [4:0]  rs2_loc_EX;

wire [4:0]  ctrl_AluOp_EX;
wire        ctrl_ALUSrc_A_EX;
wire        ctrl_ALUSrc_B_EX;

wire        ctrl_is_branch_EX;
wire        ctrl_is_jalr_EX;
wire        ctrl_is_jump_EX = ctrl_ALUSrc_A_EX;
wire        ctrl_real_jump_EX;

wire        ctrl_MemRead_EX;
wire        ctrl_MemWrite_EX;
wire        ctrl_FLUSH_EX;
wire        ctrl_RegWrite_EX;
wire        ctrl_MemToReg_EX;

wire        ctrl_is_Mul_ID;
wire        ctrl_is_Mul_EX;
wire        ctrl_is_Mul_MEM;
wire        ctrl_is_Mul_WB;

wire [31:0] ALU_result_EX;
wire [31:0] ALU_input_A_EX;
wire [31:0] ALU_input_B_EX;

wire [1:0]  forwardA_EX;
wire [1:0]  forwardB_EX;
wire        true_branch_EX;

// ======== In MEM stage ========
wire        ctrl_MemRead_MEM;
wire        ctrl_MemWrite_MEM;
wire        ctrl_FLUSH_MEM;
wire        ctrl_RegWrite_MEM;
wire        ctrl_MemToReg_MEM;
wire [4:0]  rd_loc_MEM;
wire [4:0]  rs2_loc_MEM;
wire [31:0] ALU_result_MEM;
wire [31:0] data2_MEM; // For SW
wire [31:0] store_data_MEM;
wire [31:0] mem_rdata_MEM;

// ======== In WB stage ========
wire        ctrl_RegWrite_WB;
wire        ctrl_MemToReg_WB;
wire [4:0]  rd_loc_WB;
wire [31:0] rd_data_WB;
wire [31:0] Compute_result_WB;
wire [31:0] mem_rdata_WB;


// =================== 2-stage multiplier (EX-MEM) START =====================

// 1. Rename the multiplier output so it doesn't plug directly into the pipeline yet
wire [31:0] raw_mul_result; 

Multiplier_2Stage Multiplier0(
    .clk(clk),
    .src_a(data1_EX), 
    .src_b(data2_EX),
    .tc(1'b1), 
    .product_low(raw_mul_result) 
);

// 2. Add a shadow register to hold the result during stalls
reg [31:0] saved_mul_result;
reg        is_stalled_reg;

always @(posedge clk) begin
    if (!rst_n_core) begin
        saved_mul_result <= 32'b0;
        is_stalled_reg   <= 1'b0;
    end else begin
        // Track the stall state delayed by 1 cycle
        is_stalled_reg <= global_stall;
        
        // Capture the correct multiplier output EXACTLY on the first cycle of a stall
        if (global_stall && !is_stalled_reg) begin
            saved_mul_result <= raw_mul_result;
        end
    end
end

// 3. Re-create mul_result_MEM using a MUX
// If we are currently in a stall (or recovering from one), use the saved result.
// Otherwise, safely use the live streaming result from the multiplier.
wire [31:0] mul_result_MEM = (is_stalled_reg) ? saved_mul_result : raw_mul_result;

// 4. Your existing logic remains untouched
wire [31:0] compute_result_MEM = (ctrl_is_Mul_MEM) ? mul_result_MEM : ALU_result_MEM;

// =================== 2-stage multiplier (EX-MEM) END =====================



// =========================================
// ======== In IF stage (RVC 升級版) ========
// =========================================

// FSM 的相關連線
wire [31:0]  fsm_inst_out;
wire [31:0]  fsm_pc_out;
wire         fsm_inst_valid;
wire         fsm_is_rvc;
wire [29:0]  fsm_icache_addr;
wire         fsm_icache_read;
wire         if_fsm_stall;

// Cache 吐出來的原始資料與 Endian 轉換
wire [31:0]  raw_cache_rdata;
wire         raw_cache_resp_valid;
wire         raw_cache_resp_ready;
wire [31:0]  endian_fixed_cache_data;
assign endian_fixed_cache_data = {raw_cache_rdata[7:0], raw_cache_rdata[15:8], raw_cache_rdata[23:16], raw_cache_rdata[31:24]};

// 算出下一條指令的 PC (JAL/JALR 寫回 rd 用的回傳位址)
// 注意：如果有 RVC，下一條指令可能是 +2 也可能是 +4
wire [31:0]  PC_return_addr_IF = fsm_pc_out + (fsm_is_rvc ? 32'd2 : 32'd4);


wire        ctrl_PCSrc_IF;
// wire        ctrl_PCSrc_ID; // later
wire        ctrl_PCSrc_EX;
wire        ctrl_PCSrc_EX_to_IF;
wire [31:0] PC_computed_IF;
wire [31:0] PC_computed_target_IF;
// wire [31:0] PC_computed_ID; // later
wire [31:0] PC_computed_EX;
reg         sent_EX_redirect_during_stall;

always @(posedge clk) begin
    if (!rst_n_core) begin
        sent_EX_redirect_during_stall <= 1'b0;
    end
    else if (!ctrl_PCSrc_EX) begin
        sent_EX_redirect_during_stall <= 1'b0;
    end
    else if (global_stall) begin
        sent_EX_redirect_during_stall <= 1'b1;
    end
    else begin
        sent_EX_redirect_during_stall <= 1'b0;
    end
end

assign ctrl_PCSrc_EX_to_IF = ctrl_PCSrc_EX && !sent_EX_redirect_during_stall;

// Redirect priority follows program age: EX is older than IF.
assign PC_computed_IF = (ctrl_PCSrc_EX_to_IF) ? PC_computed_EX :
                                               PC_computed_target_IF;
assign ctrl_PCSrc_IF = ctrl_PCSrc_EX_to_IF | ctrl_real_jump_IF;

// Backend/hazard stalls must hold the visible frontend pipes, but the IF FSM
// can still fill its own output slot while that slot is empty.
assign if_fsm_stall = (global_stall || Hazard_Stall_ID) && fsm_inst_valid;

Compressed_IF_FSM U_IF_FSM (
    .clk            (clk),
    .rst_n          (rst_n_core),
    
    // Hazard only stalls the FSM when its output slot is already occupied.
    .stall_i        (if_fsm_stall), 
    .flush_i        (1'b0), 
    
    // 【關鍵2】接收 Control 算出來的 Branch/Jump 跳轉訊號
    .redirect_i     (ctrl_PCSrc_IF),     
    .redirect_pc_i  (PC_computed_IF),  
    
    // 與 I-Cache 的溝通
    .icache_rdata_i (endian_fixed_cache_data), // 餵給 FSM 已經轉好 Endian 的資料
    .icache_resp_valid_i (raw_cache_resp_valid),
    .icache_stall_i (I_cache_stall),
    .icache_read_o  (fsm_icache_read),
    .icache_addr_o  (fsm_icache_addr),
    .icache_resp_ready_o (raw_cache_resp_ready),
    
    // 輸出給後端 Pipeline
    .inst_o         (fsm_inst_out),     
    .pc_o           (fsm_pc_out),       
    .inst_valid_o   (fsm_inst_valid),
    .is_rvc_o       (fsm_is_rvc)
);

Compute_target_PC_IDC Compute_target_PC_IF0(
    // input
    .pre_instruction_IDC(fsm_inst_out),
    .is_rvc_IDC(fsm_is_rvc),
    .PC_IDC(fsm_pc_out),
    // output
    .early_target_PC_IDC(PC_computed_target_IF),
    .is_jal_IDC(is_jal_IF),
    .is_branch_IDC(is_branch_IF)
);

Branch_Predictor Branch_Predictor0(
    // input
    .clk(clk),
    .rst_n(rst_n_core),
    .pc_idc(fsm_pc_out),
    .update_en(ctrl_is_branch_EX),      // high if EX stage has a branch
    .pc_ex(PC_EX),
    .actual_taken(true_branch_EX),      // actual outcome from EX stage
    // output
    .predict_taken(predict_taken_IF)    // predict result in IF stage
);

// JAL and predicted branches redirect as soon as the IF FSM emits them.
// Only redirect when the emitted instruction is accepted by IF/IDC; otherwise
// a held instruction during a stall would redirect repeatedly before entering the pipe.
assign accept_inst_IF = fsm_inst_valid &&
                        !(global_stall || Hazard_Stall_ID) &&
                        !ctrl_real_jump_EX;
assign ctrl_real_jump_IF = accept_inst_IF &&
                           (is_jal_IF || (is_branch_IF && predict_taken_IF));

assign instruction_or_NOP_IF = (ctrl_PCSrc_EX_to_IF || !fsm_inst_valid) ? INST_NOP_param : fsm_inst_out;

I_cache I_cache_0(
    .clk(clk),
    .proc_reset(!rst_n_core),
    .proc_read(fsm_icache_read),     // 由 FSM 控制讀取
    .proc_write(1'b0),               
    .proc_addr(fsm_icache_addr),     // 【關鍵3】位址改由 FSM 提供 (已經是 [31:2] 格式了)
    .proc_rdata(raw_cache_rdata),    // 原始資料先拉出來做 Endian 轉換
    .proc_resp_valid(raw_cache_resp_valid),
    .proc_resp_ready(raw_cache_resp_ready),
    .proc_wdata(32'b0), 
    .proc_stall(I_cache_stall),
    .mem_read(mem_read_I),
    .mem_write(mem_write_I),
    .mem_addr(mem_addr_I),
    .mem_rdata(mem_rdata_I),
    .mem_wdata(mem_wdata_I),
    .mem_ready(mem_ready_I)
);

// =========================================
// ======== In IF stage END (RVC 升級版) ========
// =========================================
wire is_rvc_IDC;

IF_IDC_Pipe IF_IDC_Pipe0(
    .clk(clk),
    .rst_n(rst_n_core),
    .stall(global_stall || Hazard_Stall_ID), 

    .pre_instruction_in(instruction_or_NOP_IF), 
    .PC_in(fsm_pc_out),                  // 【關鍵4】PC 改接 FSM 給出的正確當前 PC
    .PC_plus_4_in(PC_return_addr_IF),    // 【關鍵5】PC_plus_4_in 變成動態的 +2 或 +4
    .is_rvc_in(fsm_is_rvc),
    .predict_taken_in(accept_inst_IF && is_branch_IF && predict_taken_IF),
    .PC_plus_imm_in(PC_computed_target_IF),

    .pre_instruction_out(pre_instruction_IDC),
    .PC_out(PC_IDC),
    .PC_plus_4_out(PC_plus_4_IDC),
    .is_rvc_out(is_rvc_IDC),
    .predict_taken_out(predict_taken_IDC),
    .PC_plus_imm_out(PC_plus_imm_IDC)
);

// =========================================
// ======== In IDC stage (RVC 升級版) =======
// =========================================

Decompressor Decompressor0(
    .c_inst(pre_instruction_IDC[15:0]),
    .ext_inst(decoded_instruction_IDC)
);

assign instruction_full_IDC = (is_rvc_IDC) ? decoded_instruction_IDC : pre_instruction_IDC;
assign instruction_real_IDC = (ctrl_real_jump_EX)? INST_NOP_param : instruction_full_IDC;
assign instruction_or_NOP_IDC = instruction_real_IDC;

// =========================================
// ======== In IDC stage end (RVC 升級版) ========
// =========================================

IDC_ID_Pipe IDC_ID_Pipe0(
    .clk(clk),
    .rst_n(rst_n_core),
    .stall(global_stall || Hazard_Stall_ID), 

    .instruction_in(instruction_or_NOP_IDC), 
    .PC_in(PC_IDC),                  // 【關鍵4】PC 改接 FSM 給出的正確當前 PC
    .PC_plus_4_in(PC_plus_4_IDC),    // 【關鍵5】PC_plus_4_in 變成動態的 +2 或 +4
    .predict_taken_in(predict_taken_IDC),
    .PC_plus_imm_in(PC_plus_imm_IDC),

    .instruction_out(instruction_ID),
    .PC_out(PC_ID),
    .PC_plus_4_out(PC_plus_4_ID),
    .predict_taken_out(predict_taken_ID),
    .PC_plus_imm_out(PC_plus_imm_ID)
);

// =========================================
// ======== In ID stage (RVC 升級版) ========
// =========================================

Hazard_Detect Hazard_Detect0(
	.opcode_ID(instruction_ID[6:0]), 
	.rs1_ID(rs1_loc_ID),
	.rs2_ID(rs2_loc_ID),
	.rd_EX(rd_loc_EX),
	.rd_MEM(rd_loc_MEM),
	.ctrl_MemRead_EX(ctrl_MemRead_EX),
	.ctrl_MemRead_MEM(ctrl_MemRead_MEM),
	.Hazard_Stall_ID(Hazard_Stall_ID),
	.ctrl_is_Mul_EX(ctrl_is_Mul_EX), // 乘法指令也會引起 load-use hazard
    .ctrl_real_jump_EX(ctrl_real_jump_EX)
);

Control Control0(
    // input
	.instruction(instruction_ID),
	.Hazard_Stall_ID(Hazard_Stall_ID || ctrl_real_jump_EX), // When to pass the NOP

    // output
	.ctrl_AluOp(ctrl_AluOp_ID),
	.ctrl_ALUSrc_A(ctrl_ALUSrc_A_ID),
	.ctrl_ALUSrc_B(ctrl_ALUSrc_B_ID),

    .ctrl_is_branch(ctrl_is_branch_ID),
    .ctrl_is_jalr(ctrl_is_jalr_ID),

	.ctrl_MemRead(ctrl_MemRead_ID),
	.ctrl_MemWrite(ctrl_MemWrite_ID),
	.ctrl_FLUSH(ctrl_FLUSH_ID),
	.ctrl_RegWrite(ctrl_RegWrite_ID),
	.ctrl_MemToReg(ctrl_MemToReg_ID),
	.ctrl_is_Mul(ctrl_is_Mul_ID)
);

Imm_Gen Imm_Gen0(
	.instruction(instruction_ID),
	.imm(imm_ID)
);

assign rs1_loc_ID = instruction_ID[19:15];
assign rs2_loc_ID = instruction_ID[24:20];
assign rd_loc_ID  = instruction_ID[11:7];

Regfile Regfile0(
	.clk(clk),
	.rst_n(rst_n_core),
	.rs1_addr(rs1_loc_ID),
	.rs2_addr(rs2_loc_ID),
	.rd_addr(rd_loc_WB),
	.rd_data(rd_data_WB),
	.reg_write(ctrl_RegWrite_WB),
	.rs1_data(data1_ID),
	.rs2_data(data2_ID)
);


// =========================================
// ======== In ID stage END (RVC 升級版) ========
// =========================================

ID_EX_Pipe ID_EX_Pipe0(
	.clk(clk),
	.rst_n(rst_n_core),
	.stall(global_stall),

    .PC_in(PC_ID),
	.PC_plus_4_in(PC_plus_4_ID),
	.data1_in(data1_ID),
	.data2_in(data2_ID),
	.imm_in(imm_ID),
	.rd_loc_in(rd_loc_ID),
	.rs1_loc_in(rs1_loc_ID),
	.rs2_loc_in(rs2_loc_ID),
	.ctrl_AluOp_in(ctrl_AluOp_ID),
	.ctrl_ALUSrc_A_in(ctrl_ALUSrc_A_ID),
	.ctrl_ALUSrc_B_in(ctrl_ALUSrc_B_ID),
    .predict_taken_in(predict_taken_ID),
    .PC_plus_imm_in(PC_plus_imm_ID),

    .ctrl_is_branch_in(ctrl_is_branch_ID),
    .ctrl_is_jalr_in(ctrl_is_jalr_ID),

	.ctrl_MemRead_in(ctrl_MemRead_ID),
	.ctrl_MemWrite_in(ctrl_MemWrite_ID),
	.ctrl_FLUSH_in(ctrl_FLUSH_ID),
	.ctrl_RegWrite_in(ctrl_RegWrite_ID),
	.ctrl_MemToReg_in(ctrl_MemToReg_ID),
	.ctrl_is_Mul_in(ctrl_is_Mul_ID),

    .PC_out(PC_EX),
	.PC_plus_4_out(PC_plus_4_EX),
	.data1_out(have_not_forward_data1_EX),
	.data2_out(have_not_forward_data2_EX),
	.imm_out(imm_EX),
	.rd_loc_out(rd_loc_EX),
	.rs1_loc_out(rs1_loc_EX),
	.rs2_loc_out(rs2_loc_EX),
	.ctrl_AluOp_out(ctrl_AluOp_EX),
	.ctrl_ALUSrc_A_out(ctrl_ALUSrc_A_EX),
	.ctrl_ALUSrc_B_out(ctrl_ALUSrc_B_EX),
    .predict_taken_out(predict_taken_EX),
    .PC_plus_imm_out(PC_plus_imm_EX),

    .ctrl_is_branch_out(ctrl_is_branch_EX),
    .ctrl_is_jalr_out(ctrl_is_jalr_EX),

	.ctrl_MemRead_out(ctrl_MemRead_EX),
	.ctrl_MemWrite_out(ctrl_MemWrite_EX),
	.ctrl_FLUSH_out(ctrl_FLUSH_EX),
	.ctrl_RegWrite_out(ctrl_RegWrite_EX),
	.ctrl_MemToReg_out(ctrl_MemToReg_EX),
	.ctrl_is_Mul_out(ctrl_is_Mul_EX)
);

// =========================================
// ======== In EX stage (RVC 升級版) ========
// =========================================

ALU ALU0(
	.src_a(ALU_input_A_EX),
	.src_b(ALU_input_B_EX),
	.alu_op(ctrl_AluOp_EX),
	.alu_result(ALU_result_EX)
);

wire [31:0] rs1_plus_imm_EX;
assign rs1_plus_imm_EX = data1_EX + imm_EX;
assign PC_computed_EX = (ctrl_is_jalr_EX)  ? {rs1_plus_imm_EX[31:1], 1'b0} : 
                        (predict_taken_EX) ? PC_plus_4_EX :
                        PC_plus_imm_EX;

// Note that the above "PC+4" is in fact PC+2 or PC+4, we just do not want to modify the name

ForwardingUnit_EX ForwardingUnit_EX0(
	.rs1_EX(rs1_loc_EX),
	.rs2_EX(rs2_loc_EX),
	.rd_MEM(rd_loc_MEM),
	.rd_WB(rd_loc_WB),
	.reg_write_MEM(ctrl_RegWrite_MEM),
	.reg_write_WB(ctrl_RegWrite_WB),
	.forwardA_EX(forwardA_EX),
	.forwardB_EX(forwardB_EX)
);

wire   mispredict_EX = ctrl_is_branch_EX && (true_branch_EX ^ predict_taken_EX);

assign true_branch_EX = (ALU_result_EX[0] && ctrl_is_branch_EX);
assign ctrl_PCSrc_EX = (ctrl_is_jalr_EX) || mispredict_EX; // jalr or mispredicted branch
assign ctrl_real_jump_EX = ctrl_PCSrc_EX;

assign data1_EX = (forwardA_EX == 2'b00) ? have_not_forward_data1_EX :
                  (forwardA_EX == 2'b01) ? ALU_result_MEM : // MEM 階段 Forward
                  (forwardA_EX == 2'b10) ? rd_data_WB :     // WB 階段 Forward
                                           32'b0;

assign data2_EX = (forwardB_EX == 2'b00) ? have_not_forward_data2_EX :
                  (forwardB_EX == 2'b01) ? ALU_result_MEM : // MEM 階段 Forward
                  (forwardB_EX == 2'b10) ? rd_data_WB :     // WB 階段 Forward
                                           32'b0;

assign ALU_input_A_EX = (ctrl_ALUSrc_A_EX) ? PC_plus_4_EX : data1_EX;
assign ALU_input_B_EX = (ctrl_ALUSrc_B_EX) ? imm_EX : data2_EX;

// =========================================
// ======== In EX stage END (RVC 升級版) ========
// =========================================

EX_MEM_Pipe EX_MEM_Pipe0(
	.clk(clk),
	.rst_n(rst_n_core),
	.stall(global_stall),

	.ALU_result_in(ALU_result_EX),
	.data2_in(data2_EX),
	.rd_loc_in(rd_loc_EX),
	.rs2_loc_in(rs2_loc_EX),

	.ctrl_MemRead_in(ctrl_MemRead_EX),  // MEM
	.ctrl_MemWrite_in(ctrl_MemWrite_EX), // MEM
	.ctrl_FLUSH_in(ctrl_FLUSH_EX),    // MEM
	.ctrl_RegWrite_in(ctrl_RegWrite_EX), // WB
	.ctrl_MemToReg_in(ctrl_MemToReg_EX), // WB
	.ctrl_is_Mul_in(ctrl_is_Mul_EX), // EX

	.ALU_result_out(ALU_result_MEM),
	.data2_out(data2_MEM),
	.rd_loc_out(rd_loc_MEM),
	.rs2_loc_out(rs2_loc_MEM),

	.ctrl_MemRead_out(ctrl_MemRead_MEM),  // MEM
	.ctrl_MemWrite_out(ctrl_MemWrite_MEM), // MEM
	.ctrl_FLUSH_out(ctrl_FLUSH_MEM),    // MEM
	.ctrl_RegWrite_out(ctrl_RegWrite_MEM), // WB
	.ctrl_MemToReg_out(ctrl_MemToReg_MEM), // WB
	.ctrl_is_Mul_out(ctrl_is_Mul_MEM)      // EX
);

// =========================================
// ======== In MEM stage (RVC 升級版) =======
// =========================================

assign store_data_MEM = (ctrl_MemWrite_MEM && ctrl_RegWrite_WB &&
                         (rd_loc_WB != 5'b0) && (rd_loc_WB == rs2_loc_MEM)) ?
                        rd_data_WB : data2_MEM;

D_cache D_cache_0(
	.clk(clk),
	.proc_reset(!rst_n_core),
	.proc_read(ctrl_MemRead_MEM),
	.proc_write(ctrl_MemWrite_MEM),
	.proc_addr(ALU_result_MEM[31:2]), // Word aligned
	.proc_rdata({mem_rdata_MEM[7:0], mem_rdata_MEM[15:8], mem_rdata_MEM[23:16], mem_rdata_MEM[31:24]}), // Endian issue
	.proc_wdata({store_data_MEM[7:0], store_data_MEM[15:8], store_data_MEM[23:16], store_data_MEM[31:24]}), // Endian issue
	.proc_stall(D_cache_stall),
	.mem_read(mem_read_D),
	.mem_write(mem_write_D),
	.mem_addr(mem_addr_D),
    .mem_rdata(mem_rdata_D),
    .mem_wdata(mem_wdata_D),
    .mem_ready(mem_ready_D),
	.proc_flush(ctrl_FLUSH_MEM),
    .proc_o_done(o_done)
);


// =========================================
// ======== In MEM stage END (RVC 升級版) ========
// =========================================

MEM_WB_Pipe MEM_WB_Pipe0(
	.clk(clk),
	.rst_n(rst_n_core),
	.stall(global_stall),

	.MemRead_result_in(mem_rdata_MEM),
	.ALU_result_in(ALU_result_MEM),
	.Compute_result_in(compute_result_MEM),
	.rd_loc_in(rd_loc_MEM),
	.mul_result_in(mul_result_MEM),

	.ctrl_RegWrite_in(ctrl_RegWrite_MEM), // WB
	.ctrl_MemToReg_in(ctrl_MemToReg_MEM), // WB
	.ctrl_is_Mul_in(ctrl_is_Mul_MEM),

	.MemRead_result_out(mem_rdata_WB),
	.Compute_result_out(Compute_result_WB),
	.rd_loc_out(rd_loc_WB),

	.ctrl_RegWrite_out(ctrl_RegWrite_WB), // WB
	.ctrl_MemToReg_out(ctrl_MemToReg_WB), // WB
	.ctrl_is_Mul_out(ctrl_is_Mul_WB)     // EX
);

// =========================================
// ======== In WB stage (RVC 升級版) ========
// =========================================

assign rd_data_WB = (ctrl_MemToReg_WB) ? mem_rdata_WB :  
                                         Compute_result_WB;


endmodule





module Multiplier_2Stage (
    input         clk,
    input  [31:0] src_a,     // 來自 EX Stage
    input  [31:0] src_b,     // 來自 EX Stage
    input      tc,        // 算低 32 位元時，Signed/Unsigned 結果完全相同，故此處無需 tc 訊號
    output [31:0] product_low 
);

    // --- 1. 依圖片邏輯：切分運算元為高低 16-bit ---
    wire [15:0] a1 = src_a[31:16]; // 圖片中的 a1
    wire [15:0] a2 = src_a[15:0];  // 圖片中的 a2
    wire [15:0] b1 = src_b[31:16]; // 圖片中的 b1
    wire [15:0] b2 = src_b[15:0];  // 圖片中的 b2

    // 宣告三個 2-Stage DesignWare 乘法器的輸出線路 (16x16 乘積為 32-bit)
    wire [31:0] p_a2b2;
    wire [31:0] p_a1b2;
    wire [31:0] p_a2b1;

    // --- 2. 實例化三個 16x16 的 2-Stage DesignWare 乘法器 ---
    
    // (項次一) a2 * b2 ：貢獻給最底部的位元，需要完整的 32-bit 結果
    DW02_mult_2_stage #(
        .A_width(16),
        .B_width(16)
    ) U_mult_a2b2 (
        .A(a2),
        .B(b2),
        .TC(1'b0), // 填 0 代表 Unsigned
        .CLK(clk),
        .PRODUCT(p_a2b2)
    );

    // (項次二) a1 * b2 ：交叉項，後續會左移 16 位元
    DW02_mult_2_stage #(
        .A_width(16),
        .B_width(16)
    ) U_mult_a1b2 (
        .A(a1),
        .B(b2),
        .TC(1'b0),
        .CLK(clk),
        .PRODUCT(p_a1b2)
    );

    // (項次三) a2 * b1 ：交叉項，後續會左移 16 位元
    DW02_mult_2_stage #(
        .A_width(16),
        .B_width(16)
    ) U_mult_a2b1 (
        .A(a2),
        .B(b1),
        .TC(1'b0),
        .CLK(clk),
        .PRODUCT(p_a2b1)
    );

    // --- 3. 組合邏輯運算 (在 Stage 2 輸出端進行加法與移位) ---
    
    // 根據你的公式：A * B = a2*b2 + 2^16 * (a1*b2 + a2*b1)
    // 因為 final_result 只要取低 32 位元，而交叉項會被左移 16 位元，
    // 這代表交叉項相加後，超過低 16 位元的部分（即 [31:16]）在左移後會超出 32-bit 邊界而溢出。
    // 因此，交叉項我們只需要取低 16 位元 [15:0] 進行相加即可。
    wire [15:0] cross_sum = p_a1b2[15:0] + p_a2b1[15:0];
    
    // 用位元拼接（Bit-concatenation）實現乘以 2^16（左移 16 位元，後面補 16 個 0）
    wire [31:0] cross_sum_shifted = {cross_sum, 16'd0};

    // 最終加總，得到符合 RV32I MUL 規範的低 32 位元結果
    assign product_low = p_a2b2 + cross_sum_shifted;

endmodule

module Imm_Gen (
    input  [31:0] instruction,
    output reg [31:0] imm
);

// RISC-V opcode field
wire [6:0] opcode;
assign opcode = instruction[6:0];

always @(*) begin
    case (opcode[6:2])

        // =========================
        // I-Type
        // ADDI, ANDI, ORI, XORI
        // SLLI, SRLI, SRAI
        // SLTI, LW, JALR
        // =========================
        5'b00100, // immediate arithmetic
        5'b00000, // load
        5'b11001: // JALR
        begin
            imm = {{20{instruction[31]}}, instruction[31:20]};
        end

        // =========================
        // S-Type
        // SW
        // =========================
        5'b01000:
        begin
            imm = {
                {20{instruction[31]}},
                instruction[31:25],
                instruction[11:7]
            };
        end

        // =========================
        // B-Type
        // BEQ, BNE
        // =========================
        5'b11000:
        begin
            imm = {
                {19{instruction[31]}},
                instruction[31],
                instruction[7],
                instruction[30:25],
                instruction[11:8],
                1'b0
            };
        end

        // =========================
        // J-Type
        // JAL
        // =========================
        5'b11011:
        begin
            imm = {
                {11{instruction[31]}},
                instruction[31],
                instruction[19:12],
                instruction[20],
                instruction[30:21],
                1'b0
            };
        end

        // =========================
        // R-Type / default
        // ADD, SUB, AND, OR, XOR
        // SLT, NOP
        // =========================
        default:
        begin
            imm = 32'b0;
        end

    endcase
end

endmodule


module Compute_target_PC_IDC(
    input [31:0]  pre_instruction_IDC,
    input         is_rvc_IDC,
    input [31:0]  PC_IDC,

    output [31:0] early_target_PC_IDC,
    output reg    is_jal_IDC,
    output reg    is_branch_IDC
);

    // -- Compute the imm, and find the jump address --
    // =========================================================
    // IDC Stage: Early Target PC Predictor & Imm Decoder
    // =========================================================
    wire [31:0] pre_inst = pre_instruction_IDC;
    
    // ---------------------------------------------------------
    // 2. Pre-wire all possible Immediate formats
    // ---------------------------------------------------------
    // Standard RV32 J-Type (JAL)
    wire [31:0] imm_jal_32 = {{12{pre_inst[31]}}, pre_inst[19:12], pre_inst[20], pre_inst[30:21], 1'b0};
    
    // Standard RV32 B-Type (BEQ, BNE, BLT, BGE, BLTU, BGEU)
    wire [31:0] imm_b_32   = {{20{pre_inst[31]}}, pre_inst[7], pre_inst[30:25], pre_inst[11:8], 1'b0};
    
    // Compressed RV32C J-Type (C.J, C.JAL)
    wire [31:0] imm_cj_16  = {{20{pre_inst[12]}}, pre_inst[12], pre_inst[8], pre_inst[10:9], pre_inst[6], pre_inst[7], pre_inst[2], pre_inst[11], pre_inst[5:3], 1'b0};
    
    // Compressed RV32C B-Type (C.BEQZ, C.BNEZ)
    wire [31:0] imm_cb_16  = {{23{pre_inst[12]}}, pre_inst[12], pre_inst[6:5], pre_inst[2], pre_inst[11:10], pre_inst[4:3], 1'b0};

    // ---------------------------------------------------------
    // 3. Select the correct immediate based on Opcode
    // ---------------------------------------------------------
    reg [31:0] early_imm_IDC;
    always @(*) begin
        early_imm_IDC = 32'b0; // Default
        is_jal_IDC = 0;
        is_branch_IDC = 0;

        if (is_rvc_IDC) begin
            // RV32C Instruction Matching
            if (pre_inst[1:0] == 2'b01) begin
                if (pre_inst[15:13] == 3'b101 || pre_inst[15:13] == 3'b001) begin
                    // C.J or C.JAL
                    early_imm_IDC = imm_cj_16;
                    is_jal_IDC = 1;
                end 
                else if (pre_inst[15:13] == 3'b110 || pre_inst[15:13] == 3'b111) begin
                    // C.BEQZ or C.BNEZ
                    early_imm_IDC = imm_cb_16;
                    is_branch_IDC = 1;
                end
            end
        end 
        else begin
            // Standard RV32 Instruction Matching
            if (pre_inst[6:2] == 5'b11011) begin
                // JAL
                early_imm_IDC = imm_jal_32;
                is_jal_IDC = 1;
            end 
            else if (pre_inst[6:2] == 5'b11000) begin
                // BEQ, BNE, etc.
                early_imm_IDC = imm_b_32;
                is_branch_IDC = 1;
            end
        end
    end
    // ---------------------------------------------------------
    // 4. Compute the Target PC Early
    // ---------------------------------------------------------
    // PC_IDC should be the program counter for the instruction currently in the IDC stage
    assign early_target_PC_IDC = PC_IDC + early_imm_IDC;

endmodule


module Regfile (
    input         clk,
    input         rst_n,

    input  [4:0]  rs1_addr,
    input  [4:0]  rs2_addr,
    input  [4:0]  rd_addr,
    input  [31:0] rd_data,
    input         reg_write,

    output [31:0] rs1_data,
    output [31:0] rs2_data
);

// 32 registers, each 32 bits
reg [31:0] reg_file [0:31];

integer i;

// synchronous write
always @(posedge clk) begin
    if (!rst_n) begin
        for (i = 0; i < 32; i = i + 1) begin
            reg_file[i] <= 32'b0;
        end
    end
    else begin
        // x0 is always zero
        if (reg_write) begin
            reg_file[rd_addr] <= rd_data;
        end
    end
end

// asynchronous read with bypass (write-first behavior)
assign rs1_data =
    (rs1_addr == 5'd0) ? 32'b0 :
    (reg_write && (rd_addr == rs1_addr)) ? rd_data :
    reg_file[rs1_addr];

assign rs2_data =
    (rs2_addr == 5'd0) ? 32'b0 :
    (reg_write && (rd_addr == rs2_addr)) ? rd_data :
    reg_file[rs2_addr];

endmodule
