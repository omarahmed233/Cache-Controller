module tb2;
    localparam   MEM_WIDTH   = 32;
    localparam   MEM_DEPTH   = 2**16;    
    localparam  ADDR_WIDTH  = $clog2(MEM_DEPTH);
    localparam  FULL_WIDTH  = $clog2((MEM_WIDTH * MEM_DEPTH)/8);
    localparam   NWAYS = 4;
    localparam   NSETS = 64;
    localparam   num_blocks = 256;
    localparam OFFSET_WIDTH = $clog2((MEM_WIDTH)/8);
    localparam INDEX_WIDTH = $clog2(NSETS);
    localparam TAG_WIDTH = FULL_WIDTH - INDEX_WIDTH - OFFSET_WIDTH;
    localparam LRU_WIDTH = $clog2(NWAYS);

    reg                       clk;
    reg                       rst;
    reg  [FULL_WIDTH-1:0]     address;
    reg  [MEM_WIDTH-1:0]      din;
    reg                       rden;
    reg                       wren;

    wire                      hit_miss;
    wire [MEM_WIDTH-1:0]      q;
    wire [MEM_WIDTH-1:0]      mdout;
    wire                      mrden;
    wire                      mwren;
    wire [ADDR_WIDTH-1:0]     maddress;
    wire [MEM_WIDTH-1:0]      data_out;

    Cache_d #(
        .MEM_WIDTH(MEM_WIDTH),
        .MEM_DEPTH(MEM_DEPTH),
        .num_blocks(num_blocks)
    ) Cache (
        .clk(clk),
        .rst(rst),
        .address(address),
        .din(din),
        .rden(rden),
        .wren(wren),
        .mq(data_out),
        .hit_miss(hit_miss),
        .q(q),
        .mdout(mdout),
        .mrden(mrden),
        .maddress(maddress),
        .mwren(mwren)
    );

    RAM #(
        .MEM_WIDTH(MEM_WIDTH),
        .MEM_DEPTH(MEM_DEPTH)
    ) memory (
        .clk(clk),
        .rd_en(mrden),
        .wr_en(mwren),
        .data_in(mdout),
        .address(maddress),
        .data_out(data_out)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        rst     = 1;
        wren    = 0;
        rden    = 0;
        din     = 0;
        address = 0;

        #10;
        @(posedge clk);
        rst = 0;
        #10;
        // ------------------------------------------------------------
        // TEST 1: WRITE MISS (Write Allocate)
        // Address 0x1000 is empty. 
        // Expect: Miss -> Fetch from Memory (Fill) -> Write to Cache -> Write to Memory (Write-Through)
        // ------------------------------------------------------------
        cpu_access(1, 0, 32'h0000_1000, 32'hAAAA_AAAA);
        // ------------------------------------------------------------
        // TEST 2: READ HIT
        // Read 0x1000. Data should be in Cache now.
        // Expect: HIT.
        // ------------------------------------------------------------
        cpu_access(0, 1, 32'h0000_1000, 0);
        // ------------------------------------------------------------
        // TEST 3: WRITE HIT (Write-Through Verification)
        // Update 0x1000. Direct Mapped usually writes through to memory immediately.
        // Expect: Hit -> Update Cache -> Update Memory.
        // ------------------------------------------------------------
        cpu_access(1, 0, 32'h0000_1000, 32'hBBBB_BBBB);

        // ------------------------------------------------------------
        // TEST 4: CONFLICT MISS (Thrashing)
        // In Direct Mapped, only ONE block can exist at a specific Index.
        // We calculate an address that maps to the SAME index as 0x1000 but has a different Tag.
        //
        // Config: 256 blocks, 4 bytes/block. Cache Size = 1024 bytes (0x400).
        // Addr 0x1000 and 0x1400 will likely collide at Index 0.
        // ------------------------------------------------------------
        // This read should evict 0x1000 (containing 0xBBBB_BBBB) and load 0x1400.
        cpu_access(0, 1, 32'h0000_1400, 0); 
        // ------------------------------------------------------------
        // TEST 5: VERIFY EVICTION
        // Read 0x1000 again. Since 0x1400 took its spot, this MUST be a MISS now.
        // ------------------------------------------------------------
        cpu_access(0, 1, 32'h0000_1000, 0);
        #100;
        $finish;
    end
    task cpu_access;
        input w_en;
        input r_en;
        input [31:0] addr;
        input [31:0] data;
        begin
            // 1. Setup Data
            @(negedge clk);
            #1; 
            address = addr;
            din     = data;
            wren    = w_en;
            rden    = r_en;
            // 2. Check Hit/Miss immediately
            @(posedge clk);
            #1;
            // 3. De-assert strobes so we don't restart operations continuously
            wren = 0;
            rden = 0;
            // 4. Wait for FSM to return to IDLE (0)
            // Ensure you are referencing the correct instance name here (e.g. tb.dut.state or tb.Cache.state)
            wait(tb2.Cache.state == 0); 
            #5;
        end
    endtask
endmodule