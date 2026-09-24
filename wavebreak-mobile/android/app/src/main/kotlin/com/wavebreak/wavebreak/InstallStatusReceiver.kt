package com.wavebreak.wavebreak

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.os.Build
import android.util.Log

/**
 * Receives the result of a [PackageInstaller.Session.commit] started by
 * [UpdateInstaller.installApk] — a static manifest receiver rather than one
 * dynamically registered from MainActivity, since the system's own
 * confirmation UI (launched from here on STATUS_PENDING_USER_ACTION) can
 * take the user away from WAVEBREAK for a moment, and this needs to still
 * be reachable if that happens to background/kill the Flutter activity in
 * the meantime.
 */
class InstallStatusReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val status = intent.getIntExtra(
            PackageInstaller.EXTRA_STATUS,
            PackageInstaller.STATUS_FAILURE,
        )
        when (status) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                // Normal, expected path for any app without the
                // (system/privileged-only) INSTALL_PACKAGES permission:
                // the session is staged, but Android still requires an
                // explicit confirmation tap — this Intent is that
                // confirmation screen itself, already fully formed by the
                // system. FLAG_ACTIVITY_NEW_TASK: this receiver has no
                // activity context of its own to launch from.
                @Suppress("DEPRECATION")
                val confirmIntent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
                } else {
                    intent.getParcelableExtra(Intent.EXTRA_INTENT)
                }
                confirmIntent?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                if (confirmIntent != null) {
                    try {
                        context.startActivity(confirmIntent)
                    } catch (t: Throwable) {
                        Log.e(TAG, "failed to launch install confirmation UI", t)
                    }
                }
            }
            PackageInstaller.STATUS_SUCCESS -> {
                Log.d(TAG, "update installed successfully")
            }
            else -> {
                val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
                Log.e(TAG, "update install failed: status=$status message=$message")
            }
        }
    }

    companion object {
        private const val TAG = "InstallStatusReceiver"
    }
}
