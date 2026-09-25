package com.wavebreak.wavebreak

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import androidx.core.content.FileProvider
import java.io.File
import java.io.FileInputStream

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
     * Installs an APK already fully downloaded to [apkPath] (must be
     * inside [stagingDir]) via the PackageInstaller.Session API. Returns
     * false (rather than throwing) if [canRequestInstall] is false or the
     * file doesn't exist, so the Dart side can react without needing to
     * catch a platform exception for an entirely expected, checkable
     * condition.
     *
     * Real product feedback this replaces the old ACTION_VIEW-on-a-
     * content-Uri path for: that approach makes Android treat every
     * WAVEBREAK update as a brand-new, never-seen-before install — the
     * full "unknown sources"/Play Protect verification screen, every
     * single time, even though this exact app (same package name, same
     * signing key) is already installed and already trusted. Streaming
     * the new APK through an explicit install SESSION instead is what
     * lets Android recognize this as an update to an already-installed
     * app rather than a fresh install, which is what actually earns the
     * lighter update-style confirmation the product owner is after — not
     * a flag or intent extra, but Android's own package-manager logic
     * noticing the package name + signing certificate already match. One
     * system confirmation tap is still unavoidable: a normal app (no
     * device-owner/MDM privilege, no INSTALL_PACKAGES system permission)
     * can never make PackageInstaller skip user confirmation outright —
     * setRequireUserAction(NOT_REQUIRED) exists but is silently ignored
     * for exactly this app's privilege level, so it's deliberately not
     * called here rather than left in as a no-op that reads like it does
     * something. What changes is that the ONE tap becomes an update
     * confirmation, not a fresh-install review.
     */
    fun installApk(context: Context, apkPath: String): Boolean {
        val file = File(apkPath)
        if (!file.exists() || !canRequestInstall(context)) return false
        return try {
            installViaSession(context, file)
            true
        } catch (t: Throwable) {
            Log.e(TAG, "PackageInstaller session failed, falling back to ACTION_VIEW", t)
            installViaActionView(context, file)
        }
    }

    private fun installViaSession(context: Context, file: File) {
        val installer = context.packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
        val sessionId = installer.createSession(params)
        val session = installer.openSession(sessionId)
        session.use { s ->
            FileInputStream(file).use { input ->
                s.openWrite("wavebreak_update", 0, file.length()).use { out ->
                    input.copyTo(out)
                    s.fsync(out)
                }
            }
            val statusIntent = Intent(context, InstallStatusReceiver::class.java)
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                // Android 12+ requires every PendingIntent to declare
                // mutability explicitly — MUTABLE because the system
                // fills this in with EXTRA_STATUS/EXTRA_INTENT before
                // delivering it back to InstallStatusReceiver.
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
            val pendingIntent = PendingIntent.getBroadcast(context, sessionId, statusIntent, flags)
            s.commit(pendingIntent.intentSender)
        }
    }

    /**
     * The original ACTION_VIEW path — kept only as a fallback for the
     * rare device/OEM where the Session API itself misbehaves, not as the
     * normal route any more.
     */
    private fun installViaActionView(context: Context, file: File): Boolean {
        return try {
            val uri = FileProvider.getUriForFile(
                context,
                "${context.packageName}.fileprovider",
                file,
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            context.startActivity(intent)
            true
        } catch (t: Throwable) {
            Log.e(TAG, "ACTION_VIEW install fallback also failed", t)
            false
        }
    }

    private const val TAG = "UpdateInstaller"
}
