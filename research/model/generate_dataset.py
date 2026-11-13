import csv,random,argparse
from pathlib import Path
P=argparse.ArgumentParser();P.add_argument("--noise",type=int,default=2);P.add_argument("--seed",type=int,default=21);a=P.parse_args()
R=Path(__file__).resolve().parents[1];O=R/"dataset"/"vectors.csv";random.seed(a.seed);rows=[]
def add(n,v,i,t,label=0,code=0):
 for _ in range(n):
  rows.append((max(0,v+random.randint(-a.noise,a.noise)),max(0,i+random.randint(-a.noise,a.noise)),max(0,t+random.randint(-a.noise,a.noise)),label,code))
add(30,3700,100,300,0,0)
# thermal ramp marked as fault from onset; threshold crossing comes later
for k in range(24): rows.append((3700+random.randint(-a.noise,a.noise),110,300+5*k,1,7))
add(12,3700,110,500,1,3)
add(18,4650,100,320,1,1)
add(18,3700,1200,320,1,2)
add(18,3700,100,820,1,3)
# sensor stuck: temperature fixed while V/I move; label as sensor fault, not battery failure
for k in range(20): rows.append((3600+8*k,100+3*k,330,1,6))
add(30,3700,100,300,0,0)
O.parent.mkdir(exist_ok=True)
with O.open("w",newline="") as f:
 w=csv.writer(f);w.writerow(["voltage","current","temperature","label_fault","label_code"]);w.writerows(rows)
print(f"Wrote {len(rows)} shared labelled samples to {O}; noise={a.noise}, seed={a.seed}")
print("All labels are synthetic scenario ground truth.")
