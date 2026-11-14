/*
 * Copyright (c) 2026 Pavan G, Manali Kulkarni, Shylashree N, RV College of Engineering
 * SPDX-License-Identifier: Apache-2.0
 *
 * Sample buffer + three-channel, three-sample moving-average filter.
 *
 * For every sample it computes, per channel,
 *     out = (count < 2) ? x[n] : floor((x[n] + x[n-1] + x[n-2]) / 3)
 *
 * Storage widths are matched to the sensor full-scale ranges:
 *     voltage      13 bit  (0 .. 8191 mV)
 *     current      11 bit  (0 .. 2047 mA)
 *     temperature  11 bit  (0 .. 204.7 degC, 0.1 degC units)
 * The byte interface still carries 16/16/12-bit values; a value above the
 * full-scale range is clipped to the maximum code. All protection thresholds
 * lie well inside these ranges, so in-range samples give exactly the same
 * result as the original 16/16/12-bit SV-PBS V2.1 design.
 *
 * Area-saving architecture (needed to fit one Tiny Tapeout tile):
 *  - Each channel keeps its last three samples in a 3-slot ring buffer.
 *    Incoming bytes overwrite the OLDEST slot directly (the sum of three
 *    slots does not depend on their order).
 *  - One shared, exact, bit-serial divide-by-3 unit (MSB first, 2-bit
 *    remainder) processes the three channels one after another. Quotient
 *    bits are shifted straight into the output register.
 *  - As the new value shifts in, the old value shifts out; a 4-bit
 *    saturating difference tracks new - old exactly enough to flag
 *    "changed by more than the tolerance" and "unchanged" for the
 *    stuck-sensor checks.
 *  - Output registers need no reset: before the first sample the previous
 *    value is treated as 0 (matching the original reset value).
 *
 * Latency: start -> done = 3 x 15 + 2 = 47 clock cycles. The byte interface
 * must not be written while busy is high (the wrapper guarantees this).
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
    output reg  [12:0] v_out,        // valid after the first done pulse
    output reg  [10:0] i_out,
    output reg  [10:0] t_out,
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
    reg [12:0] v_s0, v_s1, v_s2;
    reg [10:0] i_s0, i_s1, i_s2;
    reg [10:0] t_s0, t_s1, t_s2;
    reg [1:0]  wp;                   // slot receiving the next sample (0..2)
    reg [1:0]  count;                // number of samples seen, saturates at 2
    reg        clip;                 // high byte of this value was over range

    // Low/high parts of the value being written, with clipping applied
    wire       clip_v = |wr_data[7:5];          // voltage   >= 8192
    wire       clip_i = |wr_data[7:3];          // current   >= 2048
    wire       clip_t = wr_data[7];             // temperature >= 2048
    wire [7:0] lo8    = clip ? 8'hFF : wr_data;
    wire [3:0] lo4    = clip ? 4'hF  : wr_data[3:0];

    always @(posedge clk) begin
        if (wr_en) begin
            case (wr_idx)
                3'd0: begin
                    clip <= clip_v;
                    case (wp) 2'd0: v_s0[12:8] <= wr_data[4:0]; 2'd1: v_s1[12:8] <= wr_data[4:0]; default: v_s2[12:8] <= wr_data[4:0]; endcase
                end
                3'd1: begin
                    case (wp) 2'd0: v_s0[7:0] <= lo8; 2'd1: v_s1[7:0] <= lo8; default: v_s2[7:0] <= lo8; endcase
                    if (clip) case (wp) 2'd0: v_s0[12:8] <= 5'h1F; 2'd1: v_s1[12:8] <= 5'h1F; default: v_s2[12:8] <= 5'h1F; endcase
                end
                3'd2: begin
                    clip <= clip_i;
                    case (wp) 2'd0: i_s0[10:8] <= wr_data[2:0]; 2'd1: i_s1[10:8] <= wr_data[2:0]; default: i_s2[10:8] <= wr_data[2:0]; endcase
                end
                3'd3: begin
                    case (wp) 2'd0: i_s0[7:0] <= lo8; 2'd1: i_s1[7:0] <= lo8; default: i_s2[7:0] <= lo8; endcase
                    if (clip) case (wp) 2'd0: i_s0[10:8] <= 3'h7; 2'd1: i_s1[10:8] <= 3'h7; default: i_s2[10:8] <= 3'h7; endcase
                end
                3'd4: begin
                    clip <= clip_t;
                    case (wp) 2'd0: t_s0[10:4] <= wr_data[6:0]; 2'd1: t_s1[10:4] <= wr_data[6:0]; default: t_s2[10:4] <= wr_data[6:0]; endcase
                end
                default: begin
                    case (wp) 2'd0: t_s0[3:0] <= lo4; 2'd1: t_s1[3:0] <= lo4; default: t_s2[3:0] <= lo4; endcase
                    if (clip) case (wp) 2'd0: t_s0[10:4] <= 7'h7F; 2'd1: t_s1[10:4] <= 7'h7F; default: t_s2[10:4] <= 7'h7F; endcase
                end
            endcase
        end
    end

    // ------------------------------------------------------------- sequencer
    localparam S_IDLE = 2'd0, S_RUN = 2'd1, S_DONE = 2'd2;
    localparam [3:0] TOP = 4'd14;    // 3 x 8191 < 2^15: 15 dividend bits
    reg [1:0]  phase;
    reg [1:0]  ch;                   // 0 voltage, 1 current, 2 temperature
    reg [3:0]  bitpos;               // bit being produced, 14 down to 0
    reg [1:0]  rem;                  // division remainder (0..2)
    reg [3:0]  dacc;                 // saturated (new - old) seen so far, signed

    assign busy = (phase != S_IDLE);

    // The three slots of the channel being processed
    reg [14:0] x0, x1, x2;
    always @(*) begin
        case (ch)
            2'd0:    begin x0 = {2'd0, v_s0}; x1 = {2'd0, v_s1}; x2 = {2'd0, v_s2}; end
            2'd1:    begin x0 = {4'd0, i_s0}; x1 = {4'd0, i_s1}; x2 = {4'd0, i_s2}; end
            default: begin x0 = {4'd0, t_s0}; x1 = {4'd0, t_s1}; x2 = {4'd0, t_s2}; end
        endcase
    end

    wire        warm   = (count < 2'd2);
    wire        first  = (count == 2'd0);          // no previous filtered value
    // During warm-up only slots 0 and 1 have been written; newest = slot[count]
    wire [14:0] newest = count[0] ? x1 : x0;
    wire [14:0] sum3   = x0 + x1 + x2;

    // One step of MSB-first restoring division by 3
    wire        sbit  = sum3[bitpos];
    wire [2:0]  trial = {rem, sbit};               // 2*rem + next bit (0..5)
    wire        qbit  = (trial >= 3'd3);
    wire [1:0]  rem_n = qbit ? (trial[1:0] + 2'd1) : trial[1:0];  // trial-3 (mod 4)

    // Next bit of the new filtered value (bits above the width are zero)
    wire        nbit = warm ? newest[bitpos] : qbit;

    // Matching bit of the previous filtered value: the output register is
    // shifted left while the new value is shifted in, so its MSB is that bit.
    wire        in_v = (bitpos < 4'd13);
    wire        in_w = (bitpos < 4'd11);
    reg         obit;
    always @(*) begin
        case (ch)
            2'd0:    obit = in_v & v_out[12];
            2'd1:    obit = in_w & i_out[10];
            default: obit = in_w & t_out[10];
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
    wire        last    = (bitpos == 4'd0);

    // Datapath registers without reset (always initialised before use)
    always @(posedge clk) begin
        if (phase == S_RUN) begin
            rem  <= last ? 2'd0 : rem_n;
            dacc <= last ? 4'd0 : dsat;
            if (ch == 2'd0 && in_v) v_out <= {v_out[11:0], nbit};
            if (ch == 2'd1 && in_w) i_out <= {i_out[9:0],  nbit};
            if (ch == 2'd2 && in_w) t_out <= {t_out[9:0],  nbit};
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
            phase <= S_IDLE; ch <= 2'd0; bitpos <= TOP;
            done <= 1'b0;
        end else begin
            done <= 1'b0;
            case (phase)
                S_IDLE: if (start) begin
                    ch     <= 2'd0;
                    bitpos <= TOP;
                    phase  <= S_RUN;
                end

                S_RUN: begin
                    if (last) begin
                        case (ch)
                            2'd0:    begin v_act <= is_act; v_same <= is_same; end
                            2'd1:    begin i_act <= is_act; i_same <= is_same; end
                            default: begin t_act <= is_act; t_same <= is_same; end
                        endcase
                        bitpos <= TOP;
                        if (ch == 2'd2) phase <= S_DONE;
                        else            ch    <= ch + 2'd1;
                    end else begin
                        bitpos <= bitpos - 4'd1;
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
