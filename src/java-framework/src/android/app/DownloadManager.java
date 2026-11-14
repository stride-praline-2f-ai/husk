/** Android download queries/completion backed by host NSURLSession disk streaming. */
package android.app;

@SuppressWarnings({"unchecked", "rawtypes", "deprecation"})
public class DownloadManager {
    private final java.util.HashMap<String, Object> huskProps = new java.util.HashMap<>();
    public static final java.lang.String ACTION_DOWNLOAD_COMPLETE = "android.intent.action.DOWNLOAD_COMPLETE";
    public static final java.lang.String ACTION_DOWNLOAD_COMPLETED = "android.intent.action.DOWNLOAD_COMPLETED";
    public static final java.lang.String ACTION_NOTIFICATION_CLICKED = "android.intent.action.DOWNLOAD_NOTIFICATION_CLICKED";
    public static final java.lang.String ACTION_VIEW_DOWNLOADS = "android.intent.action.VIEW_DOWNLOADS";
    public static final java.lang.String COLUMN_ALLOW_WRITE = "allow_write";
    public static final java.lang.String COLUMN_BYTES_DOWNLOADED_SO_FAR = "bytes_so_far";
    public static final java.lang.String COLUMN_DESCRIPTION = "description";
    public static final java.lang.String COLUMN_DESTINATION = "destination";
    public static final java.lang.String COLUMN_FILE_NAME_HINT = "hint";
    public static final java.lang.String COLUMN_ID = "_id";
    public static final java.lang.String COLUMN_LAST_MODIFIED_TIMESTAMP = "last_modified_timestamp";
    public static final java.lang.String COLUMN_LOCAL_FILENAME = "local_filename";
    public static final java.lang.String COLUMN_LOCAL_URI = "local_uri";
    public static final java.lang.String COLUMN_MEDIAPROVIDER_URI = "mediaprovider_uri";
    public static final java.lang.String COLUMN_MEDIASTORE_URI = "mediastore_uri";
    public static final java.lang.String COLUMN_MEDIA_TYPE = "media_type";
    public static final java.lang.String COLUMN_REASON = "reason";
    public static final java.lang.String COLUMN_STATUS = "status";
    public static final java.lang.String COLUMN_TITLE = "title";
    public static final java.lang.String COLUMN_TOTAL_SIZE_BYTES = "total_size";
    public static final java.lang.String COLUMN_URI = "uri";
    public static final int ERROR_BLOCKED = 1010;
    public static final int ERROR_CANNOT_RESUME = 1008;
    public static final int ERROR_DEVICE_NOT_FOUND = 1007;
    public static final int ERROR_FILE_ALREADY_EXISTS = 1009;
    public static final int ERROR_FILE_ERROR = 1001;
    public static final int ERROR_HTTP_DATA_ERROR = 1004;
    public static final int ERROR_INSUFFICIENT_SPACE = 1006;
    public static final int ERROR_TOO_MANY_REDIRECTS = 1005;
    public static final int ERROR_UNHANDLED_HTTP_CODE = 1002;
    public static final int ERROR_UNKNOWN = 1000;
    public static final java.lang.String EXTRA_DOWNLOAD_ID = "extra_download_id";
    public static final java.lang.String EXTRA_NOTIFICATION_CLICK_DOWNLOAD_IDS = "extra_click_download_ids";
    public static final java.lang.String INTENT_EXTRAS_SORT_BY_SIZE = "android.app.DownloadManager.extra_sortBySize";
    public static final int PAUSED_MANUAL = 5;
    public static final int PAUSED_QUEUED_FOR_WIFI = 3;
    public static final int PAUSED_UNKNOWN = 4;
    public static final int PAUSED_WAITING_FOR_NETWORK = 2;
    public static final int PAUSED_WAITING_TO_RETRY = 1;
    public static final int STATUS_FAILED = 16;
    public static final int STATUS_PAUSED = 4;
    public static final int STATUS_PENDING = 1;
    public static final int STATUS_RUNNING = 2;
    public static final int STATUS_SUCCESSFUL = 8;
    public static java.lang.String[] UNDERLYING_COLUMNS;
    private final android.content.Context context;
    private static long nextId=System.currentTimeMillis();
    private static final java.util.LinkedHashMap<Long,Entry> entries=new java.util.LinkedHashMap<>();
    private static final class Entry {
        long id; Request request; java.io.File file; android.content.Context context; boolean notified;
    }
    public DownloadManager(android.content.Context p0) { context=p0==null?husk.ContextImpl.app():p0; }
    private static Entry entry(long id) { synchronized(entries) { return entries.get(id); } }
    public static void huskComplete(long id) {
        Entry e=entry(id); if (e==null || e.notified) return;
        e.notified=true;
        e.context.sendBroadcast(new android.content.Intent(ACTION_DOWNLOAD_COMPLETE).setPackage(e.context.getPackageName()).putExtra(EXTRA_DOWNLOAD_ID,id));
    }
    private static java.io.File safeDestination(android.content.Context c, android.net.Uri uri) {
        try {
            if (uri==null || !"file".equals(uri.getScheme())) throw new SecurityException("Download requires an app-local file destination");
            java.io.File file=new java.io.File(uri.getPath()).getCanonicalFile();
            String root=c.getFilesDir().getCanonicalFile().getParent()+java.io.File.separator;
            if (!file.getPath().startsWith(root)) throw new SecurityException("Destination outside imported app data");
            return file;
        } catch (java.io.IOException ex) { throw new SecurityException(ex); }
    }
    public static long getActiveNetworkWarningBytes(android.content.Context p0) { return 0L; }
    public static java.lang.Long getMaxBytesOverMobile(android.content.Context p0) { return null; }
    public static java.lang.Long getRecommendedMaxBytesOverMobile(android.content.Context p0) { return null; }
    public static boolean isActiveNetworkExpensive(android.content.Context p0) { return false; }
    public long addCompletedDownload(java.lang.String p0, java.lang.String p1, boolean p2, java.lang.String p3, java.lang.String p4, long p5, boolean p6) { return 0L; }
    public long addCompletedDownload(java.lang.String p0, java.lang.String p1, boolean p2, java.lang.String p3, java.lang.String p4, long p5, boolean p6, android.net.Uri p7, android.net.Uri p8) { return 0L; }
    public long addCompletedDownload(java.lang.String p0, java.lang.String p1, boolean p2, java.lang.String p3, java.lang.String p4, long p5, boolean p6, boolean p7) { return 0L; }
    public long addCompletedDownload(java.lang.String p0, java.lang.String p1, boolean p2, java.lang.String p3, java.lang.String p4, long p5, boolean p6, boolean p7, android.net.Uri p8, android.net.Uri p9) { return 0L; }
    public long enqueue(android.app.DownloadManager.Request p0) {
        if (p0==null) throw new IllegalArgumentException("null request");
        Entry e=new Entry(); e.context=context; e.request=p0;
        android.net.Uri dest=(android.net.Uri)p0.huskProps.get("DestinationUri");
        synchronized(entries) { e.id=nextId++; }
        if (dest==null) dest=android.net.Uri.fromFile(new java.io.File(context.getCacheDir(),"downloads/"+e.id));
        e.file=safeDestination(context,dest);
        java.util.ArrayList<String> headers=new java.util.ArrayList<>();
        for (java.util.Map.Entry<String,String> h:p0.headers.entrySet()) { headers.add(h.getKey()); headers.add(h.getValue()); }
        synchronized(entries) { entries.put(e.id,e); }
        husk.Web.downloadStart(e.id,p0.url.toString(),e.file.getPath(),headers.toArray(new String[0]));
        return e.id;
    }
    public void forceDownload(long[] p0) {}
    public android.net.Uri getDownloadUri(long p0) { return null; }
    public java.lang.String getMimeTypeForDownloadedFile(long p0) { Entry e=entry(p0); return e==null?null:(String)e.request.huskProps.get("MimeType"); }
    public android.net.Uri getUriForDownloadedFile(long p0) { Entry e=entry(p0); String[] s=husk.Web.downloadQuery(p0); return e!=null && s!=null && Integer.parseInt(s[0])==STATUS_SUCCESSFUL?android.net.Uri.fromFile(e.file):null; }
    public int markRowDeleted(long[] p0) { return 0; }
    public void onMediaStoreDownloadsDeleted(android.util.LongSparseArray p0) {}
    public android.os.ParcelFileDescriptor openDownloadedFile(long p0) throws java.io.FileNotFoundException { Entry e=entry(p0); if(e==null)throw new java.io.FileNotFoundException(); return android.os.ParcelFileDescriptor.open(e.file,android.os.ParcelFileDescriptor.MODE_READ_ONLY); }
    public int pauseDownload(long p0) { return 0; }
    public android.database.Cursor query(android.app.DownloadManager.Query p0) { return query(p0,null); }
    public android.database.Cursor query(android.app.DownloadManager.Query p0, java.lang.String[] p1) {
        String[] columns=p1!=null?p1:new String[]{COLUMN_ID,COLUMN_STATUS,COLUMN_REASON,COLUMN_BYTES_DOWNLOADED_SO_FAR,COLUMN_TOTAL_SIZE_BYTES,COLUMN_LOCAL_URI,COLUMN_LOCAL_FILENAME,COLUMN_URI,COLUMN_TITLE,COLUMN_MEDIA_TYPE,COLUMN_DESCRIPTION,COLUMN_LAST_MODIFIED_TIMESTAMP};
        android.database.MatrixCursor cursor=new android.database.MatrixCursor(columns);
        java.util.ArrayList<Entry> snapshot; synchronized(entries) { snapshot=new java.util.ArrayList<>(entries.values()); }
        long[] ids=p0==null?null:(long[])p0.huskProps.get("FilterById");
        Integer flags=p0==null?null:(Integer)p0.huskProps.get("FilterByStatus");
        for (Entry e:snapshot) {
            if (ids!=null) { boolean match=false; for(long id:ids) if(id==e.id)match=true; if(!match)continue; }
            String[] state=husk.Web.downloadQuery(e.id);
            int status=state==null?STATUS_PENDING:Integer.parseInt(state[0]),reason=state==null?0:Integer.parseInt(state[1]);
            if(flags!=null && (flags&status)==0)continue;
            Object[] row=new Object[columns.length];
            for(int i=0;i<columns.length;i++) {
                String c=columns[i];
                if(COLUMN_ID.equals(c))row[i]=e.id;
                else if(COLUMN_STATUS.equals(c))row[i]=status;
                else if(COLUMN_REASON.equals(c))row[i]=reason;
                else if(COLUMN_BYTES_DOWNLOADED_SO_FAR.equals(c))row[i]=state==null?0L:Long.parseLong(state[2]);
                else if(COLUMN_TOTAL_SIZE_BYTES.equals(c))row[i]=state==null?-1L:Long.parseLong(state[3]);
                else if(COLUMN_LOCAL_URI.equals(c))row[i]=android.net.Uri.fromFile(e.file).toString();
                else if(COLUMN_LOCAL_FILENAME.equals(c))row[i]=e.file.getPath();
                else if(COLUMN_URI.equals(c))row[i]=e.request.url.toString();
                else if(COLUMN_TITLE.equals(c))row[i]=e.request.huskProps.get("Title");
                else if(COLUMN_MEDIA_TYPE.equals(c))row[i]=e.request.huskProps.get("MimeType");
                else if(COLUMN_DESCRIPTION.equals(c))row[i]=e.request.huskProps.get("Description");
                else if(COLUMN_LAST_MODIFIED_TIMESTAMP.equals(c))row[i]=e.file.lastModified();
            }
            cursor.addRow(row);
        }
        return cursor;
    }
    public int remove(long... p0) { int count=0; for(long id:p0) { Entry e; synchronized(entries) { e=entries.remove(id); } if(e!=null) { husk.Web.downloadRemove(id); count++; } } return count; }
    public boolean rename(android.content.Context p0, long p1, java.lang.String p2) { return false; }
    public void restartDownload(long[] p0) {}
    public int resumeDownload(long p0) { return 0; }
    public void setAccessAllDownloads(boolean p0) { huskProps.put("AccessAllDownloads", Boolean.valueOf(p0)); }
    public void setAccessFilename(boolean p0) { huskProps.put("AccessFilename", Boolean.valueOf(p0)); }
    DownloadManager() { this((android.content.Context) null); }
    public static class Query {
        private final java.util.HashMap<String, Object> huskProps = new java.util.HashMap<>();
        public static final int ORDER_ASCENDING = 1;
        public static final int ORDER_DESCENDING = 2;
        public Query() {}
        public android.app.DownloadManager.Query orderBy(java.lang.String p0, int p1) { return this; }
        public android.app.DownloadManager.Query setFilterById(long... p0) { huskProps.put("FilterById", p0); return this; }
        public android.app.DownloadManager.Query setFilterByStatus(int p0) { huskProps.put("FilterByStatus", Integer.valueOf(p0)); return this; }
        public android.app.DownloadManager.Query setFilterByString(java.lang.String p0) { huskProps.put("FilterByString", p0); return this; }
        public android.app.DownloadManager.Query setOnlyIncludeVisibleInDownloadsUi(boolean p0) { huskProps.put("OnlyIncludeVisibleInDownloadsUi", Boolean.valueOf(p0)); return this; }
    }
    public static class Request {
        private final java.util.HashMap<String, Object> huskProps = new java.util.HashMap<>();
        public static final int NETWORK_BLUETOOTH = 4;
        public static final int NETWORK_MOBILE = 1;
        public static final int NETWORK_WIFI = 2;
        public static final int VISIBILITY_HIDDEN = 2;
        public static final int VISIBILITY_VISIBLE = 0;
        public static final int VISIBILITY_VISIBLE_NOTIFY_COMPLETED = 1;
        public static final int VISIBILITY_VISIBLE_NOTIFY_ONLY_COMPLETION = 3;
        private final android.net.Uri url;
        private final java.util.LinkedHashMap<String,String> headers=new java.util.LinkedHashMap<>();
        public Request(android.net.Uri p0) { if(p0==null || !("http".equals(p0.getScheme()) || "https".equals(p0.getScheme())))throw new IllegalArgumentException("HTTP(S) URI required"); url=p0; }
        public android.app.DownloadManager.Request addRequestHeader(java.lang.String p0, java.lang.String p1) { if(p0==null || p0.contains("\r") || p0.contains("\n") || (p1!=null && (p1.contains("\r") || p1.contains("\n"))))throw new IllegalArgumentException("Invalid header"); headers.put(p0,p1==null?"":p1); return this; }
        public void allowScanningByMediaScanner() {}
        public android.app.DownloadManager.Request setAllowedNetworkTypes(int p0) { huskProps.put("AllowedNetworkTypes", Integer.valueOf(p0)); return this; }
        public android.app.DownloadManager.Request setAllowedOverMetered(boolean p0) { huskProps.put("AllowedOverMetered", Boolean.valueOf(p0)); return this; }
        public android.app.DownloadManager.Request setAllowedOverRoaming(boolean p0) { huskProps.put("AllowedOverRoaming", Boolean.valueOf(p0)); return this; }
        public android.app.DownloadManager.Request setDescription(java.lang.CharSequence p0) { huskProps.put("Description", p0); return this; }
        public android.app.DownloadManager.Request setDestinationInExternalFilesDir(android.content.Context p0, java.lang.String p1, java.lang.String p2) { return setDestinationUri(android.net.Uri.fromFile(new java.io.File(p0.getExternalFilesDir(p1),p2))); }
        public android.app.DownloadManager.Request setDestinationInExternalPublicDir(java.lang.String p0, java.lang.String p1) { return this; }
        public android.app.DownloadManager.Request setDestinationUri(android.net.Uri p0) { huskProps.put("DestinationUri", p0); return this; }
        public android.app.DownloadManager.Request setMimeType(java.lang.String p0) { huskProps.put("MimeType", p0); return this; }
        public android.app.DownloadManager.Request setNotificationVisibility(int p0) { huskProps.put("NotificationVisibility", Integer.valueOf(p0)); return this; }
        public android.app.DownloadManager.Request setRequiresCharging(boolean p0) { huskProps.put("RequiresCharging", Boolean.valueOf(p0)); return this; }
        public android.app.DownloadManager.Request setRequiresDeviceIdle(boolean p0) { huskProps.put("RequiresDeviceIdle", Boolean.valueOf(p0)); return this; }
        public android.app.DownloadManager.Request setShowRunningNotification(boolean p0) { huskProps.put("ShowRunningNotification", Boolean.valueOf(p0)); return this; }
        public android.app.DownloadManager.Request setTitle(java.lang.CharSequence p0) { huskProps.put("Title", p0); return this; }
        public android.app.DownloadManager.Request setVisibleInDownloadsUi(boolean p0) { huskProps.put("VisibleInDownloadsUi", Boolean.valueOf(p0)); return this; }
        Request() { this((android.net.Uri) null); }
    }
}
