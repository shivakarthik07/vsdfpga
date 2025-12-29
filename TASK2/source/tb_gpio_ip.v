`timescale 1ns / 1ps

module gpio_ip_tb;

    reg clk;
    reg resetn;
    reg wr_en;
    reg rd_en;
    reg [31:0] wdata;

    wire [31:0] rdata;
    wire [31:0] gpio_data;

    // DUT instantiation
    gpio_ip dut (
        .clk(clk),
        .resetn(resetn),
        .wr_en(wr_en),
        .rd_en(rd_en),
        .wdata(wdata),
        .rdata(rdata),
        .gpio_data(gpio_data)
    );

    // Clock generation: 10 ns period
    always #5 clk = ~clk;

    initial begin
        // Dump for GTKWave
        $dumpfile("gpio.vcd");
        $dumpvars(0, gpio_ip_tb);

        // Initialize signals
        clk    = 0;
        resetn = 0;
        wr_en  = 0;
        rd_en  = 0;
        wdata  = 32'b0;

        // Hold reset for a few cycles
        #20;
        resetn = 1;

        // ------------------------
        // WRITE TEST
        // Drive inputs on negedge
        // ------------------------
        @(negedge clk);
        wr_en = 1;
        wdata = 32'h00000005;

        @(negedge clk);
        wr_en = 0;

        // ------------------------
        // READ TEST
        // ------------------------
        @(negedge clk);
        rd_en = 1;

        @(negedge clk);
        rd_en = 0;

        // Finish simulation
        #20;
        $finish;
    end

endmodule

