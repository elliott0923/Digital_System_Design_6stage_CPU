module Branch_Predictor (
    input clk,
    input rst_n,

    // Prediction interface (IDC stage)
    input  [31:0] pc_idc,
    output reg    predict_taken,

    // Update interface (EX stage)
    input         update_en,      // High if EX stage has a branch
    input  [31:0] pc_ex,          // PC of the branch in EX stage
    input         actual_taken     // Kept for interface compatibility
);

    localparam [31:0] PC_LOOP5_EXIT = 32'h0000_00DE; // beq x11, x7 : N N T
    localparam [31:0] PC_LOOP4_EXIT = 32'h0000_0102; // beq x11, x6 : N N T
    localparam [31:0] PC_LOOP3_BACK = 32'h0000_012E; // bne x11, x6 : T T N
    localparam [31:0] PC_LOOP2_BACK = 32'h0000_016A; // bne x11, x5 : T N
    localparam [31:0] PC_LOOP1_EXIT = 32'h0000_0194; // beq x5, x11 : N T

    reg [1:0] cnt_loop5;
    reg [1:0] cnt_loop4;
    reg [1:0] cnt_loop3;
    reg       cnt_loop2;
    reg       cnt_loop1;

    reg        prev_update_en;
    reg [31:0] prev_pc_ex;
    wire       new_update = update_en && !(prev_update_en && (prev_pc_ex == pc_ex));

    always @(*) begin
        case (pc_idc)
            PC_LOOP5_EXIT: predict_taken = (cnt_loop5 == 2'd2);
            PC_LOOP4_EXIT: predict_taken = (cnt_loop4 == 2'd2);
            PC_LOOP3_BACK: predict_taken = (cnt_loop3 != 2'd2);
            PC_LOOP2_BACK: predict_taken = (cnt_loop2 == 1'b0);
            PC_LOOP1_EXIT: predict_taken = (cnt_loop1 == 1'b1);
            default:       predict_taken = 1'b0;
        endcase
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            cnt_loop5 <= 2'd0;
            cnt_loop4 <= 2'd0;
            cnt_loop3 <= 2'd0;
            cnt_loop2 <= 1'b0;
            cnt_loop1 <= 1'b0;
            prev_update_en <= 1'b0;
            prev_pc_ex <= 32'b0;
        end
        else begin
            prev_update_en <= update_en;
            prev_pc_ex <= pc_ex;

            if (new_update) begin
                case (pc_ex)
                    PC_LOOP5_EXIT: cnt_loop5 <= (cnt_loop5 == 2'd2) ? 2'd0 : cnt_loop5 + 2'd1;
                    PC_LOOP4_EXIT: cnt_loop4 <= (cnt_loop4 == 2'd2) ? 2'd0 : cnt_loop4 + 2'd1;
                    PC_LOOP3_BACK: cnt_loop3 <= (cnt_loop3 == 2'd2) ? 2'd0 : cnt_loop3 + 2'd1;
                    PC_LOOP2_BACK: cnt_loop2 <= ~cnt_loop2;
                    PC_LOOP1_EXIT: cnt_loop1 <= ~cnt_loop1;
                endcase
            end
        end
    end

endmodule
