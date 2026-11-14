package android.content;

import husk.StoragePaths;
import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.Arrays;
import java.util.HashSet;

public final class StoragePathContract {
    static int checks;
    static final String APP = "E8CA5884-BC22-40D0-8D62-23A555B2F80F";
    static final String OLD = "/private/var/mobile/Containers/Data/Application/5A65C9DF-7E69-4DFC-ABF9-745E22BE519C";
    static final String NOW = "/private/var/mobile/Containers/Data/Application/EF2B1246-8A32-4860-8AB2-9E4ADC9AF532";
    static final String SCOPE = "/Documents/TranslationLayer/" + APP + "/java-data";
    static void check(boolean ok, String message) { checks++; if (!ok) throw new AssertionError(message); }
    static String rebase(String s) { return StoragePaths.rebaseOwnDataPath(s, NOW + SCOPE); }
    public static void main(String[] args) throws Exception {
        check(rebase(OLD+SCOPE+"/sdcard/AnkiDroid").equals(NOW+SCOPE+"/sdcard/AnkiDroid"), "reported old container repaired");
        check(rebase(OLD+SCOPE).equals(NOW+SCOPE), "root directory repaired");
        check(rebase(NOW+SCOPE+"/files").equals(NOW+SCOPE+"/files"), "current path stable");
        check(rebase(OLD.substring(8)+SCOPE+"/files").equals(NOW+SCOPE+"/files"), "var/private alias handled");
        String nested=OLD+"/Documents/Data/Application/11111111-2222-3333-4444-555555555555";
        check(rebase(nested+SCOPE+"/sdcard/AnkiDroid").equals(NOW+SCOPE+"/sdcard/AnkiDroid"), "LiveContainer nested origin handled");
        check(StoragePaths.rebaseOwnDataPath(OLD+SCOPE+"/files",nested+SCOPE).equals(nested+SCOPE+"/files"), "nested current container handled");
        String other=OLD+SCOPE.replace(APP,"11111111-2222-3333-4444-555555555555")+"/files";
        check(rebase(other).equals(other), "another imported app not rewritten");
        for(String p: Arrays.asList("https://example.test"+OLD+SCOPE, "content://documents/1", "file://"+OLD+SCOPE,
                "notes about "+OLD+SCOPE, "relative/AnkiDroid", "/sdcard/AnkiDroid", OLD+"/Documents/other",
                OLD+SCOPE+"-other/files", OLD+SCOPE+"/../other", OLD+SCOPE+"/./files", "/tmp"+SCOPE+"/files")) {
            check(rebase(p).equals(p), "unrelated or unsafe value unchanged: "+p);
        }
        check(rebase(null)==null,"null preserved");
        String spaced=OLD+SCOPE+"/sdcard/My decks/日本語";
        check(rebase(spaced).equals(NOW+SCOPE+"/sdcard/My decks/日本語"), "custom names preserved");
        check(StoragePaths.rebaseOwnDataPath(spaced,NOW+SCOPE+"/").equals(rebase(spaced)),"trailing root slash handled");
        File root=Files.createTempDirectory("husk-prefs-path").toFile();
        File f=new File(root,"shared_prefs/anki.xml");f.getParentFile().mkdirs();
        String oldPath=OLD+SCOPE+"/sdcard/AnkiDroid";
        Files.write(f.toPath(),("s deckPath "+oldPath+"\ns token opaque-account-token\ni count 42\nb enabled true\nS savedFolders "+oldPath+"\u0001unchanged\n").getBytes(StandardCharsets.UTF_8));
        File collection=new File(root,"collection.anki2");Files.write(collection.toPath(),new byte[]{1,2,3,4});
        HuskSharedPreferences prefs=new HuskSharedPreferences(f,NOW+SCOPE);
        check(prefs.getString("deckPath",null).equals(rebase(oldPath)),"actual preferences read repaired before app startup");
        check(prefs.getString("token",null).equals("opaque-account-token") && prefs.getInt("count",0)==42 && prefs.getBoolean("enabled",false),"unrelated typed preferences preserved");
        check(prefs.getStringSet("savedFolders",null).contains(rebase(oldPath)),"persisted path sets migrated");
        check(Arrays.equals(Files.readAllBytes(collection.toPath()),new byte[]{1,2,3,4}),"collection file not modified");
        check(new String(Files.readAllBytes(f.toPath()),StandardCharsets.UTF_8).contains(NOW+SCOPE),"migration persisted");
        HuskSharedPreferences reopened=new HuskSharedPreferences(f,NOW+SCOPE);
        check(reopened.getString("deckPath",null).equals(rebase(oldPath)),"next launch retains repaired location");
        check(reopened.edit().putStringSet("folders",new HashSet<>(Arrays.asList(rebase(oldPath),"unchanged"))).commit(),"atomic commit succeeds");
        check(new HuskSharedPreferences(f,NOW+SCOPE).getStringSet("folders",null).contains("unchanged"),"sets survive replacement");
        check(!new File(f.getParentFile(),f.getName()+".husk-prefs-new").exists(),"no unfinished preferences after save");
        check(android.os.Environment.isExternalStorageManager()==android.os.Environment.isExternalStorageManager(new File("/sdcard")),"virtual storage permission overloads agree");
        System.out.println("Storage path contract: "+checks+" checks passed");
    }
}
