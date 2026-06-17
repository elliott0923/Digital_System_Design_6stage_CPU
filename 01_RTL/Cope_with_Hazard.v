module ForwardingUnit_EX (
    input  [4:0] rs1_EX,
    input  [4:0] rs2_EX,
    input  [4:0] rd_MEM,
    input  [4:0] rd_WB,
    input        reg_write_MEM,
    input        reg_write_WB,
    output reg   [1:0] forwardA_EX,
    output reg   [1:0] forwardB_EX
);

always @(*) begin
    // Default: no forwarding
    forwardA_EX = 2'b00;
    forwardB_EX = 2'b00;

    // Check for MEM hazard
    if (reg_write_MEM && (rd_MEM == rs1_EX)) begin
        forwardA_EX = 2'b01; // Forward from MEM stage
    end
    else if (reg_write_WB && (rd_WB == rs1_EX)) begin
        forwardA_EX = 2'b10; // Forward from WB stage
    end
    if (reg_write_MEM && (rd_MEM == rs2_EX)) begin
        forwardB_EX = 2'b01; // Forward from MEM stage
    end
    else if (reg_write_WB && (rd_WB == rs2_EX)) begin
        forwardB_EX = 2'b10; // Forward from WB stage
    end
end

endmodule

module Hazard_Detect (
    input  [6:0] opcode_ID,   
    input  [4:0] rs1_ID,
    input  [4:0] rs2_ID,
    input  [4:0] rd_EX,
    input  [4:0] rd_MEM,
    input        ctrl_MemRead_EX,
    input        ctrl_MemRead_MEM,
    input        ctrl_is_Mul_EX,
    input        ctrl_real_jump_EX,

    output reg   Hazard_Stall_ID
);

    wire use_rs1 = (opcode_ID[6:2] == 5'b01100) || // R-type
                   (opcode_ID[6:2] == 5'b00100) || // I-type ALU
                   (opcode_ID[6:2] == 5'b00000) || // Load
                   (opcode_ID[6:2] == 5'b01000) || // Store
                   (opcode_ID[6:2] == 5'b11000) || // Branch
                   (opcode_ID[6:2] == 5'b11001);   // JALR

    wire use_rs2 = (opcode_ID[6:2] == 5'b01100) || // R-type
                   (opcode_ID[6:2] == 5'b01000) || // Store
                   (opcode_ID[6:2] == 5'b11000);   // Branch

    wire is_store = (opcode_ID[6:2] == 5'b01000);
    wire use_rs2_in_ex = use_rs2 && !is_store;

    always @(*) begin
        // Default: no hazard
        Hazard_Stall_ID = 1'b0;

        // Standard Load/Mul Use Hazard (Producer in EX)
        if(ctrl_real_jump_EX) begin
            Hazard_Stall_ID = 1'b0;
        end
        else if ((ctrl_MemRead_EX || ctrl_is_Mul_EX) && (rd_EX != 5'b0)) begin
            if ((use_rs1 && (rd_EX == rs1_ID)) || (use_rs2_in_ex && (rd_EX == rs2_ID))) begin
                Hazard_Stall_ID = 1'b1;
            end
        end
        
    end

endmodule
