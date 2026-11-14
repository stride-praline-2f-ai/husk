import android.os.*;
import android.webkit.*;
import java.lang.reflect.*;
import java.util.*;

/** Real framework methods, with native transport/queue endpoints replaced by recording facades. */
public class AnkiInteractionContract {
    static int checks;
    static void check(boolean b,String m) { if(!b)throw new AssertionError(m); checks++; }
    static Object allocate(Class<?> c) throws Exception {
        Class<?> uc=Class.forName("sun.misc.Unsafe"); Field f=uc.getDeclaredField("theUnsafe"); f.setAccessible(true);
        return uc.getMethod("allocateInstance",Class.class).invoke(f.get(null),c);
    }
    static void field(Object o,String key,Object v) throws Exception { Field f=o.getClass().getDeclaredField(key); f.setAccessible(true); f.set(o,v); }
    public static void main(String[] args) throws Exception {
        Handler h=new Handler(); Message original=Message.obtain(h,7,3,4,"discard");
        original.getData().putString("key","old"); original.setAsynchronous(true); original.when=123;
        Runnable callback=()->{}; original.setCallback(callback);
        Message clone=Message.obtain(original);
        check(clone!=null && clone!=original,"AppCompat obtains a distinct button message");
        check(clone.target==h && clone.what==7 && clone.arg1==3 && clone.arg2==4 && clone.obj.equals("discard"),"button target and arguments preserved");
        check(clone.getCallback()==callback && clone.isAsynchronous(),"callback/async copied");
        clone.getData().putString("key","new"); check(original.getData().getString("key").equals("old"),"bundle independently copied");
        check(clone.getWhen()==0 && original.getWhen()==123,"clone is not already scheduled");
        clone.sendToTarget(); check(Handler.sent==clone,"button clone reaches handler");
        Handler h2=new Handler(); clone.setTarget(h2); check(clone.getTarget()==h2,"setTarget works");
        clone.setWhat(8); check(clone.what==8,"setWhat works");
        check(Message.obtain().peekData()==null,"peek does not allocate bundle");
        WebView web=(WebView)allocate(WebView.class);
        Class<?> settingsClass=Class.forName("android.webkit.HuskWebSettings");
        Constructor<?> ctor=settingsClass.getDeclaredConstructor(Runnable.class); ctor.setAccessible(true);
        final int[] deferred={0}; WebSettings settings=(WebSettings)ctor.newInstance((Runnable)()->deferred[0]++);
        field(web,"mSettings",settings); field(web,"mId",27);
        Method load=WebView.class.getDeclaredMethod("hostLoad",String.class,String[].class,byte[].class); load.setAccessible(true);
        load.invoke(web,"https://example.test/first",null,null);
        check(husk.Web.calls.equals(Arrays.asList("settings:false","load:false")),"default policy precedes navigation");
        settings.setJavaScriptEnabled(true); // Anki does this immediately before loading a module-only page
        load.invoke(web,"https://example.test/shared/decks/",null,null);
        check(deferred[0]>0 && husk.Web.calls.get(2).equals("settings:true") && husk.Web.calls.get(3).equals("load:true"),"pending settings cannot be overtaken by page load");
        load.invoke(web,"https://example.test/repeated",null,null);
        check(husk.Web.calls.size()==5 && husk.Web.calls.get(4).equals("load:true"),"identical settings not resent");
        final String[] download={null}; final long[] length={0};
        web.setDownloadListener((url,ua,disposition,mime,size)->{download[0]=url+"|"+disposition+"|"+mime; length[0]=size;});
        web.huskEvent(new String[]{"d","27","https://example.test/deck","attachment; filename=deck.apkg","application/octet-stream","3000000000"});
        check(download[0].contains("deck.apkg") && length[0]==3000000000L,"download response reaches actual listener with 64-bit size");
        field(web,"mDestroyed",true); load.invoke(web,"https://example.test/late",null,null);
        check(husk.Web.calls.size()==5,"destroyed view cannot start late navigation");
        System.out.println("AnkiInteractionContract: "+checks+" checks passed");
    }
}
