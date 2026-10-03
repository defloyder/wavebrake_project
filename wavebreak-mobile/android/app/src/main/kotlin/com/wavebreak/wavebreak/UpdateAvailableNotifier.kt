package com.wavebreak.wavebreak

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat

/**
 * A one-shot, dismissible "a new WAVEBREAK build is ready" notification —
 * distinct from VpnStatusNotificationService's own ongoing, LOW-importance
 * connection-state notification (different channel, different
 * notification ID: sharing either would mean this either silently
 * overwrites, or gets silently overwritten by, whatever the VPN status
 * bar is currently showing). HIGH importance so it actually pops up/
 * makes a sound rather than sitting silently in the shade — a routine
 * connection-state change is background noise, a new release worth
 * installing isn't.
 *
 * Called from Dart (update_service.dart's [showUpdateAvailableNotification])
 * once per newly-seen versionCode — see app_shell.dart's own dedup via
 * PrefsStore.lastNotifiedUpdateVersionCode for why this itself doesn't
 * need to worry about re-firing for the same release.
 */
object UpdateAvailableNotifier {
    private const val CHANNEL_ID = "wavebreak_updates"
    private const val NOTIFICATION_ID = 4301
    private const val PREFS = "wavebreak_update_notifier"
    private const val KEY_LAST_CODE = "last_notified_version_code"

    /**
     * Posts at most once per versionCode, whoever calls it — the Dart UI
     * path (MainActivity channel) and UpdateCheckWorker (bug 2) share this
     * native record, so the same release never alerts twice.
     */
    @Synchronized
    fun showOnce(context: Context, versionCode: Long, versionName: String) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (versionCode <= prefs.getLong(KEY_LAST_CODE, 0L)) return
        if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) return
        prefs.edit().putLong(KEY_LAST_CODE, versionCode).apply()
        show(context, versionName)
    }

    fun show(context: Context, versionName: String) {
        if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) return
        ensureChannel(context)

        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?.apply { flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK }
        val contentIntent = launchIntent?.let {
            PendingIntent.getActivity(
                context,
                0,
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        val body = if (versionName.isNotEmpty()) {
            "Версия $versionName готова к установке — откройте WAVEBREAK, чтобы скачать."
        } else {
            "Новая версия готова к установке — откройте WAVEBREAK, чтобы скачать."
        }

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.notif_ic_update)
            .setColor(ContextCompat.getColor(context, R.color.wb_wave_cyan))
            .setContentTitle("Доступно обновление WAVEBREAK")
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(contentIntent)
            .build()

        try {
            NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, notification)
        } catch (t: SecurityException) {
            // POST_NOTIFICATIONS revoked between the areNotificationsEnabled()
            // check above and this call — never worth crashing the app over.
        }
    }

    /**
     * "Downloaded — tap to install": used when the system's install
     * confirmation can't be opened directly (app not on screen, or the
     * ROM blocked the start). Tapping it opens [confirmIntent].
     */
    fun showInstallReady(context: Context, confirmIntent: Intent) {
        if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) return
        ensureChannel(context)
        val tap = PendingIntent.getActivity(
            context,
            INSTALL_NOTIFICATION_ID,
            Intent(confirmIntent).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val body = "Нажмите, чтобы установить новую версию WAVEBREAK."
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.notif_ic_update)
            .setColor(ContextCompat.getColor(context, R.color.wb_wave_cyan))
            .setContentTitle("Обновление скачано")
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(tap)
            .build()
        try {
            NotificationManagerCompat.from(context).notify(INSTALL_NOTIFICATION_ID, notification)
        } catch (t: SecurityException) {
            // POST_NOTIFICATIONS revoked — nothing else to do here.
        }
    }

    private const val INSTALL_NOTIFICATION_ID = 4302

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Обновления приложения",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Уведомление о новой версии WAVEBREAK, готовой к установке"
        }
        manager.createNotificationChannel(channel)
    }
}
