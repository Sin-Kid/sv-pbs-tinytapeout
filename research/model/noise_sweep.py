"""Run the dataset evaluation at several noise levels (needs iverilog + vvp)."""
import json
import shutil
import subprocess
import sys
from pathlib import Path

R = Path(__file__).resolve().parents[1]          # research/
SRC = R.parent / "src"
py = sys.executable
vvp = shutil.which("vvp") or "vvp"
iverilog = shutil.which("iverilog") or "iverilog"

sources = [str(p) for p in sorted(SRC.glob("*.v")) if p.name != "project.v"]
(R / "results").mkdir(exist_ok=True)
ref = [str(p) for p in sorted((R / "reference_rtl").glob("*.v"))]
subprocess.run([iverilog, "-g2012", "-o", str(R / "sim_compare.out"), *sources, *ref,
                str(R / "testbench" / "tb_compare.v")], check=True)

results = []
for noise in (0, 2, 5, 10):
    subprocess.run([py, str(R / "model" / "generate_dataset.py"), "--noise", str(noise), "--seed", "21"], check=True)
    subprocess.run([vvp, "-n", "sim_compare.out"], cwd=R, check=True)
    subprocess.run([py, str(R / "model" / "evaluate.py")], cwd=R, check=True)
    data = json.loads((R / "results" / "aligned_metrics.json").read_text())
    results.append({"noise": noise, "baseline": data["baseline_same_cycles"], "proposed": data["proposed_same_cycles"]})
(R / "results" / "noise_sweep.json").write_text(json.dumps(results, indent=2))
print(json.dumps(results, indent=2))
