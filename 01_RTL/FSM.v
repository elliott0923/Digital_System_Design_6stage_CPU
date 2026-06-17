module Compressed_IF_FSM (
    input         clk,
    input         rst_n,

    // Pipeline control
    input         stall_i,        
    input         flush_i,        
    input         redirect_i,     
    input  [31:0] redirect_pc_i,  
    input  [31:0] icache_rdata_i,
    input         icache_resp_valid_i,
    input         icache_stall_i,

    output        icache_read_o,
    output [29:0] icache_addr_o, // connect to I_cache.proc_addr
    output        icache_resp_ready_o,
    output reg [31:0] inst_o,     
    output reg [31:0] pc_o,       
    output reg        inst_valid_o,
    output reg        is_rvc_o
);

    localparam INST_NOP = 32'h00000013;
    localparam S_REQ        = 2'b00; // issue a word fetch request
    localparam S_WAIT       = 2'b01; // wait for the requested word response
    localparam S_BUF        = 2'b10; // consume buffered high halfword
    localparam S_CROSS_WAIT = 2'b11; // wait for the next word of a cross-boundary RV32I

    reg [1:0]  state_q;
    reg [31:0] pc_q;              // next instruction PC, byte address
    reg [31:0] pending_pc_q;      // PC belonging to the outstanding I-cache request
    reg [31:0] cross_pc_q;        // original PC of a cross-boundary RV32I

    // Buffer holds a halfword that has already been fetched but not consumed.
    reg [15:0] buf_q;
    reg        buf_valid_q;

    // --------------------------------------------------------------------------
    // Halfword selection and compressed detection
    // --------------------------------------------------------------------------
    wire [15:0] low_half  = icache_rdata_i[15:0];
    wire [15:0] high_half = icache_rdata_i[31:16];

    wire [15:0] cur_half_from_word = (pending_pc_q[1] == 1'b0) ? low_half : high_half;

    wire cur_half_is_rvc = (cur_half_from_word[1:0] != 2'b11);
    wire buf_is_rvc      = (buf_q[1:0] != 2'b11);
    wire high_half_is_rvc = (high_half[1:0] != 2'b11);
    wire ready_to_advance = !stall_i && !icache_stall_i;

    // Decompressed versions
    wire [31:0] dec_cur_half;
    wire [31:0] dec_buf_half;

    wire [31:0] pending_pc_plus_2 = pending_pc_q + 32'd2;
    wire [31:0] pending_pc_plus_4 = pending_pc_q + 32'd4;
    wire [31:0] pc_plus_2         = pc_q + 32'd2;

    wire wait_can_use_resp  = (state_q == S_WAIT)       && icache_resp_valid_i && ready_to_advance;
    wire cross_can_use_resp = (state_q == S_CROSS_WAIT) && icache_resp_valid_i && ready_to_advance;
    wire buf_can_advance    = (state_q == S_BUF) && buf_valid_q && ready_to_advance;
    wire redirect_can_req   = redirect_i && !icache_stall_i;
    wire discard_resp       = icache_resp_valid_i &&
                              ((state_q == S_REQ) || flush_i || redirect_i);

    wire wait_low_half      = (pending_pc_q[1] == 1'b0);
    wire wait_high_half     = (pending_pc_q[1] == 1'b1);
    wire wait_cur_is_rvc    = cur_half_is_rvc;
    wire wait_need_next_req = wait_can_use_resp &&
                              ((!wait_low_half && wait_cur_is_rvc) ||
                               ( wait_low_half && !wait_cur_is_rvc) ||
                               ( wait_high_half && !wait_cur_is_rvc) ||
                               ( wait_low_half && wait_cur_is_rvc && !high_half_is_rvc));
    wire buf_need_next_req  = buf_can_advance;
    wire cross_need_next_req = cross_can_use_resp && !high_half_is_rvc;

    wire [31:0] wait_next_req_pc =
        (wait_high_half && !wait_cur_is_rvc) ? pending_pc_plus_2 :
                                               pending_pc_plus_4;
    wire [31:0] cross_next_req_pc = cross_pc_q + 32'd6;

    assign icache_read_o =
        redirect_can_req ||
        ((!stall_i && !icache_stall_i) &&
         (((state_q == S_REQ) && !icache_resp_valid_i) ||
          wait_need_next_req ||
          buf_need_next_req ||
          cross_need_next_req));

    assign icache_addr_o =
        redirect_can_req      ? redirect_pc_i[31:2] :
        (state_q == S_REQ)    ? pc_q[31:2] :
        wait_need_next_req    ? wait_next_req_pc[31:2] :
        cross_need_next_req   ? cross_next_req_pc[31:2] :
        buf_need_next_req     ? pc_plus_2[31:2] :
                                pc_q[31:2];

    assign icache_resp_ready_o =
        wait_can_use_resp || cross_can_use_resp || discard_resp;

    // --------------------------------------------------------------------------
    // Main sequential FSM
    // --------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            state_q      <= S_REQ;
            pc_q         <= 32'b0;
            pending_pc_q <= 32'b0;
            cross_pc_q   <= 32'b0;
            buf_q        <= 16'b0;
            buf_valid_q  <= 1'b0;

            inst_o       <= INST_NOP;
            pc_o         <= 32'b0;
            inst_valid_o <= 1'b0;
            is_rvc_o     <= 1'b0;
        end
        else begin
            // Default: no new instruction emitted this cycle.
            inst_valid_o <= 1'b0;

            // Branch/jump/flush must kill the old halfword buffer.
            if (flush_i || redirect_i) begin
                state_q      <= redirect_can_req ? S_WAIT : S_REQ;
                pc_q         <= redirect_i ? redirect_pc_i : pc_q;
                pending_pc_q <= redirect_can_req ? redirect_pc_i : 32'b0;
                cross_pc_q   <= 32'b0;
                buf_q       <= 16'b0;
                buf_valid_q <= 1'b0;

                inst_o       <= INST_NOP;
                inst_valid_o <= 1'b0;
                is_rvc_o     <= 1'b0;
            end
            else if (stall_i) begin
                // Hold everything when downstream pipeline cannot accept a new inst.
                state_q     <= state_q;
                pc_q        <= pc_q;
                buf_q       <= buf_q;
                buf_valid_q <= buf_valid_q;

                inst_o       <= inst_o;
                pc_o         <= pc_o;
                inst_valid_o <= inst_valid_o;
                is_rvc_o     <= is_rvc_o;
            end
            else begin
                case (state_q)
                    // ----------------------------------------------------------
                    // Issue a 32-bit word request to I-cache.
                    // ----------------------------------------------------------
                    S_REQ: begin
                        if (!icache_stall_i && !icache_resp_valid_i) begin
                            pending_pc_q <= pc_q;
                            state_q      <= S_WAIT;
                        end
                    end

                    // ----------------------------------------------------------
                    // Consume the requested word.  When the next instruction is
                    // in a different word, issue that request in this same cycle.
                    // ----------------------------------------------------------
                    S_WAIT: begin
                        if (icache_resp_valid_i) begin
                            if (pending_pc_q[1] == 1'b0) begin
                                // PC points to low halfword: icache_rdata_i[15:0].
                                if (cur_half_is_rvc) begin
                                    // RVC at low halfword.
                                    inst_o       <= {16'b0 ,cur_half_from_word};
                                    pc_o         <= pending_pc_q;  // record the pc address of this instruction
                                    inst_valid_o <= 1'b1;
                                    is_rvc_o     <= 1'b1;

                                    buf_q        <= high_half;
                                    buf_valid_q  <= 1'b1;
                                    if (high_half_is_rvc) begin
                                        pc_q    <= pending_pc_plus_2;
                                        state_q <= S_BUF;
                                    end
                                    else begin
                                        cross_pc_q   <= pending_pc_plus_2;
                                        pending_pc_q <= pending_pc_plus_4;
                                        state_q      <= S_CROSS_WAIT;
                                    end
                                end
                                else begin
                                    // Normal aligned RV32I.
                                    inst_o       <= icache_rdata_i;
                                    pc_o         <= pending_pc_q;
                                    inst_valid_o <= 1'b1;
                                    is_rvc_o     <= 1'b0;

                                    buf_valid_q  <= 1'b0;
                                    pc_q         <= pending_pc_plus_4;
                                    pending_pc_q <= pending_pc_plus_4;
                                    state_q      <= S_WAIT;
                                end
                            end
                            else begin
                                // PC points to high halfword: icache_rdata_i[31:16].
                                if (cur_half_is_rvc) begin
                                    // RVC at high halfword.
                                    inst_o       <= {16'b0 ,cur_half_from_word};
                                    pc_o         <= pending_pc_q;
                                    inst_valid_o <= 1'b1;
                                    is_rvc_o     <= 1'b1;

                                    buf_valid_q  <= 1'b0;
                                    pc_q         <= pending_pc_plus_2; // now reaches next word boundary
                                    pending_pc_q <= pending_pc_plus_2;
                                    state_q      <= S_WAIT;
                                end
                                else begin
                                    // RV32I starts at high halfword and crosses boundary.
                                    // Save low 16 bits of the RV32I, then fetch next word.
                                    buf_q        <= high_half;
                                    buf_valid_q  <= 1'b1;
                                    cross_pc_q   <= pending_pc_q;
                                    pending_pc_q <= pending_pc_plus_2;
                                    state_q      <= S_CROSS_WAIT;
                                end
                            end
                        end
                    end

                    // ----------------------------------------------------------
                    // Consume buffered halfword.
                    // ----------------------------------------------------------
                    S_BUF: begin
                        if (buf_valid_q) begin
                            if (buf_is_rvc) begin
                                inst_o       <= {16'b0, buf_q};
                                pc_o         <= pc_q;
                                inst_valid_o <= 1'b1;
                                is_rvc_o     <= 1'b1;

                                buf_valid_q  <= 1'b0;
                                pc_q         <= pc_plus_2;
                                pending_pc_q <= pc_plus_2;
                                state_q      <= S_WAIT;
                            end
                            else begin
                                // Buffered halfword is the first half of RV32I.
                                // Need next 32-bit word to get the upper 16 bits.
                                cross_pc_q   <= pc_q;
                                pending_pc_q <= pc_plus_2;
                                state_q      <= S_CROSS_WAIT;
                            end
                        end
                        else begin
                            state_q <= S_REQ;
                        end
                    end

                    // ----------------------------------------------------------
                    // Complete a cross-boundary RV32I:
                    //   instruction = {next_word[15:0], previous_high_halfword}
                    //
                    // Example:
                    //   PC = 14
                    //   low 16 bits  = memory[14:15] = buf_q
                    //   high 16 bits = memory[16:17] = icache_rdata_i[15:0]
                    // ----------------------------------------------------------
                    S_CROSS_WAIT: begin
                        if (icache_resp_valid_i) begin
                            inst_o       <= {low_half, buf_q};
                            pc_o         <= cross_pc_q;
                            inst_valid_o <= 1'b1;
                            is_rvc_o     <= 1'b0;

                            // After consuming low_half, the high_half of this word
                            // may be the next instruction at PC + 4.
                            buf_q        <= high_half;
                            buf_valid_q  <= 1'b1;
                            if (high_half_is_rvc) begin
                                pc_q    <= cross_pc_q + 32'd4;
                                state_q <= S_BUF;
                            end
                            else begin
                                // High half starts another cross-boundary RV32I.
                                cross_pc_q   <= cross_pc_q + 32'd4;
                                pending_pc_q <= cross_pc_q + 32'd6;
                                state_q      <= S_CROSS_WAIT;
                            end
                        end
                    end

                    default: begin
                        state_q     <= S_REQ;
                        buf_valid_q <= 1'b0;
                    end
                endcase
            end
        end
    end

endmodule
