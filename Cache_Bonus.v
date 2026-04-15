// N way set associative cache
module Cache_b(
    clk,
    rst,
    address,
    din,
    rden,
    wren,
    hit_miss,
    q,
    mdout,
    mrden,
    maddress,
    mwren,
    mq
);

    `define OFFSET  OFFSET_WIDTH-1 : 0
    `define INDEX   OFFSET_WIDTH + INDEX_WIDTH - 1 : OFFSET_WIDTH
    `define TAG     FULL_WIDTH-1 : OFFSET_WIDTH + INDEX_WIDTH

    parameter   MEM_WIDTH   = 32;
    parameter   MEM_DEPTH   = 2**16;    
    localparam  ADDR_WIDTH  = $clog2(MEM_DEPTH);
    localparam  FULL_WIDTH  = $clog2((MEM_WIDTH * MEM_DEPTH)/8);
    parameter   NWAYS = 4;
    parameter   NSETS = 64;
    localparam OFFSET_WIDTH = $clog2((MEM_WIDTH)/8);
    localparam INDEX_WIDTH = $clog2(NSETS);
    localparam TAG_WIDTH = FULL_WIDTH - INDEX_WIDTH - OFFSET_WIDTH;
    localparam LRU_WIDTH = $clog2(NWAYS);

    input wire                       clk;
    input wire                       rst;
    input  wire [FULL_WIDTH-1:0]     address;
    input  wire [MEM_WIDTH-1:0]      din;
    input  wire                      rden;
    input  wire                      wren;
    input  wire [MEM_WIDTH-1:0]      mq;

    output wire                      hit_miss;
    output reg [MEM_WIDTH-1:0]       q;
    output reg [MEM_WIDTH-1:0]       mdout;
    output reg                        mrden;
    output reg [ADDR_WIDTH-1:0]       maddress;
    output reg                        mwren;

    reg valid [0:NSETS-1][0:NWAYS-1];
    reg dirty [0:NSETS-1][0:NWAYS-1];
    reg [TAG_WIDTH-1:0] tag [0:NSETS-1][0:NWAYS-1];    
    reg [MEM_WIDTH-1:0] mem [0:NSETS-1][0:NWAYS-1];
    reg [LRU_WIDTH-1:0] lru [0:NSETS-1][0:NWAYS-1];

    reg [FULL_WIDTH-1:0] reg_addr;
    reg [MEM_WIDTH-1:0]  reg_data;
    reg                  reg_wren;
    reg                  hit;
    reg [LRU_WIDTH-1:0]  hit_way;
    reg [LRU_WIDTH-1:0]  hit_way_reg;
    reg [LRU_WIDTH-1:0]  replace_way;
    reg [LRU_WIDTH-1:0]  invalid_way;
    reg                  found_invalid;

    localparam  IDLE = 0,
                MISS_CHECK = 1,
                Read = 2,
                Write = 3,
                WRITE_BACK_wait = 4,
                WRITE_BACK_done = 5,
                WAIT_MEM = 6,
                FILL = 7;

    reg [2:0] state,next;

    // Hit detection
    integer i_hit;
    always @(*) begin
        hit = 0;
        hit_way = 0;
        for (i_hit = 0; i_hit < NWAYS; i_hit = i_hit + 1) begin
            if (valid[address[`INDEX]][i_hit] && tag[address[`INDEX]][i_hit] == address[`TAG]) begin
                hit = 1;
                hit_way = i_hit;
            end
        end
    end
    assign hit_miss = (state == IDLE) && hit ;

    integer i;
    always @(*) begin
        found_invalid = 0;
        invalid_way = 0;
        replace_way = 0;

        // Find Invalid
        for (i = 0; i < NWAYS; i = i + 1) begin
            if (!valid[reg_addr[`INDEX]][i]) begin
                invalid_way = i;
                found_invalid = 1;
            end
        end
        
        // Decide Victim
        if (found_invalid) 
            replace_way = invalid_way;
        else begin
             // Find max value (LRU)
            for (i = 0; i < NWAYS; i = i + 1) begin
                if (lru[reg_addr[`INDEX]][i] == (NWAYS-1))
                    replace_way = i;
            end
        end
    end

    // Initialize arrays
    integer i_set, i_way;
    initial begin
        for (i_set = 0; i_set < NSETS; i_set = i_set + 1)
            for (i_way = 0; i_way < NWAYS; i_way = i_way + 1) begin
                valid[i_set][i_way] = 0;
                dirty[i_set][i_way] = 0;
                mem[i_set][i_way] = 'b0;
                tag[i_set][i_way] = 'b0;
                lru[i_set][i_way] = i_way;
            end
    end

    // Main FSM
    integer i_write, i_read, i_fill;
    reg [LRU_WIDTH-1:0] old_lru;
    always @(posedge clk) begin
        if (rst) begin
            q <= 0;
            mrden <= 0;
            mwren <= 0;
            maddress <= 'b0;
            mdout<= 'b0;
        end
        else begin
            case (state)
                IDLE: begin
                    mrden <= 0;
                    mwren <= 0;
                    reg_addr  <= address;
                    reg_data  <= din;
                    reg_wren <= wren;
                    hit_way_reg <= hit_way;
                end
                Write : begin
                    mem[reg_addr[`INDEX]][hit_way_reg] <= reg_data;
                    dirty[reg_addr[`INDEX]][hit_way_reg] <= 1;
                    //////////////////////////////////////////////////
                    old_lru = lru[reg_addr[`INDEX]][hit_way_reg] ;
                    for (i_write = 0; i_write < NWAYS; i_write = i_write + 1) begin
                        if (i_write == hit_way_reg) 
                            lru[reg_addr[`INDEX]][i_write] <= 0; 
                        else if (lru[reg_addr[`INDEX]][i_write] < old_lru)
                            lru[reg_addr[`INDEX]][i_write] <= lru[reg_addr[`INDEX]][i_write] + 1;
                    end
                    ///////////////////////////////////////////////////
                end
                Read : begin
                    q <= mem[reg_addr[`INDEX]][hit_way_reg];
                    mrden <= 0;
                    mwren <= 0;
                    ////////////////////////////////////////////////////////////////
                    old_lru = lru[reg_addr[`INDEX]][hit_way_reg] ;
                    for (i_read = 0; i_read < NWAYS; i_read = i_read + 1) begin
                        if (i_read == hit_way_reg) 
                            lru[reg_addr[`INDEX]][i_read] <= 0; 
                        else if (lru[reg_addr[`INDEX]][i_read] < old_lru)
                            lru[reg_addr[`INDEX]][i_read] <= lru[reg_addr[`INDEX]][i_read] + 1;
                    end
                    ///////////////////////////////////////////////////////////////////
                end
                MISS_CHECK: begin
                    if (dirty[reg_addr[`INDEX]][replace_way]) begin
                        maddress <= {tag[reg_addr[`INDEX]][replace_way], reg_addr[`INDEX]};
                        mwren <= 1;
                        mrden <= 0;
                        mdout <= mem[reg_addr[`INDEX]][replace_way];
                    end
                    else begin
                        maddress <= reg_addr[FULL_WIDTH-1 : OFFSET_WIDTH];
                        mwren <= 0;
                        mrden <= 1;
                    end
                end
                WRITE_BACK_wait: begin
                    maddress <= {tag[reg_addr[`INDEX]][replace_way], reg_addr[`INDEX]};
                    mrden <= 0;
                    mwren <= 1;
                    mdout <= mem[reg_addr[`INDEX]][replace_way];
                end
                WRITE_BACK_done: begin
                    mrden <= 1;
                    mwren <= 0;
                    maddress <= reg_addr[FULL_WIDTH-1 : OFFSET_WIDTH];
                end
                WAIT_MEM: begin
                    mrden <= 1;
                    mwren <= 0;
                end
                FILL: begin
                    mem[reg_addr[`INDEX]][replace_way] <=  reg_wren ?  reg_data : mq;
                    tag [reg_addr[`INDEX]][replace_way] <= reg_addr[`TAG];
                    valid[reg_addr[`INDEX]][replace_way] <= 1;
                    dirty[reg_addr[`INDEX]][replace_way] <= reg_wren;
                    mrden <= 0;
                    mwren <= 0;

                    if (~reg_wren)
                        q <= mq;

                    old_lru = lru[reg_addr[`INDEX]][replace_way] ;
                    for (i_fill = 0; i_fill < NWAYS; i_fill = i_fill + 1) begin
                        if (i_fill == replace_way) 
                            lru[reg_addr[`INDEX]][i_fill] <= 0; 
                        else if (lru[reg_addr[`INDEX]][i_fill] < old_lru)
                            lru[reg_addr[`INDEX]][i_fill] <= lru[reg_addr[`INDEX]][i_fill] + 1;
                    end
                end
            endcase
        end
    end

    always @(posedge clk) begin
        if (rst)
            state <= IDLE;
        else 
            state <= next;
    end

    always @(*) begin
        case (state)
            IDLE: begin
                if ((rden || wren) && !hit) next = MISS_CHECK;
                else if(wren && hit) next = Write; 
                else if(rden && hit) next = Read; 
                else next = IDLE;
            end
            Write : next = IDLE;
            Read : next = IDLE;
            MISS_CHECK: next = dirty[reg_addr[`INDEX]][replace_way] ? WRITE_BACK_wait : WAIT_MEM;
            WRITE_BACK_wait: next = WRITE_BACK_done;
            WRITE_BACK_done: next = WAIT_MEM;
            WAIT_MEM: next = FILL;
            FILL: next = IDLE;
            default : next = IDLE;
        endcase
    end

endmodule
