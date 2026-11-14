#!/usr/bin/env python3
import os,sys,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
FACADES={
'android/content/Context.java':'''package android.content; public class Context { final java.io.File root; public int broadcasts; public Intent last; public Context(java.io.File r){root=r;} public java.io.File getFilesDir(){return new java.io.File(root,"files");} public java.io.File getCacheDir(){return new java.io.File(root,"cache");} public java.io.File getExternalFilesDir(String type){return new java.io.File(root,"sdcard/Android/data/com.ichi2.anki/files");} public String getPackageName(){return "com.ichi2.anki";} public void sendBroadcast(Intent i){last=i; broadcasts++;} }''',
'husk/Web.java':'''package husk; public class Web { public static java.util.HashMap<Long,String[]> states=new java.util.HashMap<>(); public static String destination; public static String[] headers; public static void downloadStart(long id,String u,String d,String[] h){destination=d;headers=h;states.put(id,new String[]{"1","0","0","-1"});} public static String[] downloadQuery(long id){return states.get(id);} public static boolean downloadRemove(long id){return states.remove(id)!=null;} }''',
}
def run(classes):
 jdk=Path(os.environ['HUSK_JDK'])
 with tempfile.TemporaryDirectory() as td:
  base=Path(td);sources=[]
  for name,content in FACADES.items():
   f=base/name;f.parent.mkdir(parents=True,exist_ok=True);f.write_text(content);sources.append(str(f))
  out=base/'classes';subprocess.run([str(jdk/'bin/javac'),'--release','8','-cp',classes,'-d',str(out),*sources,str(ROOT/'tests/java-framework/DownloadManagerContract.java')],check=True)
  return subprocess.run([str(jdk/'bin/java'),'-cp',str(out)+os.pathsep+classes,'DownloadManagerContract'],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
if __name__=='__main__':
 r=run(sys.argv[1]);print(r.stdout,end='');raise SystemExit(r.returncode)
