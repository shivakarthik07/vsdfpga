`timescale 1ns/1ps

module gpio_ip (
    input clk,
    input resetn,
    input wr_en,
    input rd_en,
    input [31:0] wdata,
    output reg  [31:0] rdata,
    output reg  [31:0] gpio_data
);
    reg [31:0] gpio_reg;
    // Write logic (clocked)
    always @(posedge clk) begin
        if (!resetn) begin
            gpio_reg  <= 32'b0;
            gpio_data <= 32'b0;
        end else if (wr_en) begin
            gpio_reg  <= wdata;
            gpio_data <= wdata;
        end
    end
  // Read logic (registered, holds value)
always @(posedge clk) begin
    if (!resetn) begin
        rdata <= 32'b0;
    end else if (rd_en) begin
        rdata <= gpio_reg;
    end
end
endmodule
