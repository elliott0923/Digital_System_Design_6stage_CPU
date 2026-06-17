module I_cache(
    clk,
    proc_reset,
    proc_read,
    proc_write, // Unused
    proc_addr,
    proc_rdata,
    proc_resp_valid,
    proc_resp_ready,
    proc_wdata, // Unused
    proc_stall,
    mem_read,
    mem_write,  // Will be hardwired to 0
    mem_addr,
    mem_rdata,
    mem_wdata,  // Will be hardwired to 0
    mem_ready
);
    input          clk;
    input          proc_reset;
    input          proc_read, proc_write;
    input   [29:0] proc_addr;
    input   [31:0] proc_wdata;
    output         proc_stall;
    output  [31:0] proc_rdata;
    output         proc_resp_valid;
    input          proc_resp_ready;
    input  [127:0] mem_rdata;
    input          mem_ready;
    output         mem_read, mem_write;
    output  [27:0] mem_addr;
    output [127:0] mem_wdata;

    // Cache Storage (Read-Only)
    reg [127:0] cache_data [0:31];
    reg [22:0]  cache_tag  [0:31];
    reg         cache_valid[0:31];

    // FSM (Simplified: No Write-Back)
    parameter S_IDLE     = 1'b0;
    parameter S_ALLOCATE = 1'b1;
    reg state;

    // One outstanding fetch request.  The address is registered so the
    // critical path starts inside I_cache instead of at the IF-stage PC.
    reg        req_valid_q;
    reg [29:0] req_addr_q;

    // Address Parsing (32 sets = 5 bit index)
    wire [22:0] req_tag_field = req_addr_q[29:7];
    wire [4:0]  req_idx       = req_addr_q[6:2];
    wire [1:0]  req_offset    = req_addr_q[1:0];

    // Miss address is latched before going to slow memory.  This removes the
    // direct IF PC -> mem_addr_I output path.
    reg [27:0] miss_addr_q;
    reg [4:0]  miss_idx_q;
    reg [22:0] miss_tag_q;

    // Hit Logic
    wire req_hit  = req_valid_q && cache_valid[req_idx] && (cache_tag[req_idx] == req_tag_field);
    wire req_miss = req_valid_q && !req_hit;
    wire accept_request = proc_read && (state == S_IDLE) &&
                          (!req_valid_q || (req_hit && proc_resp_ready));

    // Outputs
    assign proc_stall      = (state == S_ALLOCATE) || ((state == S_IDLE) && req_miss);
    assign proc_resp_valid = (state == S_IDLE) && req_hit;
    assign mem_read    = (state == S_ALLOCATE);
    assign mem_write   = 1'b0; // Explicitly no write
    assign mem_wdata   = 128'b0;
    assign mem_addr    = miss_addr_q;

    // Read Data Path
    wire [127:0] hit_data = cache_data[req_idx];
    assign proc_rdata = (req_offset == 2'b00) ? hit_data[31:0]   :
                        (req_offset == 2'b01) ? hit_data[63:32]  :
                        (req_offset == 2'b10) ? hit_data[95:64]  :
                                                hit_data[127:96] ;

    integer i;
    always@( posedge clk ) begin
        if( proc_reset ) begin
            state       <= S_IDLE;
            req_valid_q <= 1'b0;
            req_addr_q  <= 30'b0;
            miss_addr_q <= 28'b0;
            miss_idx_q  <= 5'b0;
            miss_tag_q  <= 23'b0;
            for (i = 0; i < 32; i = i + 1) cache_valid[i] <= 1'b0;
        end
        else begin
            if (state == S_IDLE) begin
                if (req_miss) begin
                    state       <= S_ALLOCATE;
                    miss_addr_q <= req_addr_q[29:2];
                    miss_idx_q  <= req_idx;
                    miss_tag_q  <= req_tag_field;
                end
                else begin
                    if (accept_request) begin
                        req_valid_q <= 1'b1;
                        req_addr_q  <= proc_addr;
                    end
                    else if (req_hit && proc_resp_ready) begin
                        req_valid_q <= 1'b0;
                    end
                end
            end
            else begin
                if (mem_ready) begin
                    state <= S_IDLE;

                    cache_valid[miss_idx_q] <= 1'b1;
                    cache_tag[miss_idx_q]   <= miss_tag_q;
                    cache_data[miss_idx_q]  <= mem_rdata;
                    // Keep req_valid_q set.  The just-filled line becomes a
                    // normal response after state returns to S_IDLE.
                end
            end
        end
    end
endmodule
