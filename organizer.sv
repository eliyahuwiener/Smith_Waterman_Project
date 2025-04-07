module organizer (
    // System interface
    input  logic        clk,
    input  logic        resetN,
    
    // Interface with Solvers (×16)
    input  logic [511:0] arrow_matrix [15:0],
    input  logic [7:0]   max_score [15:0],
    input  logic [7:0]   max_pos [15:0],
    input  logic [3:0]   tile_row [15:0],
    input  logic [3:0]   tile_col [15:0],
    input  logic [15:0]  solver_done,
    
    // RAM interface
    output logic         ram_we,
    output logic [15:0]  ram_addr,
    output logic [511:0] ram_data_in,
    input  logic [511:0] ram_data_out,
    
    // CIGAR Builder interface
    output logic [511:0] arrow_matrix_out,
    output logic [7:0]   start_pos,
    output logic [3:0]   current_tile_row,
    output logic [3:0]   current_tile_col,
    output logic         cigar_valid_in,
    input  logic         request_next_tile,
    input  logic [3:0]   next_tile_row,
    input  logic [3:0]   next_tile_col,
    input  logic         cigar_done
);

    // Internal registers and parameters
    typedef enum {IDLE, COLLECT, STORE, FIND_MAX, TRACEBACK} state_t;
    state_t current_state, next_state;
    
    logic [7:0] global_max_score;
    logic [3:0] max_score_tile;
    logic [7:0] max_score_pos;
    logic [3:0] max_tile_row, max_tile_col;
    
    logic [4:0] solver_counter;  // Count processed solvers
    logic [15:0] processed_tiles;  // Track which tiles are processed
    logic all_tiles_processed;
    
    // Round-robin solver selection
    logic [4:0] current_solver;
    logic [15:0] solver_processed;  // Track which solvers are processed
    
    // Calculate RAM address based on tile position
    function automatic logic [15:0] calculate_ram_addr;
        input logic [3:0] row, col;
        begin
            calculate_ram_addr = {row, col};  // Simple mapping
        end
    endfunction

    // State machine sequential logic
    always_ff @(posedge clk or negedge resetN) begin
        if (!resetN)
            current_state <= IDLE;
        else
            current_state <= next_state;
    end

    // State machine combinational logic
    always_comb begin
        next_state = current_state;
        
        case (current_state)
            IDLE: begin
                if (|solver_done)  // Any solver done
                    next_state = COLLECT;
            end
            
            COLLECT: begin
                if (&solver_processed)  // All solvers processed
                    next_state = STORE;
            end
            
            STORE: begin
                if (processed_tiles == 16'hFFFF)  // All tiles stored
                    next_state = FIND_MAX;
            end
            
            FIND_MAX: begin
                next_state = TRACEBACK;
            end
            
            TRACEBACK: begin
                if (cigar_done)
                    next_state = IDLE;
            end
            
            default: next_state = IDLE;
        endcase
    end

    // Main processing logic
    always_ff @(posedge clk or negedge resetN) begin
        if (!resetN) begin
            global_max_score <= '0;
            max_score_tile <= '0;
            max_score_pos <= '0;
            max_tile_row <= '0;
            max_tile_col <= '0;
            current_solver <= '0;
            solver_processed <= '0;
            processed_tiles <= '0;
            solver_counter <= '0;
            ram_we <= 0;
            cigar_valid_in <= 0;
            arrow_matrix_out <= '0;
            start_pos <= '0;
            current_tile_row <= '0;
            current_tile_col <= '0;
        end
        else begin
            case (current_state)
                COLLECT: begin
                    // Round-robin processing of solver outputs
                    if (solver_done[current_solver] && !solver_processed[current_solver]) begin
                        // Update global maximum if necessary
                        if (max_score[current_solver] > global_max_score) begin
                            global_max_score <= max_score[current_solver];
                            max_score_pos <= max_pos[current_solver];
                            max_tile_row <= tile_row[current_solver];
                            max_tile_col <= tile_col[current_solver];
                        end
                        
                        // Prepare for RAM storage
                        ram_we <= 1;
                        ram_addr <= calculate_ram_addr(tile_row[current_solver], tile_col[current_solver]);
                        ram_data_in <= arrow_matrix[current_solver];
                        
                        // Update tracking
                        solver_processed[current_solver] <= 1;
                        processed_tiles[{tile_row[current_solver], tile_col[current_solver]}] <= 1;
                        
                        // Move to next solver
                        current_solver <= (current_solver == 15) ? 0 : current_solver + 1;
                    end
                end

                STORE: begin
                    ram_we <= 0;  // Complete any pending writes
                end

                TRACEBACK: begin
                    if (!cigar_valid_in) begin
                        // Initial setup for CIGAR builder
                        ram_addr <= calculate_ram_addr(max_tile_row, max_tile_col);
                        arrow_matrix_out <= ram_data_out;
                        start_pos <= max_score_pos;
                        current_tile_row <= max_tile_row;
                        current_tile_col <= max_tile_col;
                        cigar_valid_in <= 1;
                    end
                    else if (request_next_tile) begin
                        // Handle request for next tile
                        ram_addr <= calculate_ram_addr(next_tile_row, next_tile_col);
                        arrow_matrix_out <= ram_data_out;
                        current_tile_row <= next_tile_row;
                        current_tile_col <= next_tile_col;
                        cigar_valid_in <= 1;
                    end
                end

                default: begin
                    ram_we <= 0;
                    cigar_valid_in <= 0;
                end
            endcase
        end
    end

endmodule