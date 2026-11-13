import csv,json,sys
from pathlib import Path
R=Path(__file__).resolve().parents[1];p=R/"results"/"aligned_results.csv"
if not p.exists():raise SystemExit("Run Verilog testbench first.")
rows=list(csv.DictReader(p.open()))
def metrics(pred,truth):
 tp=fp=tn=fn=0
 for x,y in zip(pred,truth):
  if x and y:tp+=1
  elif x and not y:fp+=1
  elif not x and not y:tn+=1
  else:fn+=1
 prec=tp/(tp+fp) if tp+fp else 0;rec=tp/(tp+fn) if tp+fn else 0
 spec=tn/(tn+fp) if tn+fp else 0;f1=2*prec*rec/(prec+rec) if prec+rec else 0
 return {"TP":tp,"FP":fp,"TN":tn,"FN":fn,"precision":round(prec,4),"recall":round(rec,4),
         "specificity":round(spec,4),"F1":round(f1,4),"false_alarm_rate":round(fp/(fp+tn),4) if fp+tn else 0}
truth=[int(x["label_fault"])!=0 for x in rows]
base=[int(x["baseline_state"])!=0 for x in rows]
prop=[int(x["proposed_state"])!=0 for x in rows]
out={"samples":len(rows),"baseline_same_cycles":metrics(base,truth),
     "proposed_same_cycles":metrics(prop,truth),
     "sensor_degraded_samples":sum(int(x["sensor_degraded"]) for x in rows),
     "prediction_samples":sum(int(x["predicted_risk"]) for x in rows),
     "baseline_isolation_samples":sum(int(x["baseline_isolate"]) for x in rows),
     "proposed_isolation_samples":sum(int(x["proposed_isolate"]) for x in rows)}
# Lead time: first predictor assertion after thermal anomaly label 7 begins, before first critical-temp sample.
onset=next((i for i,x in enumerate(rows) if int(x["label_code"])==7),None)
crit=next((i for i,x in enumerate(rows) if int(x["label_code"])==3 and int(x["t_in"])>=500),None)
pred=next((i for i,x in enumerate(rows) if int(x["predicted_risk"])==1 and onset is not None and i>=onset),None)
out["thermal_prediction_lead_samples"]=(crit-pred if pred is not None and crit is not None and pred<crit else None)
(R/"results"/"aligned_metrics.json").write_text(json.dumps(out,indent=2));print(json.dumps(out,indent=2))
print("Same input vectors, same cycle index, same filtered sensor streams. Metrics remain synthetic.")
