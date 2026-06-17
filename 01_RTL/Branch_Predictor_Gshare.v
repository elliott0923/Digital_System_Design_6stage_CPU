module Branch_Predictor #(
    parameter INDEX_BITS = 4,   // 16 entries
    parameter HISTORY_BITS = 11  // 4-bit global history
)(
    input clk,
    input rst_n,
    
    // Prediction interface (IDC stage)
    input  [31:0] pc_idc,
    output        predict_taken,
    
    // Update interface (EX stage)
    input         update_en,      // High if EX stage has a branch
    input  [31:0] pc_ex,          // PC of the branch in EX stage
    input         actual_taken    // Actual outcome from EX stage
);

    reg [1:0] bht [(1<<(INDEX_BITS + HISTORY_BITS))-1:0];
    reg [HISTORY_BITS-1:0] global_history;
    integer i;
    
    // Index = XOR of PC bits and global history
    wire [INDEX_BITS + HISTORY_BITS - 1:0] read_idx  = {pc_idc[INDEX_BITS : 1] ^ global_history, global_history};
    wire [INDEX_BITS + HISTORY_BITS - 1:0] write_idx = {pc_ex[INDEX_BITS : 1] ^ global_history, global_history};
    
    // Predict Taken if counter is 10 or 11 (2 or 3)
    assign predict_taken = bht[read_idx][1]; 

    always @(posedge clk) begin
        if (!rst_n) begin
            for (i=0; i < (1<<(INDEX_BITS + HISTORY_BITS)); i=i+1)
                bht[i] <= 2'b01; // Initialize to weakly not taken
            global_history <= {HISTORY_BITS{1'b0}};
        end else if (update_en) begin
            // Update BHT entry
            case (bht[write_idx])
                2'b00: bht[write_idx] <= actual_taken ? 2'b01 : 2'b00;
                2'b01: bht[write_idx] <= actual_taken ? 2'b10 : 2'b00;
                2'b10: bht[write_idx] <= actual_taken ? 2'b11 : 2'b01;
                2'b11: bht[write_idx] <= actual_taken ? 2'b11 : 2'b10;
            endcase
            
            // Shift in new outcome into global history
            // Shift left and insert actual_taken at bit 0
            global_history <= {global_history[HISTORY_BITS-2:0], actual_taken};
        end
    end

endmodule
