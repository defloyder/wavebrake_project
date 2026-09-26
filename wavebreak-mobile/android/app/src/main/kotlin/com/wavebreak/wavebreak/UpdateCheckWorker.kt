package com.wavebreak.wavebreak

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.TimeUnit

/**
 * Bug 2: the update notification used to depend on the Flutter UI being
 * open (availableUpdateProvider only polls while something watches it),
 * so users heard about a release late or only after opening Settings >
 * Updates. This checks the same manifest in the background every 6 hours
 * (and once per app start) and posts UpdateAvailableNotifier, which
 * dedupes by versionCode so the UI path and this worker never double-post.
 */
class UpdateCheckWorker(context: Context, params: WorkerParameters) : Worker(context, params) {

    override fun doWork(): Result {
        return try {
            val manifest = fetchManifest() ?: return Result.retry()
            val remoteCode = manifest.optLong("versionCode", 0L)
            val url = manifest.optString("url", "")
            if (remoteCode > installedVersionCode(applicationContext) && url.isNotEmpty()) {
                UpdateAvailableNotifier.showOnce(
                    applicationContext,
                    remoteCode,
                    manifest.optString("versionName", ""),
                )
            }
            Result.success()
        } catch (t: Throwable) {
            Log.w(TAG, "update check failed: ${t.javaClass.simpleName}: ${t.message}")
            Result.retry()
        }
    }

    private fun fetchManifest(): JSONObject? {
        val connection = URL(MANIFEST_URL).openConnection() as HttpURLConnection
        return try {
            connection.connectTimeout = 15_000
            connection.readTimeout = 15_000
            connection.setRequestProperty("Cache-Control", "no-cache")
            if (connection.responseCode != HttpURLConnection.HTTP_OK) return null
            JSONObject(connection.inputStream.bufferedReader().use { it.readText() })
        } finally {
            connection.disconnect()
        }
    }

    companion object {
        private const val TAG = "UpdateCheckWorker"
        // Same manifest as update_service.dart's _versionCheckUrl.
        private const val MANIFEST_URL = "https://wavebreak.com.tr/downloads/version.json"
        private const val PERIODIC_NAME = "wavebreak-update-check"
        private const val ON_START_NAME = "wavebreak-update-check-on-start"

        /** Called on every app start: one check now + the 6-hour schedule. */
        fun schedule(context: Context) {
            val constraints = Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .build()
            val workManager = WorkManager.getInstance(context)
            workManager.enqueueUniquePeriodicWork(
                PERIODIC_NAME,
                ExistingPeriodicWorkPolicy.KEEP,
                PeriodicWorkRequestBuilder<UpdateCheckWorker>(6, TimeUnit.HOURS)
                    .setConstraints(constraints)
                    .build(),
            )
            workManager.enqueueUniqueWork(
                ON_START_NAME,
                ExistingWorkPolicy.REPLACE,
                OneTimeWorkRequestBuilder<UpdateCheckWorker>()
                    .setConstraints(constraints)
                    .build(),
            )
        }

        private fun installedVersionCode(context: Context): Long {
            val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                context.packageManager.getPackageInfo(context.packageName, PackageManager.PackageInfoFlags.of(0))
            } else {
                @Suppress("DEPRECATION")
                context.packageManager.getPackageInfo(context.packageName, 0)
            }
            return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                info.longVersionCode
            } else {
                @Suppress("DEPRECATION")
                info.versionCode.toLong()
            }
        }
    }
}
