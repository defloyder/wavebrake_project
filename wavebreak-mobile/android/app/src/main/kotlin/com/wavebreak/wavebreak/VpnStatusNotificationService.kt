package com.wavebreak.wavebreak

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder

/**
 * Foreground service that keeps a single persistent notification in the
 * status bar / notification shade reflecting WAVEBREAK's current
 * connection state — the "floating bar" a VPN app is expected to show
 * while connected. Driven directly from ConnectionManager's Dart-side
 * state via MethodChannel, so the indicator exists even before a real
 * native VpnService tunnel lands (see PlatformVpnAdapter's doc comment).
 */
class VpnStatusNotificationService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_HIDE) {
            // Every startForegroundService() call — even one whose intent
            // only means "hide" — obligates this service to call
            // startForeground() shortly after, or the OS kills the app with
            // a fatal RemoteServiceException. That applies whether this
            // command landed on an already-foregrounded instance or a fresh
            // one, so satisfy it unconditionally before tearing down.
            startForeground(NOTIFICATION_ID, buildNotification("WAVEBREAK", "", true))
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }
        val title = intent?.getStringExtra(EXTRA_TITLE) ?: "WAVEBREAK"
        val text = intent?.getStringExtra(EXTRA_TEXT) ?: ""
        val ongoing = intent?.getBooleanExtra(EXTRA_ONGOING, true) ?: true
        startForeground(NOTIFICATION_ID, buildNotification(title, text, ongoing))
        return START_NOT_STICKY
    }

    private fun buildNotification(title: String, text: String, ongoing: Boolean): Notification {
        ensureChannel()
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val contentIntent = launchIntent?.let {
            PendingIntent.getActivity(
                this,
                0,
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(R.drawable.ic_stat_wavebreak)
            .setOngoing(ongoing)
            .setOnlyAlertOnce(true)
            .setContentIntent(contentIntent)
            .build()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "VPN status",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Shows WAVEBREAK's current connection state"
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    companion object {
        const val ACTION_HIDE = "app.wavebreak.action.HIDE_STATUS"
        const val EXTRA_TITLE = "title"
        const val EXTRA_TEXT = "text"
        const val EXTRA_ONGOING = "ongoing"
        private const val CHANNEL_ID = "wavebreak_vpn_status"
        private const val NOTIFICATION_ID = 4201
    }
}
