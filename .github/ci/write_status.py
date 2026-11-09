"""A bounded, private build receipt for orchestration; never exports environment credentials."""
import os,json,base64,urllib.request,urllib.error
from pathlib import Path
repo=os.environ['GITHUB_REPOSITORY'];phase=os.environ.get('HUSK_STATUS','running')
report={'run_id':int(os.environ['GITHUB_RUN_ID']),'attempt':int(os.environ.get('GITHUB_RUN_ATTEMPT','1')),'runner':os.environ['RUNNER_NAME'],'architecture':os.environ['RUNNER_ARCH'],'status':phase,'source':os.environ.get('HUSK_SOURCE','pending'),'artifact_id':os.environ.get('HUSK_ARTIFACT_ID','')}
url='https://api.github.com/repos/'+repo+'/contents/build-status/current.json'
headers={'Authorization':'Bearer '+os.environ['GITHUB_TOKEN'],'Accept':'application/vnd.github+json'}
body={'message':'[skip ci] Record Mac IPA build '+phase,'content':base64.b64encode(json.dumps(report,indent=2).encode()).decode()}
try:
    with urllib.request.urlopen(urllib.request.Request(url,headers=headers))as r:body['sha']=json.load(r)['sha']
except urllib.error.HTTPError as e:
    if e.code!=404:raise
with urllib.request.urlopen(urllib.request.Request(url,data=json.dumps(body).encode(),headers=headers,method='PUT'))as r:json.load(r)
print('Private build status:',phase)
