`timescale 1ns/1ps
`default_nettype none
// Equivalence check: original SV-PBS core (ref_sv_pbs_core) vs area-optimised
// core (sv_pbs_core). Both receive identical sample streams; after each sample
// has fully propagated, every output must match bit-for-bit.
module tb_equiv;
  reg clk = 0, rst_n = 0, sv_r = 0, sv_n = 0;
  reg [15:0] v, i; reg [11:0] t;
  wire [15:0] rfv, rfi, nfv, nfi; wire [11:0] rft, nft;
  wire [1:0] rbs, rps, nbs, nps; wire rbd, rbi, rpd, rpi, rsd, rpr, nbd, nbi, npd, npi, nsd, npr, nbusy;
  wire [2:0] rfc, nfc;

  ref_sv_pbs_core R(clk, rst_n, sv_r, v, i, t, rfv, rfi, rft, rbs, rps, rbd, rbi, rpd, rpi, rsd, rpr, rfc);
  reg wr_en = 0; reg [2:0] wr_idx = 0; reg [7:0] wr_data = 0;
  sv_pbs_core     N(.clk(clk), .rst_n(rst_n), .wr_en(wr_en), .wr_idx(wr_idx), .wr_data(wr_data),
                    .sample_valid(sv_n), .filtered_voltage(nfv), .filtered_current(nfi),
                    .filtered_temperature(nft), .baseline_state(nbs), .proposed_state(nps),
                    .baseline_derate(nbd), .baseline_isolate(nbi), .proposed_derate(npd),
                    .proposed_isolate(npi), .sensor_degraded(nsd), .predicted_risk(npr),
                    .sensor_fault_code(nfc), .busy(nbusy));
  always #5 clk = ~clk;

  integer n = 0, errors = 0, mode, k, seed;
  integer cv = 3700, ci = 200, ct = 300;
  integer s_crit = 0, s_warn = 0, s_deg = 0, s_risk = 0, s_rec = 0;
  reg [1:0] last_ps;

  task wbyte(input [2:0] idx, input [7:0] d);
    begin @(negedge clk); wr_en = 1; wr_idx = idx; wr_data = d; @(negedge clk); wr_en = 0; end
  endtask

  task step;
    begin
      wbyte(0, v[15:8]); wbyte(1, v[7:0]); wbyte(2, i[15:8]); wbyte(3, i[7:0]);
      wbyte(4, t[11:4]); wbyte(5, {4'h0, t[3:0]});
      @(negedge clk); sv_r = 1; sv_n = 1;
      @(negedge clk); sv_r = 0; sv_n = 0;
      @(negedge clk);
      while (nbusy) @(negedge clk);
      repeat (2) @(negedge clk);
      if ({rfv, rfi, rft, rbs, rps, rbd, rbi, rpd, rpi, rsd, rpr, rfc} !==
          {nfv, nfi, nft, nbs, nps, nbd, nbi, npd, npi, nsd, npr, nfc}) begin
        errors = errors + 1;
        if (errors < 10)
          $display("MISMATCH sample %0d v=%0d i=%0d t=%0d | ref fv=%0d fi=%0d ft=%0d ps=%0d bs=%0d sd=%b fc=%0d pr=%b | new fv=%0d fi=%0d ft=%0d ps=%0d bs=%0d sd=%b fc=%0d pr=%b",
            n, v, i, t, rfv, rfi, rft, rps, rbs, rsd, rfc, rpr, nfv, nfi, nft, nps, nbs, nsd, nfc, npr);
      end
      if (rps == 2) s_crit = s_crit + 1;
      if (rps == 1) s_warn = s_warn + 1;
      if (rps == 3) s_deg  = s_deg + 1;
      if (rpr)      s_risk = s_risk + 1;
      if (last_ps != 0 && rps == 0) s_rec = s_rec + 1;
      last_ps = rps;
      n = n + 1;
    end
  endtask

  function integer clampi(input integer x, input integer lo, input integer hi);
    clampi = x < lo ? lo : (x > hi ? hi : x);
  endfunction

  initial begin
    if (!$value$plusargs("seed=%d", seed)) seed = 1;
    v = 3700; i = 200; t = 300; last_ps = 0;
    repeat (3) @(negedge clk); rst_n = 1;

    // 1) Directed scenarios (mirrors model/generate_dataset.py)
    repeat (30) begin v = 3700 + $random(seed) % 3; i = 100; t = 300; step; end
    for (k = 0; k < 24; k = k + 1) begin v = 3700; i = 110; t = 300 + 5 * k; step; end
    repeat (12) begin v = 3700; i = 110; t = 500; step; end
    repeat (18) begin v = 4650; i = 100; t = 320; step; end
    repeat (18) begin v = 3700; i = 1200; t = 320; step; end
    repeat (18) begin v = 3700; i = 100; t = 820; step; end
    for (k = 0; k < 20; k = k + 1) begin v = 3600 + 8 * k; i = 100 + 3 * k; t = 330; step; end
    repeat (30) begin v = 3700; i = 100; t = 300; step; end
    // stuck voltage / current with others moving
    for (k = 0; k < 15; k = k + 1) begin v = 3700; i = 100 + 7 * k; t = 300; step; end
    for (k = 0; k < 15; k = k + 1) begin v = 3500 + 9 * k; i = 150; t = 300; step; end
    // tolerance boundaries: one channel stuck, another ramping by exactly tol / tol+1
    for (mode = 0; mode < 12; mode = mode + 1) begin
      for (k = 0; k < 16; k = k + 1) begin
        case (mode)
          0: begin v = 3700; i = 100 + 5 * k; t = 300; end
          1: begin v = 3700; i = 100 + 6 * k; t = 300; end
          2: begin v = 3700; i = 300 - 5 * k; t = 300; end
          3: begin v = 3700; i = 300 - 6 * k; t = 300; end
          4: begin v = 3500 + 5 * k; i = 150; t = 300; end
          5: begin v = 3500 + 6 * k; i = 150; t = 300; end
          6: begin v = 3900 - 6 * k; i = 150; t = 300; end
          7: begin v = 3700; i = 150; t = 300 + 2 * k; end
          8: begin v = 3700; i = 150; t = 300 + 3 * k; end
          9: begin v = 3700; i = 150; t = 360 - 3 * k; end
          10: begin v = 3700 + 6 * k; i = 150 + 6 * k; t = 300; end
          default: begin v = 3700; i = 150 + 6 * k; t = 300 + 3 * k; end
        endcase
        step;
      end
      repeat (4) begin v = 3700; i = 150; t = 300; step; end
    end
    // extremes and wrap-around corners
    v = 16'hFFFF; i = 16'hFFFF; t = 12'hFFF; step; step; step;
    v = 0; i = 0; t = 0; step; step; step;
    v = 16'hFFFC; i = 16'hFFFC; t = 12'hFFE; step; v = 3700; i = 200; t = 300; step; step; step;

    // reset mid-run, then a channel stuck at exactly 0 from the first sample
    for (mode = 0; mode < 3; mode = mode + 1) begin
      @(negedge clk); rst_n = 0; repeat (2) @(negedge clk); rst_n = 1;
      for (k = 0; k < 14; k = k + 1) begin
        case (mode)
          0: begin v = 3000 + 9 * k; i = 0;           t = 300 + 3 * k; end
          1: begin v = 3000 + 9 * k; i = 100 + 7 * k; t = 0;           end
          default: begin v = 3000;   i = 0;           t = 0;           end
        endcase
        step;
      end
    end

    // 2) Random walks with occasional jumps, stuck channels and resets of trend
    for (k = 0; k < 4000; k = k + 1) begin
      mode = $random(seed) & 31;
      cv = clampi(cv + ($random(seed) % 40), 2300, 5200);
      ci = clampi(ci + ($random(seed) % 30), 0, 1300);
      ct = clampi(ct + ($random(seed) % 8) + ((mode < 6) ? 6 : 0), 200, 900);
      if (mode == 31) begin cv = 3700; ci = 150; ct = 300; end
      v = cv; i = ci; t = ct;
      if (mode == 30) begin v = $random(seed); i = $random(seed); t = $random(seed); end
      step;
    end

    // 3) Fully random values
    for (k = 0; k < 1000; k = k + 1) begin
      v = $random(seed); i = $random(seed); t = $random(seed); step;
    end

    $display("Samples=%0d  mismatches=%0d  | coverage: critical=%0d warning=%0d degraded=%0d risk=%0d recoveries=%0d",
             n, errors, s_crit, s_warn, s_deg, s_risk, s_rec);
    if (errors == 0) $display("EQUIVALENT");
    $finish;
  end
endmodule
