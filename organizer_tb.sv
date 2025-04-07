module organizer_tb();
    // Clock and reset
    logic clk;
    logic resetN;
    
    // Solver interface signals
    logic [511:0] arrow_matrix [15:0];
    logic [7:0]   max_score [15:0];
    logic [7:0]   max_pos [15:0];
    logic [3:0]   tile_row [15:0];
    logic [3:0]   tile_col [15:0];
    logic [15:0]  solver_done;
    
    // RAM interface
    logic         ram_we;
    logic [15:0]  ram_addr;
    logic [511:0] ram_data_in;
    logic [511:0] ram_data_out;
    
    // CIGAR Builder interface
    logic [511:0] arrow_matrix_out;
    logic [7:0]   start_pos;
    logic [3:0]   current_tile_row;
    logic [3:0]   current_tile_col;
    logic         cigar_valid_in;
    logic         request_next_tile;
    logic [3:0]   next_tile_row;
    logic [3:0]   next_tile_col;
    logic         cigar_done;
    
    // Instantiate DUT
    organizer dut (.*);
    
    // Clock generation
    always begin
        clk = 0; #5;
        clk = 1; #5;
    end
    
    // RAM model
    logic [511:0] ram_array [0:255];
    
    always_ff @(posedge clk) begin
        if (ram_we)
            ram_array[ram_addr] <= ram_data_in;
        ram_data_out <= ram_array[ram_addr];
    end
    
    // Checker tasks
    // Checker tasks
task check_ram_storage;
    input int solver_idx;
    begin
        automatic logic [15:0] expected_addr;  // Added 'automatic'
        expected_addr = {tile_row[solver_idx], tile_col[solver_idx]};
        assert(ram_array[expected_addr] === arrow_matrix[solver_idx])
        else $error("RAM storage mismatch for solver %0d", solver_idx);
    end
endtask

task check_max_score_tracking;
    begin
        automatic logic [7:0] expected_max = '0;    // Added 'automatic'
        automatic logic [3:0] expected_solver = '0; // Added 'automatic'
        
        // Find expected maximum
        for (int i = 0; i < 16; i++) begin
            if (solver_done[i] && max_score[i] > expected_max) begin
                expected_max = max_score[i];
                expected_solver = i[3:0];
            end
        end
        
        // Check if organizer tracked it correctly
        #20; // Allow for processing
        assert(start_pos === max_pos[expected_solver])
        else $error("Max score position mismatch");
    end
endtask
    
    // Test stimulus
    initial begin
        // Initialize
        resetN = 0;
        solver_done = '0;
        request_next_tile = 0;
        cigar_done = 0;
        next_tile_row = 0;
        next_tile_col = 0;
        
        for (int i = 0; i < 16; i++) begin
            arrow_matrix[i] = '0;
            max_score[i] = '0;
            max_pos[i] = '0;
            tile_row[i] = '0;
            tile_col[i] = '0;
        end
        
        // Reset
        #20;
        resetN = 1;
        #10;
        
        // Test Case 1: Single solver completion
        arrow_matrix[0] = {512{1'b1}};  // Example pattern
        max_score[0] = 8'h20;
        max_pos[0] = 8'h11;
        tile_row[0] = 4'h1;
        tile_col[0] = 4'h2;
        solver_done[0] = 1;
        
        #50;
        check_ram_storage(0);
        check_max_score_tracking();
        
        // Test Case 2: Multiple solver completions
        for (int i = 1; i < 4; i++) begin
            arrow_matrix[i] = {512{1'b1}} >> i;  // Different patterns
            max_score[i] = 8'h10 + i;
            max_pos[i] = 8'h22 + i;
            tile_row[i] = i[3:0];
            tile_col[i] = i[3:0] + 1;
            solver_done[i] = 1;
            #20;
            check_ram_storage(i);
        end
        
        check_max_score_tracking();
        
        // Test Case 3: CIGAR Builder interface
        #50;
        request_next_tile = 1;
        next_tile_row = 4'h3;
        next_tile_col = 4'h4;
        #20;
        assert(current_tile_row === next_tile_row && current_tile_col === next_tile_col)
        else $error("Tile position update failed");
        
        // Test Case 4: Complete processing
        #100;
        cigar_done = 1;
        #20;
        assert(dut.current_state === dut.IDLE)
        else $error("Failed to return to IDLE after completion");
        
        // Test Case 5: Stress test with all solvers
        solver_done = '1;  // All solvers complete
        for (int i = 0; i < 16; i++) begin
            arrow_matrix[i] = {512{1'b1}} >> i;
            max_score[i] = 8'h30 + i;
            max_pos[i] = 8'h33 + i;
            tile_row[i] = i[3:0];
            tile_col[i] = i[3:0];
        end
        
        #500;  // Allow for processing
        check_max_score_tracking();
        
        $display("All tests completed!");
        #100;
        $finish;
    end
    
    // Monitor
    initial begin
        $monitor("Time=%0t state=%s done=%b",
                 $time, dut.current_state.name(), cigar_done);
    end
    
    // Coverage
    covergroup state_coverage @(posedge clk);
        coverpoint dut.current_state {
            bins states[] = {dut.IDLE, dut.COLLECT, dut.STORE, 
                           dut.FIND_MAX, dut.TRACEBACK};
            bins transitions[] = (dut.IDLE => dut.COLLECT => dut.STORE => 
                                dut.FIND_MAX => dut.TRACEBACK => dut.IDLE);
        }
    endgroup
    
    state_coverage cov = new();
    
    // Assertions
    property valid_ram_addr;
        @(posedge clk) ram_we |-> ram_addr inside {[0:255]};
    endproperty
    
    property valid_state_transition;
        @(posedge clk) dut.current_state != dut.next_state |-> 
            dut.next_state inside {dut.IDLE, dut.COLLECT, dut.STORE, 
                                 dut.FIND_MAX, dut.TRACEBACK};
    endproperty
    
    assert property (valid_ram_addr)
    else $error("Invalid RAM address detected");
    
    assert property (valid_state_transition)
    else $error("Invalid state transition detected");
    
endmodule