module D_cache #(
    parameter SETS = 8,
    parameter WAYS = 8
)(
    input          clk,
    // processor interface
    input          proc_reset,
    input          proc_read, proc_write,
    input   [29:0] proc_addr,
    input   [31:0] proc_wdata,
    output         proc_stall,
    output  [31:0] proc_rdata,
    // memory interface
    input  [127:0] mem_rdata,
    input          mem_ready,
    output         mem_read, mem_write,
    output  [27:0] mem_addr,
    output [127:0] mem_wdata,
    // new flush interface
    input          proc_flush,
    output         proc_o_done
);
    
//==== parameter & math definitions =======================
    localparam INDEX_BITS = $clog2(SETS);
    localparam WAY_BITS   = (WAYS > 1) ? $clog2(WAYS) : 1;
    localparam TAG_BITS   = 30 - 2 - INDEX_BITS;
    localparam TOTAL_BLKS = SETS * WAYS;
    localparam FLUSH_BITS = ($clog2(TOTAL_BLKS) > 0) ? $clog2(TOTAL_BLKS) : 1;

//==== wire/reg definition ================================
    // Address Parsing 
    wire [1:0]            offset    = proc_addr[1:0];
    wire [INDEX_BITS-1:0] idx       = proc_addr >> 2; 
    wire [TAG_BITS-1:0]   tag_field = proc_addr >> (2 + INDEX_BITS);

    // Cache Storage (2D Arrays: [Way][Set])
    reg [127:0]        cache_data  [0:WAYS-1][0:SETS-1];
    reg [TAG_BITS-1:0] cache_tag   [0:WAYS-1][0:SETS-1];
    reg                cache_valid [0:WAYS-1][0:SETS-1];
    reg                cache_dirty [0:WAYS-1][0:SETS-1];
    
    // 8-way tree pseudo-LRU tracker. Each set uses 7 direction bits.
    // A bit points toward the next victim subtree; touching a way flips the
    // bits along that way's path to point away from it.
    reg [6:0]          cache_plru  [0:SETS-1];

    // Flush Sweep Logic
    reg [FLUSH_BITS-1:0] flush_cnt;
    wire [INDEX_BITS-1:0] flush_idx   = flush_cnt / WAYS;
    wire [WAY_BITS-1:0]   flush_way   = flush_cnt % WAYS;
    wire                  flush_dirty = cache_dirty[flush_way][flush_idx];

    // FSM States
    parameter S_IDLE        = 3'd0;
    parameter S_WRITE_BACK  = 3'd1;
    parameter S_ALLOCATE    = 3'd2;
    parameter S_FLUSH_SWEEP = 3'd3;
    parameter S_FLUSH_WRITE = 3'd4;
    parameter S_DONE        = 3'd5;
    
    reg [2:0] state, next_state;

    // Eviction Pipeline Registers
    reg [127:0] evicted_data_reg;
    reg [27:0]  evicted_addr_reg;

//==== combinational circuit ==============================
    // Hit Detection
    reg hit;
    reg [WAY_BITS-1:0] hit_way;
    integer i_hit;
    
    always @(*) begin
        hit = 1'b0;
        hit_way = 0;
        for (i_hit = 0; i_hit < WAYS; i_hit = i_hit + 1) begin
            if (cache_valid[i_hit][idx] && (cache_tag[i_hit][idx] == tag_field)) begin
                hit = 1'b1;
                hit_way = i_hit[WAY_BITS-1:0];
            end
        end
    end

    wire miss = (proc_read || proc_write) && !hit;

    // Eviction target selection
    reg [WAY_BITS-1:0] replace_way;
    reg replace_dirty;
    integer i_rep;

    function [2:0] plru_victim;
        input [6:0] bits;
        begin
            if (bits[0] == 1'b0) begin
                if (bits[1] == 1'b0) begin
                    plru_victim = (bits[3] == 1'b0) ? 3'd0 : 3'd1;
                end else begin
                    plru_victim = (bits[4] == 1'b0) ? 3'd2 : 3'd3;
                end
            end else begin
                if (bits[2] == 1'b0) begin
                    plru_victim = (bits[5] == 1'b0) ? 3'd4 : 3'd5;
                end else begin
                    plru_victim = (bits[6] == 1'b0) ? 3'd6 : 3'd7;
                end
            end
        end
    endfunction

    function [6:0] plru_touch;
        input [6:0] bits;
        input [2:0] way;
        begin
            plru_touch = bits;
            case (way)
                3'd0: begin plru_touch[0] = 1'b1; plru_touch[1] = 1'b1; plru_touch[3] = 1'b1; end
                3'd1: begin plru_touch[0] = 1'b1; plru_touch[1] = 1'b1; plru_touch[3] = 1'b0; end
                3'd2: begin plru_touch[0] = 1'b1; plru_touch[1] = 1'b0; plru_touch[4] = 1'b1; end
                3'd3: begin plru_touch[0] = 1'b1; plru_touch[1] = 1'b0; plru_touch[4] = 1'b0; end
                3'd4: begin plru_touch[0] = 1'b0; plru_touch[2] = 1'b1; plru_touch[5] = 1'b1; end
                3'd5: begin plru_touch[0] = 1'b0; plru_touch[2] = 1'b1; plru_touch[5] = 1'b0; end
                3'd6: begin plru_touch[0] = 1'b0; plru_touch[2] = 1'b0; plru_touch[6] = 1'b1; end
                3'd7: begin plru_touch[0] = 1'b0; plru_touch[2] = 1'b0; plru_touch[6] = 1'b0; end
            endcase
        end
    endfunction

    always @(*) begin
        replace_way = plru_victim(cache_plru[idx]);
        // Override if an invalid way exists.
        for (i_rep = WAYS - 1; i_rep >= 0; i_rep = i_rep - 1) begin
            if (!cache_valid[i_rep][idx]) begin
                replace_way = i_rep[WAY_BITS-1:0];
            end
        end
        replace_dirty = cache_dirty[replace_way][idx];
    end

    // Processor Outputs
    assign proc_stall  = miss || (state != S_IDLE && state != S_DONE);
    assign proc_o_done = (state == S_DONE);
    
    wire [127:0] hit_data = cache_data[hit_way][idx];
    assign proc_rdata = (offset == 2'b00) ? hit_data[31:0]   :
                        (offset == 2'b01) ? hit_data[63:32]  :
                        (offset == 2'b10) ? hit_data[95:64]  :
                                            hit_data[127:96] ;

    // Memory Outputs
    assign mem_read  = (state == S_ALLOCATE);
    assign mem_write = (state == S_WRITE_BACK) || (state == S_FLUSH_WRITE);
    
    wire [127:0] current_wb_data = cache_data[replace_way][idx];
    wire [TAG_BITS-1:0] current_wb_tag = cache_tag[replace_way][idx];

    wire [127:0] current_flush_data = cache_data[flush_way][flush_idx];
    wire [TAG_BITS-1:0] current_flush_tag = cache_tag[flush_way][flush_idx];
    
    assign mem_wdata = evicted_data_reg;
    assign mem_addr  = (state == S_WRITE_BACK || state == S_FLUSH_WRITE) ? 
                       evicted_addr_reg : proc_addr[29:2];


    // FSM Next State Logic
    always @(*) begin
        case(state)
            S_IDLE: begin
                if (proc_flush) begin
                    next_state = S_FLUSH_SWEEP;
                end else if (miss) begin
                    if (replace_dirty) next_state = S_WRITE_BACK;
                    else next_state = S_ALLOCATE;
                end else begin
                    next_state = S_IDLE;
                end
            end
            S_WRITE_BACK: begin
                if (mem_ready) next_state = S_ALLOCATE;
                else next_state = S_WRITE_BACK;
            end
            S_ALLOCATE: begin
                if (mem_ready) next_state = S_IDLE;
                else next_state = S_ALLOCATE;
            end
            S_FLUSH_SWEEP: begin
                if (flush_dirty) next_state = S_FLUSH_WRITE;
                else if (flush_cnt == (TOTAL_BLKS - 1)) next_state = S_DONE;
                else next_state = S_FLUSH_SWEEP;
            end
            S_FLUSH_WRITE: begin
                if (mem_ready) begin
                    if (flush_cnt == (TOTAL_BLKS - 1)) next_state = S_DONE;
                    else next_state = S_FLUSH_SWEEP;
                end else begin
                    next_state = S_FLUSH_WRITE;
                end
            end
            S_DONE: next_state = S_DONE; 
            default: next_state = S_IDLE;
        endcase
    end

//==== sequential circuit =================================
    integer i_rst, w_rst;

    always@(posedge clk) begin
        if(proc_reset) begin
            state <= S_IDLE;
            flush_cnt <= 0;
            evicted_data_reg <= 128'b0;
            evicted_addr_reg <= 28'b0;
            
            for (i_rst = 0; i_rst < SETS; i_rst = i_rst + 1) begin
                cache_plru[i_rst] <= 7'b0;
                for (w_rst = 0; w_rst < WAYS; w_rst = w_rst + 1) begin
                    cache_valid[w_rst][i_rst] <= 1'b0;
                    cache_dirty[w_rst][i_rst] <= 1'b0;
                end
            end
        end
        else begin
            state <= next_state;

            // --- Latch Eviction Data ---
            if (state == S_IDLE) begin
                evicted_data_reg <= current_wb_data;
                evicted_addr_reg <= {current_wb_tag, idx};
            end else if (state == S_FLUSH_SWEEP) begin
                evicted_data_reg <= current_flush_data;
                evicted_addr_reg <= {current_flush_tag, flush_idx};
            end

            // --- Flush Counter Logic ---
            if (state == S_FLUSH_SWEEP && !flush_dirty && flush_cnt != (TOTAL_BLKS - 1)) begin
                flush_cnt <= flush_cnt + 1;
            end
            else if (state == S_FLUSH_WRITE && mem_ready) begin
                cache_dirty[flush_way][flush_idx] <= 1'b0;
                if (flush_cnt != (TOTAL_BLKS - 1)) flush_cnt <= flush_cnt + 1;
            end

            // --- PLRU Tracker Update (Hit) ---
            if (state == S_IDLE && hit && (proc_read || proc_write) && !proc_flush) begin
                cache_plru[idx] <= plru_touch(cache_plru[idx], hit_way);
            end

            // --- Standard Miss Allocation ---
            if (state == S_ALLOCATE && mem_ready) begin
                cache_valid[replace_way][idx] <= 1'b1;
                cache_dirty[replace_way][idx] <= 1'b0;
                cache_tag[replace_way][idx]   <= tag_field;
                cache_data[replace_way][idx]  <= mem_rdata;
                
                cache_plru[idx] <= plru_touch(cache_plru[idx], replace_way);
            end
            
            // --- Processor Write Handler ---
            else if (state == S_IDLE && proc_write && hit && !proc_flush) begin
                cache_dirty[hit_way][idx] <= 1'b1;
                case (offset)
                    2'b00: cache_data[hit_way][idx][31:0]   <= proc_wdata;
                    2'b01: cache_data[hit_way][idx][63:32]  <= proc_wdata;
                    2'b10: cache_data[hit_way][idx][95:64]  <= proc_wdata;
                    2'b11: cache_data[hit_way][idx][127:96] <= proc_wdata;
                endcase
            end
        end
    end

endmodule
