module RAM (
    input  wire                 clk,
    input  wire                 rd_en,
    input  wire                 wr_en,
    input  wire [31:0]          data_in,
    input  wire [15:0]          address,
    output reg  [31:0]          data_out
);
    
    parameter MEM_WIDTH = 32;
    parameter MEM_DEPTH = 2**16;

    reg [MEM_WIDTH-1:0] mem [0:MEM_DEPTH-1];

    integer k;
    initial begin
        for(k=0; k<MEM_DEPTH; k=k+1)
            mem[k] = 0;
    end
    
    always @(posedge clk) begin
        if (wr_en) begin
            mem[address] <= data_in;      
        end
        else if (rd_en) begin
            data_out <= mem[address];    
        end
    end

endmodule
