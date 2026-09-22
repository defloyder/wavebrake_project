package com.wavebreak.wavebreak

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import java.io.File

/**
 * Backs the Dart-side in-app updater (see
 * lib/services/update/update_service.dart): staging directory for a
 * downloaded APK, and triggering the system package installer on it.
 *
 * This app ships outside the Play Store, so there's no other way for a
 * user to apply a new build without manually re-downloading and opening
 * the APK from a browser or file manager each time — this just automates
 * that same flow from inside the app. Nothing here bypasses the user's
 * own consent: Android still shows its own installer confirmation screen,
 * and (the first time) its own "allow this app to install unknown apps"
 * settings prompt.
 */
object UpdateInstaller {
    /**
     * Where Dio (Dart side) should save the downloaded APK — must match
     * file_paths.xml's `<external-files-path name="updates" path="updates/" />`
     * exactly, since [installApk] resolves the FileProvider content:// Uri
     * relative to that same mapping.
     */
    fun stagingDir(context: Context): String {
        val dir = File(context.getExternalFilesDir(null), "updates")
        if (!dir.exists()) dir.mkdirs()
        return dir.absolutePath
    }

    /**
     * True if this app is already allowed to install packages it
     * downloads itself — false the first time, until the user grants it
     * via [installUnknownAppsSettingsIntent]. Checking this before firing
     * the install intent lets the Dart side show "allow installs" instead
     * of a confusing silent no-op (Android just drops the install intent
     * without this permission on API 26+, no exception thrown).
     */
    fun canRequestInstall(context: Context): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.packageManager.canRequestPackageInstalls()
        } else {
            true // Pre-O: gated by the (already-declared) manifest permission alone.
        }
    }

    /** Deep-links straight to this app's own "install unknown apps" toggle. */
    fun installUnknownAppsSettingsIntent(context: Context): Intent {
        return Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
            data = Uri.parse("package:${context.packageName}")
        }
    }

    /**
     * Launches the system installer on an APK already fully downloaded to
     * [apkPath] (must be inside [stagingDir]). Returns false (rather than
     * throwing) if [canRequestInstall] is false or the file doesn't
     * exist, so the Dart side can react without needing to catch a
     * platform exception for an entirely expected, checkable condition.
     */
    fun installApk(context: Context, apkPath: String): Boolean {
        val file = File(apkPath)
        if (!file.exists() || !canRequestInstall(context)) return false
        val uri = FileProvider.getUriForFile(
            context,
            "${context.packageName}.fileprovider",
            file,
        )
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        // ACTION_VIEW on an APK content Uri always resolves to the system
        // package installer on stock Android — no need to also check
        // resolveActivity() the way a truly ambiguous ACTION_VIEW would.
        context.startActivity(intent)
        return true
    }
}
