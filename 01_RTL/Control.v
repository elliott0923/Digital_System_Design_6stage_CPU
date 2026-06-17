module Control (
    input  [31:0] instruction,
    input         Hazard_Stall_ID, // Meaning passing NOP to the next stage

    // For EX stage
    output reg [4:0] ctrl_AluOp,
    output reg       ctrl_is_branch,
    output reg       ctrl_is_jalr,
    output reg       ctrl_ALUSrc_A,  // 0: data1, 1: PC + 4
    output reg       ctrl_ALUSrc_B,  // 0: data2, 1: imm

    // For MEM stage
    output reg       ctrl_MemRead,
    output reg       ctrl_MemWrite,
    output reg       ctrl_FLUSH,

    // For WB stage
    output reg       ctrl_RegWrite,
    output reg       ctrl_MemToReg,

    output reg       ctrl_is_Mul     // 1: this instruction is MUL, need to use mul unit result
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

// ========================================
// instruction fields
// ========================================
wire [6:0] opcode;
wire [2:0] funct3;
wire [6:0] funct7;

assign opcode = instruction[6:0];
assign funct3 = instruction[14:12];
assign funct7 = instruction[31:25];

// ========================================
// combinational control logic
// ========================================


// Last Cache Flush identification
always @(*) begin
    if(instruction == INST_FLUSH_param)
        ctrl_FLUSH = 1'b1;
    else
        ctrl_FLUSH = 1'b0;
end


always @(*) begin
    // Default control signals
    // For IF stage

    // For EX stage
    ctrl_AluOp    = OP_NOP;
    ctrl_ALUSrc_A = 1'b0;   // 0: data1, 1: PC + 4
    ctrl_ALUSrc_B = 1'b0;   // 0: data2, 1: imm
    ctrl_is_branch = 1'b0;
    ctrl_is_jalr = 1'b0;

    // For MEM stage
    ctrl_MemRead  = 1'b0;
    ctrl_MemWrite = 1'b0;

    // For WB stage
    ctrl_RegWrite = 1'b0;
    ctrl_MemToReg = 1'b0;   // 0: ALU_result, 1: MemRead_result
    ctrl_is_Mul   = 1'b0;   // 0: not MUL, 1: MUL instruction


    if(Hazard_Stall_ID) begin
        // For EX stage, set control signals to do nothing
        ctrl_AluOp    = OP_NOP;
        ctrl_ALUSrc_A = 1'b0;
        ctrl_ALUSrc_B = 1'b0;
        ctrl_is_branch = 1'b0;
        ctrl_is_jalr = 1'b0;

        // For MEM stage, no memory operation
        ctrl_MemRead  = 1'b0;
        ctrl_MemWrite = 1'b0;

        // For WB stage, no register write
        ctrl_RegWrite = 1'b0;
        ctrl_MemToReg = 1'b0;
        ctrl_is_Mul   = 1'b0;

    end else begin
        // No load-use hazard, normal control logic based on opcode and funct fields
    case (opcode[6:2])
        // =================================
        // R-type
        // ADD, SUB, AND, OR, XOR, SLT, MUL
        // =================================
        5'b01100: begin
            ctrl_RegWrite = 1'b1;

            case (funct3)

                3'b000: begin
                    if (funct7 == 7'b0100000)
                        ctrl_AluOp = OP_SUB;
                    else if (funct7 == 7'b0000001)begin
                        ctrl_AluOp = OP_NOP; // MUL instruction
                        ctrl_is_Mul   = 1'b1;
                    end
                    else
                        ctrl_AluOp = OP_ADD;
                end

                3'b111: ctrl_AluOp = OP_AND;
                3'b110: ctrl_AluOp = OP_OR;
                3'b100: ctrl_AluOp = OP_XOR;
                3'b010: ctrl_AluOp = OP_SLT;

                default: ctrl_AluOp = OP_NOP;

            endcase
        end

        // =================================
        // I-type ALU
        // ADDI, ANDI, ORI, XORI
        // SLLI, SRLI, SRAI, SLTI
        // =================================
        5'b00100: begin
            ctrl_RegWrite = 1'b1;
            ctrl_ALUSrc_B = 1'b1; // Need to feed immediate

            case (funct3)

                3'b000: ctrl_AluOp = OP_ADD; // ADDI
                3'b111: ctrl_AluOp = OP_AND; // ANDI
                3'b110: ctrl_AluOp = OP_OR;  // ORI
                3'b100: ctrl_AluOp = OP_XOR; // XORI
                3'b010: ctrl_AluOp = OP_SLT; // SLTI
                3'b001: ctrl_AluOp = OP_SLL; // SLLI

                3'b101: begin
                    if (funct7 == 7'b0100000)
                        ctrl_AluOp = OP_SRA; // SRAI
                    else
                        ctrl_AluOp = OP_SRL; // SRLI
                end

                default: ctrl_AluOp = OP_NOP;
            endcase
        end

        // =================================
        // LOAD
        // LW
        // =================================
        5'b00000: begin
            ctrl_AluOp    = OP_ADD;
            ctrl_ALUSrc_B = 1'b1;
            ctrl_MemRead  = 1'b1;
            ctrl_RegWrite = 1'b1;
            ctrl_MemToReg = 1'b1;
        end

        // =================================
        // STORE
        // SW
        // =================================
        5'b01000: begin
            ctrl_AluOp     = OP_ADD;
            ctrl_ALUSrc_B  = 1'b1;
            ctrl_MemWrite  = 1'b1;
        end

        // =================================
        // BRANCH
        // BEQ, BNE
        // =================================
        5'b11000: begin
            case (funct3)
                3'b000: begin // BEQ
                    ctrl_AluOp = OP_BEQ;
                    ctrl_is_branch = 1'b1;
                end
                3'b001: begin // BNE
                    ctrl_AluOp = OP_BNE;
                    ctrl_is_branch = 1'b1;
                end
            endcase
        end

        // =================================
        // JAL
        // =================================
        5'b11011: begin
            ctrl_AluOp    = OP_JAL;  // To let "PC + 4" pass the ALU
            ctrl_ALUSrc_A = 1'b1;    // To let "PC + 4" pass the ALU
            ctrl_RegWrite = 1'b1;
        end

        // =================================
        // JALR
        // =================================
        5'b11001: begin
            ctrl_AluOp    = OP_JALR;
            ctrl_ALUSrc_A = 1'b1;    // To let "PC + 4" pass the ALU
            ctrl_is_jalr = 1'b1;
            ctrl_RegWrite = 1'b1;
        end

    endcase

    // OPTIMIZATION: Early Zero-Masking
    // If the destination register is x0, forcefully turn off RegWrite.
    if (instruction[11:7] == 5'b00000) begin
        ctrl_RegWrite = 1'b0;
    end

    end
end

endmodule