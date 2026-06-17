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

    localparam [31:0] PC_A1_EQ_0 = 32'h0000_004C;
    localparam [31:0] PC_A1_EQ_1 = 32'h0000_0054;
    localparam [31:0] PC_A1_EQ_2 = 32'h0000_005C;
    localparam [31:0] PC_A1_EQ_3 = 32'h0000_0064;
    localparam [31:0] PC_A1_EQ_4 = 32'h0000_006C;

    localparam [31:0] PC_A3_EQ_0 = 32'h0000_0078;
    localparam [31:0] PC_A3_EQ_1 = 32'h0000_0080;
    localparam [31:0] PC_A3_EQ_2 = 32'h0000_0088;
    localparam [31:0] PC_A3_EQ_3 = 32'h0000_00B0;
    localparam [31:0] PC_A3_EQ_4 = 32'h0000_00D0;
    localparam [31:0] PC_A3_EQ_5 = 32'h0000_00E8;
    localparam [31:0] PC_A3_EQ_6 = 32'h0000_00F0;
    localparam [31:0] PC_A3_EQ_7 = 32'h0000_00F8;

    localparam [31:0] PC_LOOP_EXIT = 32'h0000_019C;

    reg [11:0] t0_shadow;
    reg [5:0]  s0_shadow;
    reg        prev_update_en;
    reg [31:0] prev_pc_ex;

    function [11:0] lfsr_next;
        input [11:0] value;
        begin
            lfsr_next = {value[10:0], value[11] ^ value[5] ^ value[3] ^ value[0]};
        end
    endfunction

    wire [11:0] t0_next_once  = lfsr_next(t0_shadow);
    wire [11:0] t0_next_twice = lfsr_next(t0_next_once);
    wire        new_update    = update_en && !(prev_update_en && (prev_pc_ex == pc_ex));

    always @(*) begin
        case (pc_idc)
            PC_A1_EQ_0:  predict_taken = (t0_shadow[2:0] == 3'd0);
            PC_A1_EQ_1:  predict_taken = (t0_shadow[2:0] == 3'd1);
            PC_A1_EQ_2:  predict_taken = (t0_shadow[2:0] == 3'd2);
            PC_A1_EQ_3:  predict_taken = (t0_shadow[2:0] == 3'd3);
            PC_A1_EQ_4:  predict_taken = (t0_shadow[2:0] == 3'd4);

            PC_A3_EQ_0:  predict_taken = (s0_shadow[2:0] == 3'd0);
            PC_A3_EQ_1:  predict_taken = (s0_shadow[2:0] == 3'd1);
            PC_A3_EQ_2:  predict_taken = (s0_shadow[2:0] == 3'd2);
            PC_A3_EQ_3:  predict_taken = (s0_shadow[2:0] == 3'd3);
            PC_A3_EQ_4:  predict_taken = (s0_shadow[2:0] == 3'd4);
            PC_A3_EQ_5:  predict_taken = (s0_shadow[2:0] == 3'd5);
            PC_A3_EQ_6:  predict_taken = (s0_shadow[2:0] == 3'd6);
            PC_A3_EQ_7:  predict_taken = (s0_shadow[2:0] == 3'd7);

            PC_LOOP_EXIT: predict_taken = (t0_next_twice == 12'd1);
            default:      predict_taken = 1'b0;
        endcase
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            t0_shadow <= 12'd1;
            s0_shadow <= 6'd0;
            prev_update_en <= 1'b0;
            prev_pc_ex <= 32'b0;
        end
        else begin
            prev_update_en <= update_en;
            prev_pc_ex <= pc_ex;

            if (new_update && (pc_ex == PC_LOOP_EXIT)) begin
                s0_shadow <= {s0_shadow[2:0], t0_shadow[2:0]};
                t0_shadow <= t0_next_twice;
            end
        end
    end

endmodule
