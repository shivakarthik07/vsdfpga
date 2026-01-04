`timescale 1ns / 1ps
module gpio_ctrl_ip (
    input  wire clk,
    input  wire resetn,
    // Bus interface
    input  wire sel,         // GPIO selected
    input  wire wr_en,        // write enable
    input  wire rd_en,       // read enable
    input  wire [1:0] addr,  // register select
    input  wire [31:0] wdata,
    output reg  [31:0] rdata,

    // GPIO pins
    output reg  [31:0] gpio_out,
    input  wire [31:0] gpio_in
);

    // Registers
    reg [31:0] gpio_data;   // output data register
    reg [31:0] gpio_dir;    // direction register (1=output)
    // WRITE LOGIC (clocked)
    always @(posedge clk) begin
        if (!resetn) begin
            gpio_data <= 32'b0;
            gpio_dir  <= 32'b0;
            gpio_out  <= 32'b0;
        end 
        else if (sel && wr_en) 
        begin
            case (addr)
                2'b00: gpio_data <= wdata;   // GPIO_DATA
                2'b01: gpio_dir  <= wdata;   // GPIO_DIR
                default: ;
            endcase
        end
        // Drive outputs only for output pins
        gpio_out <= gpio_data & gpio_dir;
    end

    // READ LOGIC (clocked → holds value)
    always @(posedge clk) begin
        if (!resetn) begin
            rdata <= 32'b0;
        end else if (sel && rd_en) begin
            case (addr)
                2'b00: rdata <= gpio_data;                 // DATA readback
                2'b01: rdata <= gpio_dir;                  // DIR readback
                2'b10: rdata <= (gpio_out | (gpio_in & ~gpio_dir)); // READ
                default: rdata <= 32'b0;
            endcase
        end
    end
endmodule
