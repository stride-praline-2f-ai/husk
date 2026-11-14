#!/usr/bin/env python3
import os,sys,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
FACADES={
'android/os/Handler.java':'''package android.os; public class Handler { public static Message sent; public Handler(){} public Handler(Looper l){} public boolean sendMessage(Message m){sent=m;return true;} public boolean post(Runnable r){return true;} public boolean postDelayed(Runnable r,long delay){return true;} }''',
'husk/Web.java':'''package husk; public class Web { public static java.util.ArrayList<String> calls=new java.util.ArrayList<>(); static boolean js; public static void settings(int id,boolean j,String ua,int z,boolean g){js=j; calls.add("settings:"+j);} public static void load(int id,String u,String[] h,byte[] b){calls.add("load:"+js);} }''',
}
def run(classes):
 jdk=Path(os.environ['HUSK_JDK'])
 with tempfile.TemporaryDirectory() as td:
  base=Path(td);sources=[]
  for name,content in FACADES.items():
   f=base/name;f.parent.mkdir(parents=True,exist_ok=True);f.write_text(content);sources.append(str(f))
  out=base/'classes'
  subprocess.run([str(jdk/'bin/javac'),'--release','8','-cp',classes,'-d',str(out),*sources,str(ROOT/'tests/java-framework/AnkiInteractionContract.java')],check=True)
  return subprocess.run([str(jdk/'bin/java'),'-cp',str(out)+os.pathsep+classes,'AnkiInteractionContract'],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
if __name__=='__main__':
 r=run(sys.argv[1]);print(r.stdout,end='');raise SystemExit(r.returncode)
