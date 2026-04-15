module Cache_d(
    clk,
    rst,
    address,  // cpu to cache 
    din, // input cpu to cache
    rden, // cpu
    wren, //cpu
    hit_miss, // 1 : hit / 0: miss
    q, // output cache to cpu
    mdout, //
    mrden,
    maddress,
    mwren,
    mq
);

    `define OFFSET  OFFSET_WIDTH-1 : 0
    `define INDEX   OFFSET_WIDTH + INDEX_WIDTH - 1 : OFFSET_WIDTH
    `define TAG     FULL_WIDTH-1 : OFFSET_WIDTH + INDEX_WIDTH

    parameter   MEM_WIDTH   = 32                                    ;   //data block size or data width
    parameter   MEM_DEPTH   = 2**16                                 ;    
    localparam  ADDR_WIDTH  = $clog2(MEM_DEPTH)                     ;   //address width
    localparam  FULL_WIDTH  = $clog2((MEM_WIDTH * MEM_DEPTH)/8)     ;

    parameter num_blocks = 256;    // number of cache blocks
    localparam OFFSET_WIDTH = $clog2((MEM_WIDTH)/8)                 ;
    localparam INDEX_WIDTH = $clog2(num_blocks)                          ;
    localparam TAG_WIDTH = FULL_WIDTH - INDEX_WIDTH - OFFSET_WIDTH  ;
    /////////////////////inputs////////////////////////////////////////////////////
    input wire                       clk            ;
    input wire                       rst            ;
    input  wire [FULL_WIDTH-1:0]     address        ;    // address form CPU
    input  wire [MEM_WIDTH-1:0]      din            ;    // data from CPU (if st inst)
    input  wire                      rden           ;    // read
    input  wire                      wren           ;    // write
    input  wire [MEM_WIDTH-1:0]         mq          ;   // data coming from memory to cache
    /////////////////////outputs////////////////////////////////////////////////////
    output reg                      hit_miss       ;   // 1 for a hit , 0 for a miss
    output reg [MEM_WIDTH-1:0]      q               ;   // data from cache to CPU
    output reg [MEM_WIDTH-1:0]      mdout           ;   // data from cache to memory
    output reg                      mrden           ;   // read enable, 1 if reading from memory
    output reg                      mwren           ;   // write enable, 1 if writing to memory
    output reg [ADDR_WIDTH-1:0]     maddress        ;   // memory address

    reg [TAG_WIDTH-1:0] tag [0:num_blocks-1];    
    reg [MEM_WIDTH-1:0] mem [0:num_blocks-1];
    reg valid [0:num_blocks-1]              ;

    integer i;
    initial begin
        for(i=0; i<num_blocks; i=i+1) begin
            valid[i] = 0;
            tag[i] = 'b0;
            mem[i] = 'b0;
        end
    end

    localparam  IDLE = 0,
                MISS = 1,
                Read = 2,
                Write = 3,
                Write_wait = 4,
                WAIT_MEM = 5,
                FILL = 6;

    reg [2:0] state,next;

    wire hit;
    assign hit = valid[address[`INDEX]] && (tag[address[`INDEX]] == address[`TAG]);

    always@(posedge clk) begin
        if(rst) hit_miss <= 0;
        else hit_miss <= (state == IDLE) && hit;
    end

    reg reg_write;
    reg [FULL_WIDTH-1:0] reg_addr;
    reg [MEM_WIDTH-1:0]  reg_data;

    always@(posedge clk) begin
        if(rst) begin
            q <= 0;
            mdout <= 'b0;
            mrden <= 0;
            mwren <= 0;
            maddress <= 0;
        end
        else begin
            mrden <= 0;
            mwren <= 0;
            mdout <= 'b0;
            case(state)
                IDLE : begin
                    mrden <= 0;
                    mwren <= 0;
                    reg_addr  <= address;
                    reg_data  <= din;
                    reg_write <= wren;
                end
                MISS : begin
                    maddress <= reg_addr[FULL_WIDTH-1 : OFFSET_WIDTH];
                    mwren <= 0;
                    mrden <= 1;
                end
                WAIT_MEM : begin
                    maddress <= reg_addr[FULL_WIDTH-1 : OFFSET_WIDTH];
                    mwren <= 0;
                    mrden <= 1;
                end
                FILL : begin
                    mem[reg_addr[`INDEX]] <= mq;
                    tag [reg_addr[`INDEX]] <= reg_addr[`TAG];
                    valid[reg_addr[`INDEX]] <= 1;
                    mwren <= 0;
                    mrden <= 0;

                    if(~reg_write) q<= mq;
                end
                Write : begin
                    maddress <= reg_addr[FULL_WIDTH-1 : OFFSET_WIDTH];
                    mdout    <= reg_data;
                    mwren <= 1;
                    mrden <= 0;

                    mem[reg_addr[`INDEX]]   <= reg_data;
                    tag[reg_addr[`INDEX]]   <= reg_addr[`TAG];
                    valid[reg_addr[`INDEX]] <= 1;
                end
                Write_wait : begin
                    maddress <= reg_addr[FULL_WIDTH-1 : OFFSET_WIDTH];
                    mdout    <= reg_data;
                    mwren <= 1;
                    mrden <= 0;
                end
                Read : begin
                    q <= mem[reg_addr[`INDEX]];
                    mwren <= 0;
                    mrden <= 0;
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

    always@(*) begin
        case(state)
            IDLE : begin
                if((~hit) && (wren || rden)) next = MISS;
                else if(wren) next = Write;
                else if(rden) next = Read;
                else next = IDLE;
            end
            MISS : next = WAIT_MEM;
            Read : next = IDLE;
            Write : next = Write_wait;
            Write_wait : next = IDLE;
            WAIT_MEM : next = FILL;
            FILL : next = reg_write ? Write : IDLE ;
            default : next = IDLE;
        endcase
    end
endmodule