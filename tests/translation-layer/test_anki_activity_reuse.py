#!/usr/bin/env python3
"""Execute AppRunner's actual unique-activity reuse against a lifecycle/stack facade."""
import os,shutil,subprocess,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def extracted(source,name):
 start=source.index('    private static boolean '+name+'(');opening=source.index('{',start);depth=1;end=opening+1
 while depth:depth+=(source[end]=='{')-(source[end]=='}');end+=1
 return source[start:end]
PROGRAM=r'''
import java.util.ArrayList;
public class ReuseContract {
 static class Component {String name;Component(String n){name=n;}String getClassName(){return name;}}
 static class Intent {Component c;Intent(String n){c=new Component(n);}Component getComponent(){return c;}}
 static class Window {boolean floating;boolean isFloating(){return floating;}}
 static class Activity {
  String name;boolean finishing,resumed,visible;int created=1,starts,resumes,pauses,stops,restarts,intents,destroys;Window window=new Window();
  Activity(String n){name=n;}boolean isFinishing(){return finishing;}boolean isResumedHusk(){return resumed;}boolean huskVisible(){return visible;}
  void huskPause(){pauses++;resumed=false;}void huskStop(){stops++;visible=false;}void huskRestart(){restarts++;}void huskStart(){starts++;visible=true;}void huskResume(){resumes++;resumed=true;}
  void huskNewIntent(Intent i){assert name.equals(i.getComponent().getClassName());intents++;}Window getWindow(){return window;}
 }
 static ArrayList<Activity> sStack=new ArrayList<>();
 static Activity top(){return sStack.isEmpty()?null:sStack.get(sStack.size()-1);}static String startedAs(Activity a){return a.name;}
 static void finishNow(Activity a,boolean resume){assert !resume;a.destroys++;a.finishing=true;sStack.remove(a);}
 // PRODUCTION_REUSE
 public static void main(String[]args){
  Activity deck=new Activity("Deck"),crash=new Activity("Crash"),editor=new Activity("Editor");
  sStack.add(deck);sStack.add(crash);crash.resumed=crash.visible=true;
  assert reuseUniqueActivity(new Intent("Crash"),3);assert reuseUniqueActivity(new Intent("Crash"),3);
  assert sStack.size()==2&&top()==crash&&crash.created==1&&crash.intents==2&&crash.pauses==0&&crash.starts==0;
  crash.resumed=crash.visible=false;sStack.add(editor);editor.resumed=editor.visible=true;
  assert reuseUniqueActivity(new Intent("Crash"),3);
  assert sStack.size()==3&&sStack.get(1)==editor&&top()==crash&&editor.destroys==0&&editor.pauses==1&&editor.stops==1;
  assert crash.intents==3&&crash.restarts==1&&crash.starts==1&&crash.resumes==1;
  sStack.clear();sStack.add(deck);sStack.add(crash);sStack.add(editor);crash.resumed=false;crash.visible=false;editor.finishing=false;
  assert reuseUniqueActivity(new Intent("Crash"),2);assert sStack.size()==2&&top()==crash&&editor.destroys==1&&deck.destroys==0;
  for(int mode:new int[]{0,1,4,-1})assert !reuseUniqueActivity(new Intent("Crash"),mode);
  crash.finishing=true;assert !reuseUniqueActivity(new Intent("Crash"),3);
  assert !reuseUniqueActivity(new Intent("Missing"),3);
  System.out.println("UniqueActivityContract: singleInstance duplicates/reorder, singleTask clear-above, ordinary/finishing/missing guards passed");
 }
}
'''
class ActivityReuse(unittest.TestCase):
 def test_actual_unique_activity_lifecycle_and_existing_screen_preservation(self):
  java=shutil.which('java');javac=shutil.which('javac')
  self.assertTrue(java and javac, 'JDK required; run after Java tool setup')
  source=(ROOT/'src/java-framework/src/husk/AppRunner.java').read_text()
  self.assertIn('if (reuseUniqueActivity(intent, c.launchMode)) return;',source)
  program=PROGRAM.replace('// PRODUCTION_REUSE',extracted(source,'reuseUniqueActivity'))
  with tempfile.TemporaryDirectory()as d:
   p=Path(d);(p/'ReuseContract.java').write_text(program)
   c=subprocess.run([javac,'-d',d,str(p/'ReuseContract.java')],capture_output=True,text=True);self.assertEqual(c.returncode,0,c.stdout+c.stderr)
   r=subprocess.run([java,'-ea','-cp',d,'ReuseContract'],capture_output=True,text=True,timeout=20);self.assertEqual(r.returncode,0,r.stdout+r.stderr);print(r.stdout.strip())
if __name__=='__main__':unittest.main(verbosity=2)
