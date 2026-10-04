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
                if (confirmIntent == null) return
                // From the app's own on-screen activity when there is one:
                // started from this receiver it's a background start, and
                // MIUI drops those without an error unless the user turned
                // on "show pop-up windows while running in the background"
                // (Redmi Note 9 Pro: update downloaded, nothing happened).
                // Otherwise — or if that fails — a notification whose tap
                // opens the confirmation: a tap is always allowed.
                // And kept until it's shown: the user who switched to
                // another app while the update downloaded gets it the
                // moment they come back (field report: back from Telegram,
                // "Installing update…" forever, no prompt).
                val activity = MainActivity.resumed()
                if (activity != null) {
                    activity.runOnUiThread {
                        try {
                            activity.startActivity(confirmIntent)
                        } catch (t: Throwable) {
                            Log.e(TAG, "install confirmation from the activity failed", t)
                            MainActivity.pendingInstallConfirm = confirmIntent
                            UpdateAvailableNotifier.showInstallReady(activity, confirmIntent)
                        }
                    }
                } else {
                    MainActivity.pendingInstallConfirm = confirmIntent
                    UpdateAvailableNotifier.showInstallReady(context, confirmIntent)
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
