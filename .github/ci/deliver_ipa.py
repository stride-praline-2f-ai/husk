"""Deliver verified existing IPA bytes through a private draft release; never rebuild or publish it."""
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import time
import urllib.error
import urllib.parse
import urllib.request

repo=os.environ['GITHUB_REPOSITORY']
token=os.environ['GITHUB_TOKEN']
api='https://api.github.com/repos/'+repo
headers={'Authorization':'Bearer '+token,'Accept':'application/vnd.github+json','X-GitHub-Api-Version':'2022-11-28'}
def request(url,body=None,method=None,extra=None):
    h=dict(headers)
    if extra:h.update(extra)
    if body is not None and not isinstance(body,bytes):
        body=json.dumps(body).encode();h['Content-Type']='application/json'
    with urllib.request.urlopen(urllib.request.Request(url,data=body,headers=h,method=method),timeout=180)as r:
        return json.load(r)

q=json.loads(Path('delivery/request.json').read_text())
assert request(api)['private'] is True,'Delivery storage must remain private'
assert re.fullmatch(r'[A-Za-z0-9._-]+\.ipa',q['file_name'])
assert re.fullmatch(r'[0-9a-f]{64}',q['sha256'])
files=list(Path('delivery-package').rglob('*.ipa'));assert len(files)==1,files
data=files[0].read_bytes()
assert len(data)==q['bytes'] and hashlib.sha256(data).hexdigest()==q['sha256'],'IPA bytes do not match verified build'
tag='husk-build'+str(int(q['build']))+'-private-download'
releases=request(api+'/releases?per_page=100')
release=next((r for r in releases if r['tag_name']==tag),None)
if release is None:
    release=request(api+'/releases',{'tag_name':tag,'target_commitish':q['source'],'name':'Husk build '+str(q['build'])+' private download','body':'Delivery of already verified IPA bytes. Draft only; no public release or app rebuild. SHA256 '+q['sha256'],'draft':True,'prerelease':False},'POST')
assert release['draft'] is True,'Do not replace a published release'
assets=request(api+'/releases/'+str(release['id'])+'/assets')
asset=next((a for a in assets if a['name']==q['file_name']),None)
if asset is None:
    upload=release['upload_url'].split('{')[0]+'?'+urllib.parse.urlencode({'name':q['file_name']})
    asset=request(upload,data,'POST',{'Content-Type':'application/octet-stream'})
assert asset['size']==q['bytes'] and asset.get('digest')=='sha256:'+q['sha256'],'Uploaded asset identity mismatch'

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self,req,fp,code,msg,h,newurl):return None

opener=urllib.request.build_opener(NoRedirect)
url=asset['url']+'?download=1&delivery='+str(time.time_ns())
h=dict(headers);h['Accept']='application/octet-stream'
try:
    with opener.open(urllib.request.Request(url,headers=h),timeout=60):
        raise RuntimeError('Expected a signed asset redirect')
except urllib.error.HTTPError as e:
    if e.code not in (301,302,303,307,308):raise
    direct=e.headers['Location']
parsed=urllib.parse.urlsplit(direct)
assert parsed.scheme=='https' and parsed.hostname in ['release-assets.githubusercontent.com','objects.githubusercontent.com']
# Check the bearer download without forwarding any repository credentials.
with urllib.request.urlopen(urllib.request.Request(direct,method='HEAD'),timeout=60)as r:
    assert int(r.headers['Content-Length'])==q['bytes'],'Direct URL size mismatch'
receipt={'build':q['build'],'source':q['source'],'file_name':q['file_name'],'bytes':q['bytes'],'sha256':q['sha256'],'asset_id':asset['id'],'draft_release_id':release['id'],'download_url':direct,'created_at':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),'workflow_run_id':int(os.environ['GITHUB_RUN_ID'])}
path=api+'/contents/delivery/latest.json'
body={'message':'Record temporary direct IPA download [skip ci]','content':base64.b64encode((json.dumps(receipt,indent=2)+'\n').encode()).decode()}
try:body['sha']=request(path)['sha']
except urllib.error.HTTPError as e:
    if e.code!=404:raise
request(path,body,'PUT')
print('Direct IPA delivery verified and recorded; no app rebuild, public release, or token disclosure')
