module ALU (
    input  [4:0]  alu_op,
    input  [31:0] src_a,
    input  [31:0] src_b,
    output reg [31:0] alu_result
);

parameter OP_NOP  = 4'b0000;
parameter OP_ADD  = 4'b0001;
parameter OP_SUB  = 4'b0010;
parameter OP_AND  = 4'b0011;
parameter OP_OR   = 4'b0100;
parameter OP_XOR  = 4'b0101;
parameter OP_SLT  = 4'b0110;
parameter OP_SLL  = 4'b0111;
parameter OP_SRL  = 4'b1000;
parameter OP_SRA  = 4'b1001;
parameter OP_BEQ  = 4'b1010;
parameter OP_BNE  = 4'b1011;
parameter OP_JAL  = 4'b1110;
parameter OP_JALR = 4'b1111;

always @(*) begin
    case (alu_op[3:0]) // synpnosys parallel_case

        OP_NOP: begin
            alu_result = 32'b0;
        end

        OP_ADD: begin
            alu_result = src_a + src_b;
        end

        OP_SUB: begin
            alu_result = src_a - src_b;
        end

        OP_AND: begin
            alu_result = src_a & src_b;
        end

        OP_OR: begin
            alu_result = src_a | src_b;
        end

        OP_XOR: begin
            alu_result = src_a ^ src_b;
        end

        OP_SLT: begin
            alu_result = ($signed(src_a) < $signed(src_b)) ? 32'd1 : 32'd0;
        end

        OP_SLL: begin
            alu_result = src_a << src_b[4:0];
        end

        OP_SRL: begin
            alu_result = src_a >> src_b[4:0];
        end

        OP_SRA: begin
            alu_result = $signed(src_a) >>> src_b[4:0];
        end

        OP_BEQ: begin
            alu_result = (src_a == src_b) ? 32'd1 : 32'd0;
        end

        OP_BNE: begin
            alu_result = (src_a != src_b) ? 32'd1 : 32'd0;
        end

        OP_JAL: begin
            alu_result = src_a; // send PC+4 to Regfile
        end

        OP_JALR: begin
            alu_result = src_a; // send PC+4 to Regfile
        end

        default: begin
            alu_result = 32'b0;
        end

    endcase
end

endmodule
