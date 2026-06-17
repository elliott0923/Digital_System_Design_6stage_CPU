

module IF_IDC_Pipe(
    input clk,
    input rst_n,
    input stall,

    input [31:0] pre_instruction_in,
    input [31:0] PC_in,
    input [31:0] PC_plus_4_in,
    input        is_rvc_in,
    input        predict_taken_in,
    input [31:0] PC_plus_imm_in,

    output reg [31:0] pre_instruction_out,
    output reg [31:0] PC_out,
    output reg [31:0] PC_plus_4_out,
    output reg        is_rvc_out,
    output reg        predict_taken_out,
    output reg [31:0] PC_plus_imm_out
);

// Note the endien issue
parameter INST_NOP_param = 32'h00_00_00_13;

always @(posedge clk) begin
    if (!rst_n) begin
        pre_instruction_out <= INST_NOP_param;
        PC_out <= 0;
        PC_plus_4_out <= 0;
        is_rvc_out <= 0;
        predict_taken_out <= 0;
        PC_plus_imm_out <= 0;
    end
    else begin
        if(!stall) begin // If we do not need to stall
            pre_instruction_out <= pre_instruction_in;
            PC_out <= PC_in;
            PC_plus_4_out <= PC_plus_4_in;
            is_rvc_out <= is_rvc_in;
            predict_taken_out <= predict_taken_in;
            PC_plus_imm_out <= PC_plus_imm_in;

        end
    end
end

endmodule







module IDC_ID_Pipe(
    input clk,
    input rst_n,
    input stall,

    input [31:0] instruction_in,
    input [31:0] PC_in,
    input [31:0] PC_plus_4_in,
    input        predict_taken_in,
    input [31:0] PC_plus_imm_in,

    output reg [31:0] instruction_out,
    output reg [31:0] PC_out,
    output reg [31:0] PC_plus_4_out,
    output reg        predict_taken_out,
    output reg [31:0] PC_plus_imm_out
);

// Note the endien issue
parameter INST_NOP_param = 32'h00_00_00_13;

always @(posedge clk) begin
    if (!rst_n) begin
        instruction_out <= INST_NOP_param;
        PC_out <= 0;
        PC_plus_4_out <= 0;
        predict_taken_out <= 0;
        PC_plus_imm_out <= 0;
    end
    else begin
        if(!stall) begin // If we do not need to stall
            instruction_out <= instruction_in;
            PC_out <= PC_in;
            PC_plus_4_out <= PC_plus_4_in;
            predict_taken_out <= predict_taken_in;
            PC_plus_imm_out <= PC_plus_imm_in;
        end
    end
end

endmodule



module ID_EX_Pipe(
    input clk,
    input rst_n,
    input stall,

    // data input
    input [31:0] PC_in,
    input [31:0] PC_plus_4_in,
    input [31:0] data1_in,
    input [31:0] data2_in,
    input [31:0] imm_in,
    input [4:0]  rd_loc_in,
    input [4:0]  rs1_loc_in,
    input [4:0]  rs2_loc_in,

    // control input
    input [4:0]  ctrl_AluOp_in,    // EX
    input        ctrl_ALUSrc_A_in, // EX
    input        ctrl_ALUSrc_B_in, // EX

    input        ctrl_is_branch_in,// EX
    input        ctrl_is_jalr_in,  // EX

    input        ctrl_MemRead_in,  // MEM
    input        ctrl_MemWrite_in, // MEM
    input        ctrl_FLUSH_in,    // MEM
    input        ctrl_RegWrite_in, // WB
    input        ctrl_MemToReg_in, // WB
    input        ctrl_is_Mul_in,   // EX
    input        predict_taken_in,
    input [31:0] PC_plus_imm_in,

    // data output
    output reg [31:0] PC_out,
    output reg [31:0] PC_plus_4_out,
    output reg [31:0] data1_out,
    output reg [31:0] data2_out,
    output reg [31:0] imm_out,
    output reg [4:0]  rd_loc_out,
    output reg [4:0]  rs1_loc_out,
    output reg [4:0]  rs2_loc_out,

    // control output
    output reg [4:0]  ctrl_AluOp_out,    // EX
    output reg        ctrl_ALUSrc_A_out, // EX
    output reg        ctrl_ALUSrc_B_out, // EX

    output reg        ctrl_is_branch_out,// EX
    output reg        ctrl_is_jalr_out,  // EX

    output reg        ctrl_MemRead_out,  // MEM
    output reg        ctrl_MemWrite_out, // MEM
    output reg        ctrl_FLUSH_out,    // MEM
    output reg        ctrl_RegWrite_out, // WB
    output reg        ctrl_MemToReg_out, // WB
    output reg        ctrl_is_Mul_out,    // EX

    output reg        predict_taken_out,
    output reg [31:0] PC_plus_imm_out
);

always @(posedge clk) begin
    if(!rst_n) begin
        PC_out <= 0;
        PC_plus_4_out <= 0;
        data1_out <= 0;
        data2_out <= 0;
        imm_out <= 0;
        rd_loc_out <= 0;
        rs1_loc_out <= 0;
        rs2_loc_out <= 0;

        ctrl_AluOp_out <= 0;
        ctrl_ALUSrc_A_out <= 0;
        ctrl_ALUSrc_B_out <= 0;
        predict_taken_out <= 0;
        PC_plus_imm_out <= 0;


        ctrl_is_branch_out <= 0;
        ctrl_is_jalr_out <= 0;

        ctrl_MemRead_out <= 0;
        ctrl_MemWrite_out <= 0;
        ctrl_FLUSH_out <= 0;
        ctrl_RegWrite_out <= 0;
        ctrl_MemToReg_out <= 0;
        ctrl_is_Mul_out <= 0;
    end
    else begin
        if(!stall) begin // If we do not need to stall
            PC_out <= PC_in;
            PC_plus_4_out <= PC_plus_4_in;
            data1_out <= data1_in;
            data2_out <= data2_in;
            imm_out <= imm_in;
            rd_loc_out <= rd_loc_in;
            rs1_loc_out <= rs1_loc_in;
            rs2_loc_out <= rs2_loc_in;

            ctrl_AluOp_out <= ctrl_AluOp_in;
            ctrl_ALUSrc_A_out <= ctrl_ALUSrc_A_in;
            ctrl_ALUSrc_B_out <= ctrl_ALUSrc_B_in;
            predict_taken_out <= predict_taken_in;
            PC_plus_imm_out <= PC_plus_imm_in;

            ctrl_is_branch_out <= ctrl_is_branch_in;
            ctrl_is_jalr_out <= ctrl_is_jalr_in;

            ctrl_MemRead_out <= ctrl_MemRead_in;
            ctrl_MemWrite_out <= ctrl_MemWrite_in;
            ctrl_FLUSH_out <= ctrl_FLUSH_in;
            ctrl_RegWrite_out <= ctrl_RegWrite_in;
            ctrl_MemToReg_out <= ctrl_MemToReg_in;
            ctrl_is_Mul_out <= ctrl_is_Mul_in;
        end
    end
end

endmodule



module EX_MEM_Pipe(
    input clk,
    input rst_n,
    input stall,

    // data input
    input [31:0] ALU_result_in,
    input [31:0] data2_in,
    input [4:0]  rd_loc_in,
    input [4:0]  rs2_loc_in,

    // control input
    input        ctrl_MemRead_in,  // MEM
    input        ctrl_MemWrite_in, // MEM
    input        ctrl_FLUSH_in,    // MEM
    input        ctrl_RegWrite_in, // WB
    input        ctrl_MemToReg_in, // WB
    input        ctrl_is_Mul_in,      // EX

    // data output
    output reg [31:0] ALU_result_out,
    output reg [31:0] data2_out,
    output reg [4:0]  rd_loc_out,
    output reg [4:0]  rs2_loc_out,

    // control output
    output reg        ctrl_MemRead_out,  // MEM
    output reg        ctrl_MemWrite_out, // MEM
    output reg        ctrl_FLUSH_out,    // MEM
    output reg        ctrl_RegWrite_out, // WB
    output reg        ctrl_MemToReg_out, // WB
    output reg        ctrl_is_Mul_out      // EX
);

always @(posedge clk) begin
    if(!rst_n) begin
        ALU_result_out <= 0;
        data2_out <= 0;
        rd_loc_out <= 0;
        rs2_loc_out <= 0;

        ctrl_MemRead_out <= 0;
        ctrl_MemWrite_out <= 0;
        ctrl_FLUSH_out <= 0;
        ctrl_RegWrite_out <= 0;
        ctrl_MemToReg_out <= 0;
        ctrl_is_Mul_out <= 0;
    end
    else begin
        if(!stall) begin // If we do not need to stall
            ALU_result_out <= ALU_result_in;
            data2_out <= data2_in;
            rd_loc_out <= rd_loc_in;
            rs2_loc_out <= rs2_loc_in;

            ctrl_MemRead_out <= ctrl_MemRead_in;
            ctrl_MemWrite_out <= ctrl_MemWrite_in;
            ctrl_FLUSH_out <= ctrl_FLUSH_in;
            ctrl_RegWrite_out <= ctrl_RegWrite_in;
            ctrl_MemToReg_out <= ctrl_MemToReg_in;
            ctrl_is_Mul_out <= ctrl_is_Mul_in;
        end
    end
end

endmodule


module MEM_WB_Pipe(
    input clk,
    input rst_n,
    input stall,

    // data input
    input [31:0] MemRead_result_in,
    input [31:0] ALU_result_in,
    input [31:0] Compute_result_in,
    input [4:0]  rd_loc_in,

    //multiplier results
    input [31:0] mul_result_in,

    // control input
    input        ctrl_RegWrite_in, // WB
    input        ctrl_MemToReg_in, // WB
    input        ctrl_is_Mul_in,      // EX

    // data output
    output reg [31:0] MemRead_result_out,
    output reg [31:0] ALU_result_out,
    output reg [31:0] mul_result_out,
    output reg [31:0] Compute_result_out,
    output reg [4:0]  rd_loc_out,

    // control output
    output reg        ctrl_RegWrite_out, // WB
    output reg        ctrl_MemToReg_out, // WB
    output reg        ctrl_is_Mul_out      // EX
);

always @(posedge clk) begin
    if(!rst_n) begin
        MemRead_result_out <= 0;
        ALU_result_out <= 0;
        rd_loc_out <= 0;
        mul_result_out <= 0;
        Compute_result_out <= 0;

        ctrl_RegWrite_out <= 0;
        ctrl_MemToReg_out <= 0;
        ctrl_is_Mul_out <= 0;
    end
    else begin
        if(!stall) begin // If we do not need to stall
            MemRead_result_out <= MemRead_result_in;
            ALU_result_out <= ALU_result_in;
            Compute_result_out <= Compute_result_in;

            rd_loc_out <= rd_loc_in;

            ctrl_RegWrite_out <= ctrl_RegWrite_in;
            ctrl_MemToReg_out <= ctrl_MemToReg_in;

            //========================
            mul_result_out <= mul_result_in;
            ctrl_is_Mul_out <= ctrl_is_Mul_in;
        end
    end
end

endmodule
