#!/usr/bin/env python3
"""Run every required regression suite, retaining every failure in one report."""
import json,re,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
workflow=(ROOT/'.github/workflows/build-husk-ipa.yml').read_text()
# The explicit suite list is the workflow contract, including the new Duo case.
names=re.findall(r'python3 (tests/translation-layer/[^ ]+\.py) -v',workflow)
if len(names)!=52 or len(set(names))!=52:raise SystemExit('Expected exactly 52 distinct required suites')
results=[];logs=ROOT/'build/logs';logs.mkdir(parents=True,exist_ok=True)
for name in names:
    result=subprocess.run([sys.executable,name,'-v'],cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
    print(result.stdout,flush=True)
    (logs/(Path(name).stem+'.log')).write_text(result.stdout)
    results.append(dict(suite=name,exit_code=result.returncode))
result=subprocess.run(['sh','tests/translation-layer/run_font_paths.sh'],cwd=ROOT)
results.append(dict(suite='font_paths',exit_code=result.returncode))
(logs/'regression-results.json').write_text(json.dumps(results,indent=2)+'\n')
failed=[r['suite']for r in results if r['exit_code']]
print('Failed suites:',failed,flush=True)
raise SystemExit(bool(failed))
