package husk;

/** Persisted paths inside one Java app's data follow that app when iOS moves its container. */
public final class StoragePaths {
    private StoragePaths() {}
    private static final String MARKER = "/Documents/TranslationLayer/";
    private static final String UUID = "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}";
    private static final java.util.regex.Pattern CONTAINER = java.util.regex.Pattern.compile(
        "/(?:private/)?var/mobile/Containers/Data/Application/" + UUID
        + "(?:/Documents/Data/Application/" + UUID + ")*");

    public static String rebaseOwnDataPath(String value, String currentDataRoot) {
        if (value == null || currentDataRoot == null || !value.startsWith("/") || value.indexOf('\0') >= 0) return value;
        String root = currentDataRoot;
        while (root.endsWith("/")) root = root.substring(0, root.length() - 1);
        int at = root.lastIndexOf(MARKER);
        if (at < 0 || !CONTAINER.matcher(root.substring(0, at)).matches()) return value;
        String scope = root.substring(at);
        if (!scope.matches(java.util.regex.Pattern.quote(MARKER) + UUID + "/java-data")) return value;
        int oldAt = value.indexOf(scope);
        if (oldAt < 0 || !CONTAINER.matcher(value.substring(0, oldAt)).matches()) return value;
        String tail = value.substring(oldAt + scope.length());
        if (!tail.isEmpty() && !tail.startsWith("/")) return value;
        for (String part : tail.split("/", -1)) if (part.equals("..") || part.equals(".")) return value;
        return root + tail;
    }
}
