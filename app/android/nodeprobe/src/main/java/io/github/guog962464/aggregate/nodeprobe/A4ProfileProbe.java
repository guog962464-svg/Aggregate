package io.github.guog962464.aggregate.nodeprobe;

import android.app.Activity;
import android.content.Intent;
import android.util.AtomicFile;
import android.util.Log;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.HashSet;
import java.util.Set;
import java.util.UUID;
import java.util.regex.Pattern;

/** Isolated A4.3 lifecycle fixture; not published through the product RuntimePort. */
final class A4ProfileProbe {
    private static final String TAG = "A4ProfileProbe";
    private static final String ADAPTER_ID = "android-bundled-json5";
    private static final String PACKAGE_ID = "json5";
    private static final String ENTRYPOINT_ID = "json5.bin";
    private static final String ENTRYPOINT_PATH = "lib/cli.js";
    private static final Pattern DRAFT_ID = Pattern.compile("^draft-[0-9a-f]{32}$");
    private static final Pattern PROFILE_ID = Pattern.compile("^node-profile-[0-9a-f]{32}$");

    private A4ProfileProbe() {}

    static void run(Activity activity, Intent intent) {
        String action = intent.getStringExtra("profileAction");
        JSONObject result;
        try {
            result = execute(activity, action, intent.getStringExtra("draftId"),
                    intent.getStringExtra("profileId"));
            result.put("ok", true);
        } catch (Throwable failure) {
            result = new JSONObject();
            try {
                result.put("ok", false);
                result.put("action", action);
                result.put("error", failure instanceof IllegalArgumentException
                        ? failure.getMessage() : "profile operation failed");
            } catch (JSONException ignored) {
                // JSONObject accepts these fixed keys and scalar values.
            }
        }
        Log.i(TAG, "PROFILE_RESULT:" + result);
    }

    private static JSONObject execute(Activity activity, String action, String draftId,
                                      String profileId) throws Exception {
        String preservedDraft = "save".equals(action) || "discard".equals(action)
                ? draftId : null;
        int cleanedOrphans = cleanupOrphans(activity, preservedDraft);
        JSONObject result;
        switch (action == null ? "" : action) {
            case "test":
                result = createDraft(activity);
                break;
            case "discard":
                result = discardDraft(activity, draftId);
                break;
            case "save":
                result = saveDraft(activity, draftId);
                break;
            case "inspect":
                result = inspectProfile(activity, profileId);
                break;
            case "remove":
                result = removeProfile(activity, profileId);
                break;
            case "create-orphan":
                result = createOrphan(activity);
                break;
            default:
                throw new IllegalArgumentException("invalid profile action");
        }
        result.put("cleanedOrphans", cleanedOrphans);
        return result;
    }

    private static JSONObject createDraft(Activity activity) throws Exception {
        JSONObject manifest = readManifest(activity);
        File root = new File(activity.getCacheDir(), "node-profile-drafts");
        if (!root.isDirectory() && !root.mkdirs()) throw new IOException("cannot create draft directory");
        String id = "draft-" + compactId();
        File draft = new File(root, id);
        if (!draft.mkdir()) throw new IOException("cannot create draft");
        try {
            JSONObject value = new JSONObject();
            value.put("schemaVersion", 1);
            value.put("draftId", id);
            value.put("adapterId", ADAPTER_ID);
            value.put("packageId", manifest.getString("packageId"));
            value.put("packageVersion", manifest.getString("version"));
            value.put("tarballSha256", manifest.getString("tarballSha256"));
            value.put("entrypointId", ENTRYPOINT_ID);
            writeJson(new File(draft, "draft.json"), value);
        } catch (Exception failure) {
            deleteTree(draft);
            throw failure;
        }
        JSONObject result = new JSONObject();
        result.put("action", "test");
        result.put("draftId", id);
        result.put("packageId", PACKAGE_ID);
        result.put("packageVersion", manifest.getString("version"));
        result.put("entrypointId", ENTRYPOINT_ID);
        result.put("saved", false);
        return result;
    }

    private static JSONObject discardDraft(Activity activity, String draftId) throws Exception {
        File draft = draftDirectory(activity, draftId);
        boolean existed = draft.exists();
        if (existed) deleteTree(draft);
        JSONObject result = new JSONObject();
        result.put("action", "discard");
        result.put("draftId", draftId);
        result.put("discarded", existed && !draft.exists());
        result.put("connectionCount", loadConnections(activity).length());
        return result;
    }

    private static JSONObject saveDraft(Activity activity, String draftId) throws Exception {
        JSONObject manifest = readManifest(activity);
        File draftDirectory = draftDirectory(activity, draftId);
        File draftFile = new File(draftDirectory, "draft.json");
        if (!draftFile.isFile()) throw new IllegalArgumentException("draft does not exist");
        JSONObject draft = readJson(draftFile);
        validateDraft(draft, draftId, manifest);

        String profileId = "node-profile-" + compactId();
        File profileRoot = profilesDirectory(activity);
        if (!profileRoot.isDirectory() && !profileRoot.mkdirs()) {
            throw new IOException("cannot create profile directory");
        }
        File staging = new File(profileRoot, ".staging-" + compactId());
        File destination = profileDirectory(activity, profileId);
        if (!staging.mkdir() || destination.exists()) throw new IOException("cannot stage profile");
        boolean connectionCommitted = false;
        try {
            JSONObject metadata = new JSONObject();
            metadata.put("schemaVersion", 1);
            metadata.put("profileId", profileId);
            metadata.put("adapterId", ADAPTER_ID);
            metadata.put("packageId", PACKAGE_ID);
            metadata.put("packageVersion", manifest.getString("version"));
            metadata.put("tarballSha256", manifest.getString("tarballSha256"));
            metadata.put("entrypointId", ENTRYPOINT_ID);
            writeJson(new File(staging, "profile.json"), metadata);

            JSONObject config = new JSONObject();
            config.put("enabled", true);
            config.put("version", manifest.getString("version"));
            config.put("userValue", "keep-me");
            writeJson(new File(staging, "config.json5"), config);
            File cache = new File(staging, "cache");
            if (!cache.mkdir()) throw new IOException("cannot create profile cache");
            writeBytes(new File(cache, "probe-cache.bin"), "private-cache".getBytes(StandardCharsets.UTF_8));

            if (!staging.renameTo(destination)) throw new IOException("cannot commit profile directory");
            JSONArray connections = loadConnections(activity);
            JSONObject spec = new JSONObject();
            spec.put("kind", "cli");
            spec.put("label", "JSON5 内置 CLI");
            spec.put("arguments", new JSONArray());
            spec.put("profileId", profileId);
            JSONObject connection = new JSONObject();
            connection.put("id", "node-connection-" + compactId());
            connection.put("spec", spec);
            connections.put(connection);
            writeConnections(activity, connections);
            connectionCommitted = true;
        } catch (Exception failure) {
            if (staging.exists()) deleteTree(staging);
            if (!connectionCommitted && destination.exists()) {
                try {
                    deleteTree(destination);
                } catch (Exception ignored) {
                    // A later orphan sweep can reclaim the profile if rollback itself fails.
                }
            }
            throw failure;
        }

        boolean draftRemoved = false;
        try {
            deleteTree(draftDirectory);
            draftRemoved = true;
        } catch (Exception ignored) {
            // Startup cleanup removes abandoned drafts from the cache directory.
        }
        JSONObject result = new JSONObject();
        result.put("action", "save");
        result.put("draftId", draftId);
        result.put("profileId", profileId);
        result.put("draftRemoved", draftRemoved);
        result.put("connectionCount", loadConnections(activity).length());
        result.put("spec", findConnection(activity, profileId).getJSONObject("spec"));
        return result;
    }

    private static JSONObject inspectProfile(Activity activity, String profileId) throws Exception {
        if (profileId == null || !PROFILE_ID.matcher(profileId).matches()) {
            throw new IllegalArgumentException("invalid profile ID");
        }
        JSONObject connection = findConnection(activity, profileId);
        if (connection == null) {
            JSONObject missing = new JSONObject();
            missing.put("action", "inspect");
            missing.put("found", false);
            missing.put("profileId", profileId);
            return missing;
        }
        JSONObject manifest = readManifest(activity);
        File directory = profileDirectory(activity, profileId);
        JSONObject metadata = readJson(new File(directory, "profile.json"));
        String migratedFrom = validateProfile(metadata, profileId, manifest,
                new File(directory, "profile.json"));
        JSONObject config = readJson(new File(directory, "config.json5"));
        if (!new File(directory, "cache/probe-cache.bin").isFile()) {
            throw new IllegalArgumentException("profile cache is missing");
        }
        JSONObject spec = connection.getJSONObject("spec");
        if (spec.has("executable") || spec.has("entrypoint") || spec.has("packageId")) {
            throw new IllegalArgumentException("connection contains non-profile package data");
        }
        JSONObject result = new JSONObject();
        result.put("action", "inspect");
        result.put("found", true);
        result.put("profileId", profileId);
        result.put("adapterId", metadata.getString("adapterId"));
        result.put("packageId", metadata.getString("packageId"));
        result.put("packageVersion", metadata.getString("packageVersion"));
        result.put("tarballSha256", metadata.getString("tarballSha256"));
        result.put("entrypointId", metadata.getString("entrypointId"));
        if (migratedFrom != null) result.put("migratedFrom", migratedFrom);
        result.put("config", config);
        result.put("spec", spec);
        return result;
    }

    private static JSONObject removeProfile(Activity activity, String profileId) throws Exception {
        if (profileId == null || !PROFILE_ID.matcher(profileId).matches()) {
            throw new IllegalArgumentException("invalid profile ID");
        }
        JSONArray current = loadConnections(activity);
        JSONArray remaining = new JSONArray();
        boolean found = false;
        for (int index = 0; index < current.length(); index++) {
            JSONObject connection = current.getJSONObject(index);
            if (profileId.equals(connection.getJSONObject("spec").getString("profileId"))) {
                found = true;
            } else {
                remaining.put(connection);
            }
        }
        if (found) writeConnections(activity, remaining);
        File directory = profileDirectory(activity, profileId);
        if (directory.exists()) deleteTree(directory);
        JSONObject result = new JSONObject();
        result.put("action", "remove");
        result.put("profileId", profileId);
        result.put("removed", found);
        result.put("profileExists", directory.exists());
        result.put("connectionCount", remaining.length());
        return result;
    }

    private static JSONObject createOrphan(Activity activity) throws Exception {
        JSONObject manifest = readManifest(activity);
        File root = profilesDirectory(activity);
        if (!root.isDirectory() && !root.mkdirs()) throw new IOException("cannot create profile directory");
        String profileId = "node-profile-" + compactId();
        File directory = profileDirectory(activity, profileId);
        if (!directory.mkdirs()) throw new IOException("cannot create orphan profile");
        JSONObject metadata = new JSONObject();
        metadata.put("schemaVersion", 1);
        metadata.put("profileId", profileId);
        metadata.put("adapterId", ADAPTER_ID);
        metadata.put("packageId", PACKAGE_ID);
        metadata.put("packageVersion", manifest.getString("version"));
        metadata.put("tarballSha256", manifest.getString("tarballSha256"));
        metadata.put("entrypointId", ENTRYPOINT_ID);
        writeJson(new File(directory, "profile.json"), metadata);
        String stagingId = ".staging-" + compactId();
        File staging = new File(root, stagingId);
        if (!staging.mkdir()) throw new IOException("cannot create interrupted-save fixture");
        writeBytes(new File(staging, "partial.json"), "partial".getBytes(StandardCharsets.UTF_8));
        JSONObject result = new JSONObject();
        result.put("action", "create-orphan");
        result.put("profileId", profileId);
        result.put("stagingId", stagingId);
        return result;
    }

    private static JSONObject readManifest(Activity activity) throws Exception {
        JSONObject manifest = new JSONObject(readAsset(activity, "a4-json5-manifest.json"));
        if (manifest.getInt("schemaVersion") != 1 ||
                !PACKAGE_ID.equals(manifest.getString("packageId")) ||
                !manifest.getString("version").matches("[0-9]+\\.[0-9]+\\.[0-9]+") ||
                !manifest.getString("tarballSha256").matches("[0-9a-f]{64}") ||
                !manifest.getString("tarballSha256").equals(
                        manifest.getJSONObject("supportedVersions").getString(manifest.getString("version"))) ||
                !ENTRYPOINT_PATH.equals(manifest.getJSONObject("entrypoints").getString(ENTRYPOINT_ID))) {
            throw new IllegalArgumentException("APK package manifest is invalid");
        }
        return manifest;
    }

    private static void validateDraft(JSONObject draft, String draftId, JSONObject manifest)
            throws JSONException {
        if (draft.getInt("schemaVersion") != 1 || !draftId.equals(draft.getString("draftId")) ||
                !ADAPTER_ID.equals(draft.getString("adapterId")) ||
                !PACKAGE_ID.equals(draft.getString("packageId")) ||
                !manifest.getString("version").equals(draft.getString("packageVersion")) ||
                !manifest.getString("tarballSha256").equals(draft.getString("tarballSha256")) ||
                !ENTRYPOINT_ID.equals(draft.getString("entrypointId"))) {
            throw new IllegalArgumentException("draft does not match the APK package manifest");
        }
    }

    private static String validateProfile(JSONObject profile, String profileId, JSONObject manifest,
                                          File profileFile) throws Exception {
        String storedVersion = profile.optString("packageVersion", "");
        String knownDigest = manifest.getJSONObject("supportedVersions").optString(storedVersion, "");
        if (profile.getInt("schemaVersion") != 1 || !profileId.equals(profile.getString("profileId")) ||
                !ADAPTER_ID.equals(profile.getString("adapterId")) ||
                !PACKAGE_ID.equals(profile.getString("packageId")) ||
                knownDigest.isEmpty() || !knownDigest.equals(profile.getString("tarballSha256")) ||
                !ENTRYPOINT_ID.equals(profile.getString("entrypointId"))) {
            throw new IllegalArgumentException("profile does not match the APK package manifest");
        }
        String currentVersion = manifest.getString("version");
        if (!currentVersion.equals(storedVersion)) {
            profile.put("packageVersion", currentVersion);
            profile.put("tarballSha256", manifest.getString("tarballSha256"));
            writeJson(profileFile, profile);
            return storedVersion;
        }
        return null;
    }

    private static JSONArray loadConnections(Activity activity) throws Exception {
        File file = new File(activity.getFilesDir(), "connections.json");
        if (!file.isFile()) return new JSONArray();
        try {
            JSONObject document = readJson(file);
            if (document.getInt("schemaVersion") != 1) {
                throw new IllegalArgumentException("connection index is invalid");
            }
            JSONArray rows = document.getJSONArray("connections");
            Set<String> profileIds = new HashSet<>();
            for (int index = 0; index < rows.length(); index++) {
                JSONObject row = rows.getJSONObject(index);
                JSONObject spec = row.getJSONObject("spec");
                String profileId = spec.getString("profileId");
                if (!"cli".equals(spec.getString("kind")) ||
                        !PROFILE_ID.matcher(profileId).matches() ||
                        spec.has("executable") || spec.has("entrypoint") || spec.has("packageId") ||
                        !profileIds.add(profileId)) {
                    throw new IllegalArgumentException("connection index violates the profile contract");
                }
            }
            return rows;
        } catch (Exception failure) {
            backupDamagedConnections(file);
            throw failure;
        }
    }

    private static void backupDamagedConnections(File original) throws IOException {
        File backup = new File(original.getParentFile(), original.getName() + ".damaged-" +
                System.currentTimeMillis() + "-" + compactId());
        try (InputStream input = new FileInputStream(original);
             FileOutputStream output = new FileOutputStream(backup, false)) {
            byte[] buffer = new byte[4096];
            int count;
            while ((count = input.read(buffer)) != -1) output.write(buffer, 0, count);
            output.getFD().sync();
        }
    }

    private static JSONObject findConnection(Activity activity, String profileId) throws Exception {
        JSONArray rows = loadConnections(activity);
        for (int index = 0; index < rows.length(); index++) {
            JSONObject row = rows.getJSONObject(index);
            if (profileId.equals(row.getJSONObject("spec").getString("profileId"))) return row;
        }
        return null;
    }

    private static int cleanupOrphans(Activity activity, String preservedDraft) throws Exception {
        JSONArray rows = loadConnections(activity);
        Set<String> referenced = new HashSet<>();
        for (int index = 0; index < rows.length(); index++) {
            referenced.add(rows.getJSONObject(index).getJSONObject("spec").getString("profileId"));
        }
        int removed = 0;
        File root = profilesDirectory(activity);
        File[] profiles = root.listFiles();
        if (profiles != null) {
            for (File profile : profiles) {
                String name = profile.getName();
                if (name.startsWith(".staging-") ||
                        (PROFILE_ID.matcher(name).matches() && !referenced.contains(name))) {
                    deleteTree(profile);
                    removed++;
                }
            }
        }
        File drafts = new File(activity.getCacheDir(), "node-profile-drafts");
        File[] draftEntries = drafts.listFiles();
        if (draftEntries != null) {
            for (File draft : draftEntries) {
                if (!draft.getName().equals(preservedDraft)) deleteTree(draft);
            }
        }
        return removed;
    }

    private static File draftDirectory(Activity activity, String draftId) throws IOException {
        if (draftId == null || !DRAFT_ID.matcher(draftId).matches()) {
            throw new IllegalArgumentException("invalid draft ID");
        }
        File root = new File(activity.getCacheDir(), "node-profile-drafts").getCanonicalFile();
        File draft = new File(root, draftId).getCanonicalFile();
        if (!root.equals(draft.getParentFile())) throw new IllegalArgumentException("invalid draft ID");
        return draft;
    }

    private static File profileDirectory(Activity activity, String profileId) throws IOException {
        if (profileId == null || !PROFILE_ID.matcher(profileId).matches()) {
            throw new IllegalArgumentException("invalid profile ID");
        }
        File root = profilesDirectory(activity).getCanonicalFile();
        File profile = new File(root, profileId).getCanonicalFile();
        if (!root.equals(profile.getParentFile())) throw new IllegalArgumentException("invalid profile ID");
        return profile;
    }

    private static File profilesDirectory(Activity activity) {
        return new File(activity.getFilesDir(), "node-profiles");
    }

    private static void writeConnections(Activity activity, JSONArray rows) throws Exception {
        JSONObject document = new JSONObject();
        document.put("schemaVersion", 1);
        document.put("connections", rows);
        writeJson(new File(activity.getFilesDir(), "connections.json"), document);
    }

    private static JSONObject readJson(File file) throws Exception {
        return new JSONObject(readFile(file));
    }

    private static String readAsset(Activity activity, String path) throws Exception {
        try (InputStream input = activity.getAssets().open(path)) {
            ByteArrayOutputStream bytes = new ByteArrayOutputStream();
            byte[] buffer = new byte[4096];
            int count;
            while ((count = input.read(buffer)) != -1) bytes.write(buffer, 0, count);
            return new String(bytes.toByteArray(), StandardCharsets.UTF_8);
        }
    }

    private static String readFile(File file) throws Exception {
        try (InputStream input = new FileInputStream(file)) {
            ByteArrayOutputStream bytes = new ByteArrayOutputStream();
            byte[] buffer = new byte[4096];
            int count;
            while ((count = input.read(buffer)) != -1) bytes.write(buffer, 0, count);
            return new String(bytes.toByteArray(), StandardCharsets.UTF_8);
        }
    }

    private static void writeJson(File file, JSONObject value) throws Exception {
        writeBytes(file, value.toString().getBytes(StandardCharsets.UTF_8));
    }

    private static void writeBytes(File file, byte[] value) throws Exception {
        File parent = file.getParentFile();
        if (parent == null || (!parent.isDirectory() && !parent.mkdirs())) {
            throw new IOException("cannot create private profile directory");
        }
        AtomicFile atomic = new AtomicFile(file);
        FileOutputStream output = null;
        try {
            output = atomic.startWrite();
            output.write(value);
            atomic.finishWrite(output);
        } catch (Exception failure) {
            if (output != null) atomic.failWrite(output);
            throw failure;
        }
    }

    private static void deleteTree(File file) throws IOException {
        if (!file.exists() && !Files.isSymbolicLink(file.toPath())) return;
        if (!Files.isSymbolicLink(file.toPath()) && file.isDirectory()) {
            File[] children = file.listFiles();
            if (children == null) throw new IOException("cannot list private profile directory");
            for (File child : children) deleteTree(child);
        }
        if (!file.delete()) throw new IOException("cannot remove private profile data");
    }

    private static String compactId() {
        return UUID.randomUUID().toString().replace("-", "");
    }
}
