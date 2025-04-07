module solver_tb();
    // Clock and reset
    logic clk;
    logic resetN;
    logic start_enable;

// Test inputs
logic [31:0] seq1_in, seq2_in;
logic [7:0]  above_row_score [15:0];
logic [7:0]  left_col_score [15:0];
logic [3:0]  tile_row, tile_col;

// Test outputs
logic        solver_done;
logic [511:0] arrow_matrix;
logic [7:0]   last_row_score [15:0];
logic [7:0]   last_col_score [15:0];
logic [7:0]   max_score;
logic [7:0]   max_pos;
logic [3:0]   out_tile_row, out_tile_col;

// Instantiate DUT
solver dut (.*);

// Clock generation
always begin
    clk = 0; #5;
    clk = 1; #5;
end

// Test sequence generation
function automatic logic [31:0] generate_sequence;
    input int seed;
    begin
        for (int i = 0; i < 16; i++) begin
            generate_sequence[2*i +: 2] = (seed + i) % 4;
        end
    end
endfunction

// Checker
function automatic void check_arrow_validity;
    input logic [511:0] arrow_mat;
    begin
        for (int i = 0; i < 256; i++) begin
            logic [1:0] arrow = arrow_mat[2*i +: 2];
            assert(arrow inside {2'b00, 2'b01, 2'b10, 2'b11})
            else $error("Invalid arrow value at position %0d", i);
        end
    end
endfunction

// Test stimulus
initial begin
    // Initialize
    resetN = 0;
    start_enable = 0;
    seq1_in = 0;
    seq2_in = 0;
    tile_row = 0;
    tile_col = 0;
    for (int i = 0; i < 16; i++) begin
        above_row_score[i] = 0;
        left_col_score[i] = 0;
    end
    
    // Reset
    #20;
    resetN = 1;
    #10;
    
    // Test Case 1: Simple match pattern
    seq1_in = generate_sequence(0);
    seq2_in = generate_sequence(0);  // Same sequence
    tile_row = 4'h1;
    tile_col = 4'h2;
    start_enable = 1;
    
    // Wait for completion
    @(posedge solver_done);
    check_arrow_validity(arrow_matrix);
    assert(max_score > 0) else $error("Expected positive max score for matching sequences");
    
    // Test Case 2: No matches
    #20;
    start_enable = 0;
    #10;
    seq1_in = generate_sequence(0);
    seq2_in = generate_sequence(2);  // Different sequence
    start_enable = 1;
    
    @(posedge solver_done);
    check_arrow_validity(arrow_matrix);
    
    // More test cases can be added here
    
    #100;
    $finish;
end

// Monitor
initial begin
    $monitor("Time=%0t done=%b max_score=%h pos=%h",
             $time, solver_done, max_score, max_pos);
end
endmodule