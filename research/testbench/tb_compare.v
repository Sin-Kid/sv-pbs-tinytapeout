`timescale 1ns/1ps
`default_nettype none
// Dataset evaluation: proposed controller = taped-out SV-PBS core;
// baseline controller = original V2.1 core (reference_rtl), which is not on the chip.
// Reads research/dataset/vectors.csv, writes research/results/aligned_results.csv.
// Outputs are recorded after each sample has fully propagated (BUSY low),
// so filtered values and controller decisions belong to the same sample.
module tb_compare;
  reg clk = 0, rst_n = 0, sample_valid = 0;
  reg wr_en = 0; reg [2:0] wr_idx = 0; reg [7:0] wr_data = 0;
  wire [15:0] fv, fi; wire [11:0] ft;
  wire [1:0] bs, ps; wire bd, bi, pd, pi, sd, pr, busy; wire [2:0] fc;
  integer fd, od, rc, idx, v, i, t, lf, lc; reg [8*128-1:0] header;

  reg [15:0] rv, ri; reg [11:0] rt;
  wire [15:0] rfv, rfi; wire [11:0] rft; wire [1:0] rps; wire rpd, rpi, rsd, rpr; wire [2:0] rfc;
  sv_pbs_core dut(.clk(clk), .rst_n(rst_n), .wr_en(wr_en), .wr_idx(wr_idx), .wr_data(wr_data),
    .sample_valid(sample_valid), .filtered_voltage(fv), .filtered_current(fi),
    .filtered_temperature(ft), .proposed_state(ps),
    .proposed_derate(pd), .proposed_isolate(pi),
    .sensor_degraded(sd), .predicted_risk(pr), .sensor_fault_code(fc), .busy(busy));
  ref_sv_pbs_core ref_core(clk, rst_n, sample_valid, rv, ri, rt, rfv, rfi, rft,
    bs, rps, bd, bi, rpd, rpi, rsd, rpr, rfc);
  always #5 clk = ~clk;

  task wbyte(input [2:0] k, input [7:0] d);
    begin @(negedge clk); wr_en = 1; wr_idx = k; wr_data = d; @(negedge clk); wr_en = 0; end
  endtask

  initial begin
    od = $fopen("results/aligned_results.csv", "w");
    $fdisplay(od, "index,v_in,i_in,t_in,label_fault,label_code,fv,fi,ft,baseline_state,baseline_derate,baseline_isolate,proposed_state,proposed_derate,proposed_isolate,sensor_degraded,predicted_risk,sensor_fault_code");
    repeat (3) @(negedge clk); rst_n = 1;
    fd = $fopen("dataset/vectors.csv", "r");
    if (fd == 0) begin $display("ERROR: missing dataset/vectors.csv"); $finish; end
    rc = $fscanf(fd, "%s\n", header); idx = 0;
    while (!$feof(fd)) begin
      rc = $fscanf(fd, "%d,%d,%d,%d,%d\n", v, i, t, lf, lc);
      if (rc == 5) begin
        rv = v; ri = i; rt = t;
        wbyte(0, v[15:8]); wbyte(1, v[7:0]); wbyte(2, i[15:8]); wbyte(3, i[7:0]);
        wbyte(4, t[11:4]); wbyte(5, {4'h0, t[3:0]});
        @(negedge clk); sample_valid = 1; @(negedge clk); sample_valid = 0;
        @(negedge clk); while (busy) @(negedge clk);
        $fdisplay(od, "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
          idx, v, i, t, lf, lc, fv, fi, ft, bs, bd, bi, ps, pd, pi, sd, pr, fc);
        idx = idx + 1;
      end
    end
    $fclose(fd); $fclose(od);
    $display("Dataset evaluation complete: %0d samples", idx); $finish;
  end
endmodule
