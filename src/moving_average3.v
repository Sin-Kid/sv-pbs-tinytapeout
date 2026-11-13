/*
 * Copyright (c) 2026 Pavan G
 * SPDX-License-Identifier: Apache-2.0
 *
 * Sample buffer + three-channel, three-sample moving-average filter.
 *
 * Functionally identical to three independent filters computing
 *     out = (count < 2) ? x[n] : floor((x[n] + x[n-1] + x[n-2]) / 3)
 * for voltage (16 bit), current (16 bit) and temperature (12 bit).
 *
 * Area-saving architecture (needed to fit one Tiny Tapeout tile):
 *  - Each channel keeps its last three samples in a 3-slot ring buffer.
 *    Incoming bytes overwrite the OLDEST slot directly, so no separate
 *    "current sample" register and no history shifting are required
 *    (the sum of three slots does not depend on their order).
 *  - One shared, exact, bit-serial divide-by-3 unit (MSB first, 2-bit
 *    remainder) processes the three channels one after another. Quotient
 *    bits are shifted straight into the output register.
 *  - As the new value shifts in, the old value shifts out; a 4-bit
 *    saturating difference tracks new - old exactly enough to flag
 *    "changed by more than the tolerance" and "unchanged" for the
 *    stuck-sensor checks (no subtractor or extra registers needed).
 *  - Output registers need no reset: before the first sample the previous
 *    value is treated as 0 (matching the original reset value).
 *
 * Latency: start -> done = 3 x 18 + 2 = 56 clock cycles. The byte interface must not be
 * written while busy is high (the wrapper guarantees this).
 */

`default_nettype none

module moving_average3 (
    input  wire        clk,
    input  wire        rst_n,
    // Byte write port into the slot that will hold the next sample
    input  wire        wr_en,
    input  wire [2:0]  wr_idx,       // 0..5, see project.v for byte order
    input  wire [7:0]  wr_data,
    input  wire        start,        // one-cycle pulse: new sample complete
    output reg  [15:0] v_out,        // valid after the first done pulse
    output reg  [15:0] i_out,
    output reg  [11:0] t_out,
    output reg         done,         // one-cycle pulse: outputs updated
    output wire        busy,
    // Change of each filtered channel vs. its previous filtered value:
    //   *_act  : |new - old| > tolerance (5 for V/I, 2 for T)
    //   *_same : new == old
    output reg         v_act, i_act, t_act,
    output reg         v_same, i_same, t_same
);

    // ---------------------------------------------------------------- buffer
    // Slots are always written before they are read, so no reset is needed.
    reg [15:0] v_s0, v_s1, v_s2;
    reg [15:0] i_s0, i_s1, i_s2;
    reg [11:0] t_s0, t_s1, t_s2;
    reg [1:0]  wp;                   // slot receiving the next sample (0..2)
    reg [1:0]  count;                // number of samples seen, saturates at 2

    always @(posedge clk) begin
        if (wr_en) begin
            case (wr_idx)
                3'd0: case (wp) 2'd0: v_s0[15:8] <= wr_data; 2'd1: v_s1[15:8] <= wr_data; default: v_s2[15:8] <= wr_data; endcase
                3'd1: case (wp) 2'd0: v_s0[7:0]  <= wr_data; 2'd1: v_s1[7:0]  <= wr_data; default: v_s2[7:0]  <= wr_data; endcase
                3'd2: case (wp) 2'd0: i_s0[15:8] <= wr_data; 2'd1: i_s1[15:8] <= wr_data; default: i_s2[15:8] <= wr_data; endcase
                3'd3: case (wp) 2'd0: i_s0[7:0]  <= wr_data; 2'd1: i_s1[7:0]  <= wr_data; default: i_s2[7:0]  <= wr_data; endcase
                3'd4: case (wp) 2'd0: t_s0[11:4] <= wr_data; 2'd1: t_s1[11:4] <= wr_data; default: t_s2[11:4] <= wr_data; endcase
                default: case (wp) 2'd0: t_s0[3:0] <= wr_data[3:0]; 2'd1: t_s1[3:0] <= wr_data[3:0]; default: t_s2[3:0] <= wr_data[3:0]; endcase
            endcase
        end
    end

    // ------------------------------------------------------------- sequencer
    localparam S_IDLE = 2'd0, S_RUN = 2'd1, S_DONE = 2'd2;
    reg [1:0]  phase;
    reg [1:0]  ch;                   // 0 voltage, 1 current, 2 temperature
    reg [4:0]  bitpos;               // bit being produced, 17 down to 0
    reg [1:0]  rem;                  // division remainder (0..2)
    reg [3:0]  dacc;                 // saturated (new - old) seen so far, signed

    assign busy = (phase != S_IDLE);

    // The three slots of the channel being processed
    reg [15:0] x0, x1, x2;
    always @(*) begin
        case (ch)
            2'd0:    begin x0 = v_s0;         x1 = v_s1;         x2 = v_s2;         end
            2'd1:    begin x0 = i_s0;         x1 = i_s1;         x2 = i_s2;         end
            default: begin x0 = {4'd0, t_s0}; x1 = {4'd0, t_s1}; x2 = {4'd0, t_s2}; end
        endcase
    end

    wire        warm   = (count < 2'd2);
    wire        first  = (count == 2'd0);          // no previous filtered value
    // During warm-up only slots 0 and 1 have been written; newest = slot[count]
    wire [15:0] newest = count[0] ? x1 : x0;
    wire [17:0] sum3   = {2'b00, x0} + {2'b00, x1} + {2'b00, x2};

    // One step of MSB-first restoring division by 3
    wire        sbit     = sum3[bitpos];
    wire [2:0]  trial    = {rem, sbit};           // 2*rem + next bit (0..5)
    wire        qbit     = (trial >= 3'd3);
    wire [1:0]  rem_n    = qbit ? (trial[1:0] + 2'd1) : trial[1:0];  // trial-3 (mod 4)

    // Next bit of the new filtered value (bits above the width are zero)
    wire        nbit = warm ? ((bitpos < 5'd16) ? newest[bitpos[3:0]] : 1'b0) : qbit;

    // Matching bit of the previous filtered value: the output register is
    // shifted left while the new value is shifted in, so its MSB is that bit.
    wire        in_v = (bitpos < 5'd16);
    wire        in_t = (bitpos < 5'd12);
    reg         obit;
    always @(*) begin
        case (ch)
            2'd0:    obit = in_v & v_out[15];
            2'd1:    obit = in_v & i_out[15];
            default: obit = in_t & t_out[11];
        endcase
        if (first) obit = 1'b0;                   // reset value of old is 0
    end

    // Running difference, MSB first: d' = 2d + (nbit - obit), saturated to
    // +/-7. Once |d| >= 6 it can never come back below 6, and while |d| <= 5
    // it is exact, so tolerance and equality checks remain exact.
    wire signed [5:0] d2   = {{2{dacc[3]}}, dacc} <<< 1;
    wire signed [5:0] dnew = d2 + $signed({5'd0, nbit}) - $signed({5'd0, obit});
    wire        [3:0] dsat = (dnew >  6'sd7) ? 4'd7 :
                             (dnew < -6'sd7) ? 4'b1001 : dnew[3:0];
    wire signed [3:0] tol  = (ch == 2'd2) ? 4'sd2 : 4'sd5;
    wire        is_same = (dsat == 4'd0);
    wire        is_act  = ($signed(dsat) > tol) || ($signed(dsat) < -tol);
    wire        last    = (bitpos == 5'd0);

    // Datapath registers without reset (always initialised before use)
    always @(posedge clk) begin
        if (phase == S_RUN) begin
            rem  <= last ? 2'd0 : rem_n;
            dacc <= last ? 4'd0 : dsat;
            if (ch == 2'd0 && in_v) v_out <= {v_out[14:0], nbit};
            if (ch == 2'd1 && in_v) i_out <= {i_out[14:0], nbit};
            if (ch == 2'd2 && in_t) t_out <= {t_out[10:0], nbit};
        end else begin
            rem  <= 2'd0;
            dacc <= 4'd0;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wp <= 2'd0; count <= 2'd0;
            v_act <= 1'b0; i_act <= 1'b0; t_act <= 1'b0;
            v_same <= 1'b0; i_same <= 1'b0; t_same <= 1'b0;
            phase <= S_IDLE; ch <= 2'd0; bitpos <= 5'd17;
            done <= 1'b0;
        end else begin
            done <= 1'b0;
            case (phase)
                S_IDLE: if (start) begin
                    ch     <= 2'd0;
                    bitpos <= 5'd17;
                    phase  <= S_RUN;
                end

                S_RUN: begin
                    if (last) begin
                        case (ch)
                            2'd0:    begin v_act <= is_act; v_same <= is_same; end
                            2'd1:    begin i_act <= is_act; i_same <= is_same; end
                            default: begin t_act <= is_act; t_same <= is_same; end
                        endcase
                        bitpos <= 5'd17;
                        if (ch == 2'd2) phase <= S_DONE;
                        else            ch    <= ch + 2'd1;
                    end else begin
                        bitpos <= bitpos - 5'd1;
                    end
                end

                default: begin // S_DONE
                    wp    <= (wp == 2'd2) ? 2'd0 : wp + 2'd1;   // oldest slot next
                    if (warm) count <= count + 2'd1;
                    done  <= 1'b1;
                    phase <= S_IDLE;
                end
            endcase
        end
    end

endmodule
