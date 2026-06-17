// ===============================================================
// RISC-V RV32C (Compressed Instruction) Decompressor - ULTIMATE FIX
// ===============================================================
module Decompressor(
    input  [15:0] c_inst,      
    output reg [31:0] ext_inst 
);
    wire [1:0] op     = c_inst[1:0];      
    wire [2:0] funct3 = c_inst[15:13];    

    wire [4:0] rd_rs1 = c_inst[11:7];
    wire [4:0] rs2    = c_inst[6:2];

    wire [4:0] rvc_rs1_s = {2'b01, c_inst[9:7]};
    wire [4:0] rvc_rs2_s = {2'b01, c_inst[4:2]};

    // Immediates
    wire [20:0] j_imm = {{9{c_inst[12]}}, c_inst[12], c_inst[8], c_inst[10:9], c_inst[6], c_inst[7], c_inst[2], c_inst[11], c_inst[5:3], 1'b0};
    wire [12:0] b_imm = {{4{c_inst[12]}}, c_inst[12], c_inst[6:5], c_inst[2], c_inst[11:10], c_inst[4:3], 1'b0};
    wire [11:0] lw_imm = {5'b0, c_inst[5], c_inst[12:10], c_inst[6], 2'b00};
    wire [11:0] lwsp_imm = {4'b0, c_inst[3:2], c_inst[12], c_inst[6:4], 2'b00};
    wire [11:0] swsp_imm = {4'b0, c_inst[8:7], c_inst[12:9], 2'b00};
    wire [11:0] addi16sp_imm = {{2{c_inst[12]}}, c_inst[12], c_inst[4:3], c_inst[5], c_inst[2], c_inst[6], 4'b0000};
    
    //  關鍵新增：C.ADDI4SPN 專用 Immediate
    wire [11:0] addi4spn_imm = {2'b00, c_inst[10:7], c_inst[12:11], c_inst[5], c_inst[6], 2'b00};

    always @(*) begin
        ext_inst = 32'h00000013; // 預設 NOP

        case(op)
            // ==========================================
            // Quadrant 00 
            // ==========================================
            2'b00: begin
                case(funct3)
                    3'b000: begin //  C.ADDI4SPN (NEW) -> addi rd', x2, nzuimm
                        if (c_inst[12:5] != 8'b0) 
                            ext_inst = {addi4spn_imm, 5'b00010, 3'b000, rvc_rs2_s, 7'b0010011};
                        else
                            ext_inst = 32'h00000013;
                    end
                    3'b010: // C.LW
                        ext_inst = {lw_imm, rvc_rs1_s, 3'b010, rvc_rs2_s, 7'b0000011};
                    3'b110: // C.SW
                        ext_inst = {lw_imm[11:5], rvc_rs2_s, rvc_rs1_s, 3'b010, lw_imm[4:0], 7'b0100011};
                    default: ext_inst = 32'h00000013;
                endcase
            end

            // ==========================================
            // Quadrant 01 
            // ==========================================
            2'b01: begin
                case(funct3)
                    3'b000: // C.ADDI
                        ext_inst = {{6{c_inst[12]}}, c_inst[12], c_inst[6:2], rd_rs1, 3'b000, rd_rs1, 7'b0010011};
                    3'b001: // C.JAL
                        ext_inst = {j_imm[20], j_imm[10:1], j_imm[11], j_imm[19:12], 5'b00001, 7'b1101111};
                    3'b010: // C.LI 
                        ext_inst = {{6{c_inst[12]}}, c_inst[12], c_inst[6:2], 5'b00000, 3'b000, rd_rs1, 7'b0010011};
                    3'b011: begin // C.LUI / C.ADDI16SP 
                        if (rd_rs1 == 5'b00010) // C.ADDI16SP (sp = x2)
                            ext_inst = {addi16sp_imm, 5'b00010, 3'b000, 5'b00010, 7'b0010011};
                        else if (rd_rs1 != 0)   // C.LUI
                            ext_inst = {{15{c_inst[12]}}, c_inst[6:2], rd_rs1, 7'b0110111};
                    end
                    3'b101: // C.J
                        ext_inst = {j_imm[20], j_imm[10:1], j_imm[11], j_imm[19:12], 5'b00000, 7'b1101111};
                    3'b110: // C.BEQZ
                        ext_inst = {b_imm[12], b_imm[10:5], 5'b00000, rvc_rs1_s, 3'b000, b_imm[4:1], b_imm[11], 7'b1100011};
                    3'b111: // C.BNEZ
                        ext_inst = {b_imm[12], b_imm[10:5], 5'b00000, rvc_rs1_s, 3'b001, b_imm[4:1], b_imm[11], 7'b1100011};
                    3'b100: begin
                        case(c_inst[11:10])
                            2'b00: // C.SRLI 
                                ext_inst = {7'b0000000, c_inst[6:2], rvc_rs1_s, 3'b101, rvc_rs1_s, 7'b0010011};
                            2'b01: // C.SRAI 
                                ext_inst = {7'b0100000, c_inst[6:2], rvc_rs1_s, 3'b101, rvc_rs1_s, 7'b0010011};
                            2'b10: // C.ANDI
                                ext_inst = {{6{c_inst[12]}}, c_inst[12], c_inst[6:2], rvc_rs1_s, 3'b111, rvc_rs1_s, 7'b0010011};
                            2'b11: begin // C.SUB, C.XOR, C.OR, C.AND 
                                case(c_inst[6:5])
                                    2'b00: // C.SUB
                                        ext_inst = {7'b0100000, rvc_rs2_s, rvc_rs1_s, 3'b000, rvc_rs1_s, 7'b0110011};
                                    2'b01: // C.XOR 
                                        ext_inst = {7'b0000000, rvc_rs2_s, rvc_rs1_s, 3'b100, rvc_rs1_s, 7'b0110011};
                                    2'b10: // C.OR
                                        ext_inst = {7'b0000000, rvc_rs2_s, rvc_rs1_s, 3'b110, rvc_rs1_s, 7'b0110011};
                                    2'b11: // C.AND
                                        ext_inst = {7'b0000000, rvc_rs2_s, rvc_rs1_s, 3'b111, rvc_rs1_s, 7'b0110011};
                                endcase
                            end
                        endcase
                    end
                    default: ext_inst = 32'h00000013;
                endcase
            end

            // ==========================================
            // Quadrant 10 
            // ==========================================
            2'b10: begin
                case(funct3)
                    3'b000: // C.SLLI 
                        ext_inst = {7'b0000000, c_inst[6:2], rd_rs1, 3'b001, rd_rs1, 7'b0010011};
                    3'b010: // C.LWSP
                        ext_inst = {lwsp_imm, 5'b00010, 3'b010, rd_rs1, 7'b0000011};
                    3'b110: // C.SWSP
                        ext_inst = {swsp_imm[11:5], rs2, 5'b00010, 3'b010, swsp_imm[4:0], 7'b0100011};
                    3'b100: begin
                        if (c_inst[12] == 1'b0 && rs2 == 5'b00000 && rd_rs1 != 0)
                            // C.JR
                            ext_inst = {12'b0, rd_rs1, 3'b000, 5'b00000, 7'b1100111};
                        else if (c_inst[12] == 1'b1 && rs2 == 5'b00000 && rd_rs1 != 0)
                            // C.JALR
                            ext_inst = {12'b0, rd_rs1, 3'b000, 5'b00001, 7'b1100111};
                        else if (c_inst[12] == 1'b0 && rs2 != 5'b00000 && rd_rs1 != 0)
                            // C.MV
                            ext_inst = {7'b0000000, rs2, 5'b00000, 3'b000, rd_rs1, 7'b0110011};
                        else if (c_inst[12] == 1'b1 && rs2 != 5'b00000 && rd_rs1 != 0)
                            // C.ADD
                            ext_inst = {7'b0000000, rs2, rd_rs1, 3'b000, rd_rs1, 7'b0110011};
                        else
                            ext_inst = 32'h00000013;
                    end
                    default: ext_inst = 32'h00000013;
                endcase
            end
            default: ext_inst = 32'h00000013;
        endcase
    end
endmodule