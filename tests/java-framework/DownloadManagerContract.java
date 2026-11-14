import android.app.DownloadManager;
import android.database.Cursor;
import android.net.Uri;
import java.io.*;
import java.nio.file.*;
public class DownloadManagerContract {
 static int checks;
 static void check(boolean b,String s){if(!b)throw new AssertionError(s);checks++;}
 public static void main(String[] args)throws Exception{
  File root=Files.createTempDirectory("husk-dl-contract").toFile(); android.content.Context c=new android.content.Context(root);
  DownloadManager manager=new DownloadManager(c);
  DownloadManager.Request request=new DownloadManager.Request(Uri.parse("https://example.test/deck"))
   .setDestinationInExternalFilesDir(c,null,"shared_decks/test.apkg").setTitle("test.apkg").setMimeType("application/octet-stream")
   .addRequestHeader("Cookie","session=example").addRequestHeader("User-Agent","Anki test");
  long id=manager.enqueue(request);check(id>0,"nonzero identity");
  check(husk.Web.destination.endsWith("shared_decks/test.apkg") && husk.Web.headers.length==4,"real request carries destination and headers");
  husk.Web.states.put(id,new String[]{"2","0","3000000000","5000000000"});
  Cursor q=manager.query(new DownloadManager.Query().setFilterById(id));check(q.moveToFirst(),"query has record");
  check(q.getLong(q.getColumnIndex(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR))==3000000000L,"64-bit downloaded bytes");
  check(q.getLong(q.getColumnIndex(DownloadManager.COLUMN_TOTAL_SIZE_BYTES))==5000000000L,"64-bit total");
  check(q.getInt(q.getColumnIndex(DownloadManager.COLUMN_STATUS))==DownloadManager.STATUS_RUNNING,"running query");q.close();
  File file=new File(husk.Web.destination);file.getParentFile().mkdirs();Files.write(file.toPath(),new byte[]{'P','K',3,4});
  husk.Web.states.put(id,new String[]{"8","0","4","4"});
  DownloadManager.huskComplete(id);DownloadManager.huskComplete(id);
  check(c.broadcasts==1 && c.last.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID,0)==id,"completion broadcast exact once with matching id");
  Uri uri=manager.getUriForDownloadedFile(id);check(uri!=null && new File(uri.getPath()).equals(file),"import URI points at file");
  q=manager.query(new DownloadManager.Query().setFilterByStatus(DownloadManager.STATUS_FAILED));check(!q.moveToFirst(),"status filtering");q.close();
  husk.Web.states.put(id,new String[]{"16","429","0","-1"});
  q=manager.query(new DownloadManager.Query().setFilterById(id));q.moveToFirst();check(q.getInt(q.getColumnIndex(DownloadManager.COLUMN_REASON))==429,"HTTP rate limit retained for login prompt");q.close();
  check(manager.getUriForDownloadedFile(id)==null,"failed file not importable");
  check(manager.remove(id)==1 && manager.remove(id)==0,"remove exact once");
  q=manager.query(new DownloadManager.Query().setFilterById(id));check(!q.moveToFirst(),"removed absent");q.close();
  DownloadManager.huskComplete(id);check(c.broadcasts==1,"late completion ignored");
  boolean rejected=false;try{manager.enqueue(new DownloadManager.Request(Uri.parse("https://example.test/")).setDestinationUri(Uri.fromFile(new File(root,"../outside.apkg"))));}catch(SecurityException ex){rejected=true;}
  check(rejected,"destination confined to imported app root");
  rejected=false;try{new DownloadManager.Request(Uri.parse("https://example.test/")).addRequestHeader("Cookie","x\r\nInjected:y");}catch(IllegalArgumentException ex){rejected=true;}
  check(rejected,"header injection rejected");
  System.out.println("DownloadManagerContract: "+checks+" checks passed");
 }
}
