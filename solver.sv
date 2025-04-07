module solver (
    // System interface
    input  logic        clk,
    input  logic        resetN,
    input  logic        start_enable,
    
    // Input interface
    input  logic [31:0]  seq1_in,                    // 16 chars × 2 bits
    input  logic [31:0]  seq2_in,                    // 16 chars × 2 bits
    input  logic [7:0]   above_row_score [15:0],     // Scores for 16 positions
    input  logic [7:0]   left_col_score [15:0],      // Scores for 16 positions
    input  logic [3:0]   tile_row,                   // Tile position
    input  logic [3:0]   tile_col,
    
    // Output interface
    output logic         solver_done,
    output logic [511:0] arrow_matrix,               // 16×16×2 bits for arrows
    output logic [7:0]   last_row_score [15:0],      // Scores for 16 positions
    output logic [7:0]   last_col_score [15:0],      // Scores for 16 positions
    output logic [7:0]   max_score,                  // Maximum score in tile
    output logic [7:0]   max_pos,                    // Position of max score
    output logic [3:0]   out_tile_row,               // For Organizer
    output logic [3:0]   out_tile_col                // For Organizer
);

    // Internal registers and signals
    logic [7:0] score_matrix [15:0][15:0];  // Current scores
    logic [1:0] temp_arrow_matrix [15:0][15:0];  // Temporary arrow storage
    logic [7:0] current_max_score;
    logic [3:0] max_score_row, max_score_col;
    logic [4:0] diag_count;  // For diagonal processing
    logic [4:0] current_diag;
    logic processing;
    
    // Sequence storage
    logic [1:0] seq1_chars [15:0];
    logic [1:0] seq2_chars [15:0];
    
    // State machine
    typedef enum {IDLE, INIT, PROCESS_DIAG, UPDATE_SCORES, FINALIZE} state_t;
    state_t current_state, next_state;
    
    // Break down input sequences into individual characters
    always_comb begin
        for(int i = 0; i < 16; i++) begin
            seq1_chars[i] = seq1_in[2*i +: 2];
            seq2_chars[i] = seq2_in[2*i +: 2];
        end
    end
    
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
                if (start_enable)
                    next_state = INIT;
            end
            
            INIT: begin
                next_state = PROCESS_DIAG;
            end
            
            PROCESS_DIAG: begin
                if (diag_count == 31) // All diagonals processed
                    next_state = FINALIZE;
            end
            
            FINALIZE: begin
                next_state = IDLE;
            end
            
            default: next_state = IDLE;
        endcase
    end
    
    // Score calculation function
    function automatic logic [7:0] calculate_score;
        input logic [1:0] char1, char2;
        begin
            calculate_score = (char1 == char2) ? 8'd1 : -8'd1;
        end
    endfunction
    
    // Main processing logic
    always_ff @(posedge clk or negedge resetN) begin
        if (!resetN) begin
            diag_count <= '0;
            current_diag <= '0;
            processing <= 0;
            solver_done <= 0;
            max_score <= '0;
            max_pos <= '0;
            current_max_score <= '0;
            max_score_row <= '0;
            max_score_col <= '0;
            out_tile_row <= '0;
            out_tile_col <= '0;
            
            // Clear matrices
            for (int i = 0; i < 16; i++) begin
                for (int j = 0; j < 16; j++) begin
                    score_matrix[i][j] <= '0;
                    temp_arrow_matrix[i][j] <= '0;
                end
                last_row_score[i] <= '0;
                last_col_score[i] <= '0;
            end
        end
        else begin
            case (current_state)
                INIT: begin
                    // Initialize first row and column
                    for (int i = 0; i < 16; i++) begin
                        score_matrix[0][i] <= above_row_score[i];
                        score_matrix[i][0] <= left_col_score[i];
                    end
                    diag_count <= '0;
                    current_diag <= '0;
                    processing <= 1;
                    solver_done <= 0;
                end
                
                PROCESS_DIAG: begin
                    if (processing) begin
                        // Process current diagonal
                        for (int i = 0; i <= current_diag; i++) begin
                            if (i < 16 && (current_diag - i) < 16) begin
                                automatic logic [7:0] match_score, diag_score, up_score, left_score;
                                automatic logic [7:0] max_val;
                                automatic logic [1:0] arrow;
                                
                                // Calculate scores
                                match_score = calculate_score(seq1_chars[i], seq2_chars[current_diag - i]);
                                diag_score = score_matrix[i][current_diag - i] + match_score;
                                up_score = score_matrix[i - 1][current_diag - i] - 8'd2; // Gap penalty
                                left_score = score_matrix[i][current_diag - i - 1] - 8'd2; // Gap penalty
                                
                                // Find maximum
                                if (diag_score >= up_score && diag_score >= left_score && diag_score > 0) begin
                                    max_val = diag_score;
                                    arrow = 2'b01; // Diagonal
                                end
                                else if (up_score >= left_score && up_score > 0) begin
                                    max_val = up_score;
                                    arrow = 2'b10; // Up
                                end
                                else if (left_score > 0) begin
                                    max_val = left_score;
                                    arrow = 2'b11; // Left
                                end
                                else begin
                                    max_val = '0;
                                    arrow = 2'b00; // No arrow
                                end
                                
                                // Update matrices
                                score_matrix[i][current_diag - i] <= max_val;
                                temp_arrow_matrix[i][current_diag - i] <= arrow;
                                
                                // Update maximum score
                                if (max_val > current_max_score) begin
                                    current_max_score <= max_val;
                                    max_score_row <= i;
                                    max_score_col <= current_diag - i;
                                end
                            end
                        end
                        
                        // Update diagonal counters
                        if (current_diag < 30) begin
                            current_diag <= current_diag + 1;
                            diag_count <= diag_count + 1;
                        end
                    end
                end
                
                FINALIZE: begin
                    // Pack arrow matrix
                    for (int i = 0; i < 16; i++) begin
                        for (int j = 0; j < 16; j++) begin
                            arrow_matrix[32*i + 2*j +: 2] <= temp_arrow_matrix[i][j];
                        end
                        last_row_score[i] <= score_matrix[15][i];
                        last_col_score[i] <= score_matrix[i][15];
                    end
                    
                    // Set final outputs
                    max_score <= current_max_score;
                    max_pos <= {max_score_row, max_score_col};
                    out_tile_row <= tile_row;
                    out_tile_col <= tile_col;
                    solver_done <= 1;
                    processing <= 0;
                end
            endcase
        end
    end

endmodule