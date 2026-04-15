module tb;

    localparam   MEM_WIDTH   = 32;
    localparam   MEM_DEPTH   = 2**16;    
    localparam  ADDR_WIDTH  = $clog2(MEM_DEPTH);
    localparam  FULL_WIDTH  = $clog2((MEM_WIDTH * MEM_DEPTH)/8);
    localparam   NWAYS = 4;
    localparam   NSETS = 64;
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

    Cache_b #(
        .MEM_WIDTH(MEM_WIDTH),
        .MEM_DEPTH(MEM_DEPTH),
        .NWAYS(NWAYS),
        .NSETS(NSETS)
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
        // CASE 1: WRITE MISS
        // Address 0x1000 is not in cache. This should trigger a fetch 
        // (Write Allocate) and then write the data into cache.
        // ------------------------------------------------------------
        cpu_access(1, 0, 32'h0000_1000, 32'hAAAA_AAAA); 
        
        // ------------------------------------------------------------
        // CASE 2: READ HIT
        // We just wrote to 0x1000. Reading it back should be a HIT 
        // and return 0xAAAA_AAAA.
        // ------------------------------------------------------------
        cpu_access(0, 1, 32'h0000_1000, 0);
        
        // ------------------------------------------------------------
        // CASE 3: WRITE HIT
        // Address 0x1000 is in cache. Update it to 0xBBBB_BBBB.
        // This should set the DIRTY bit for this line.
        // ------------------------------------------------------------
        cpu_access(1, 0, 32'h0000_1000, 32'hBBBB_BBBB);


        // ------------------------------------------------------------
        // CASE 4: READ MISS (Clean)
        // Read new address 0x2000. Cache must fetch from memory.
        // ------------------------------------------------------------
        cpu_access(0, 1, 32'h0000_2000, 0);
        
        // ------------------------------------------------------------
        // CASE 5: FORCED EVICTION & WRITE BACK
        // We have 4 ways. We will map 5 different addresses to the SAME SET 
        // to force the eviction of the first address (0x1000).
        //
        // 0x1000 is currently in the cache and DIRTY (Value 0xBBBB_BBBB).
        // When it is evicted, the cache must write 0xBBBB_BBBB back to memory.
        //
        // Let's assume Set Index bits are [10:5] (based on param settings).
        // We need addresses that differ in TAG but have same INDEX.
        // ------------------------------------------------------------
        
        // Note: 0x1000 is already in Way 0 (roughly)
        
        // Fill Way 1, 2, 3
        cpu_access(1, 0, 32'h0001_1000, 32'h1111_1111); // Way 1
        cpu_access(1, 0, 32'h0002_1000, 32'h2222_2222); // Way 2
        cpu_access(1, 0, 32'h0003_1000, 32'h3333_3333); // Way 3
        
        // Accessing Way 4 (Virtual) -> Forces eviction of LRU (which should be 0x1000)
        cpu_access(1, 0, 32'h0004_1000, 32'h4444_4444); 
        
        // ------------------------------------------------------------
        // CASE 6: VERIFY EVICTION
        // Read 0x1000 again. Since it was evicted, this should be a MISS.
        // If the Write-Back worked, memory should hold 0xBBBB_BBBB, 
        // so we should read that back.
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
            @(negedge clk);
            #1; 
            address = addr;
            din     = data;
            wren    = w_en;
            rden    = r_en;

            @(negedge clk);
            #1;

            wren = 0;
            rden = 0;

            wait(tb.Cache.state == 0); 
            #5; 
        end
    endtask

endmodule
