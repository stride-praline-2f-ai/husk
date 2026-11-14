#!/usr/bin/env python3
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT=Path(__file__).resolve().parents[2]
def run(classes):
    jdk=Path(os.environ['HUSK_JDK'])
    with tempfile.TemporaryDirectory() as d:
        p=Path(d); sources=[]
        facades={
            'android/os/Looper.java':'package android.os; public class Looper { private static final Looper MAIN=new Looper(); public static Looper getMainLooper(){return MAIN;} public static Looper myLooper(){return MAIN;} }',
            'android/os/Handler.java':'package android.os; public class Handler { public Handler(Looper l){} public boolean post(Runnable r){r.run();return true;} }',
        }
        for name,content in facades.items():
            f=p/name;f.parent.mkdir(parents=True,exist_ok=True);f.write_text(content);sources.append(str(f))
        out=p/'classes'
        subprocess.run([str(jdk/'bin/javac'),'--release','8','-cp',classes,'-d',str(out),*sources,str(ROOT/'tests/java-framework/StoragePathContract.java')],check=True)
        return subprocess.run([str(jdk/'bin/java'),'-cp',str(out)+os.pathsep+classes,'android.content.StoragePathContract'],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
if __name__=='__main__':
    r=run(sys.argv[1]);print(r.stdout,end='');raise SystemExit(r.returncode)
