package com.wavebreak.wavebreak

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.ResultReceiver
import android.provider.Settings
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

// local_auth's BiometricPrompt requires a FragmentActivity host.
class MainActivity : FlutterFragmentActivity() {

    private var pausedAtMs: Long = 0L

    override fun onCreate(savedInstanceState: Bundle?) {
        // The engine must be in the cache BEFORE super.onCreate: after
        // Android killed the process in the background, super.onCreate
        // restores the old FlutterFragment, which looks the cached engine
        // up right away — a fresh process had none yet and the app
        // crashed ("closed by itself", then a system error on the first
        // reopen, fine on the second).
        AppEngine.get(this)
        super.onCreate(savedInstanceState)
        currentRef = java.lang.ref.WeakReference(this)
        // Bug 2: background update check (6h) + one check per app start.
        try {
            UpdateCheckWorker.schedule(applicationContext)
        } catch (t: Throwable) {
            android.util.Log.w("MainActivity", "could not schedule update checks", t)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ActivityCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                REQUEST_POST_NOTIFICATIONS,
            )
        }
    }

    override fun onPause() {
        super.onPause()
        pausedAtMs = System.currentTimeMillis()
        if (resumedRef?.get() === this) resumedRef = null
    }

    // A phone asleep for a long stretch can leave a UDP-based tunnel
    // (Hysteria2/QUIC) silently dead without Android ever reporting a
    // network change at all — the Wi-Fi/LTE interface itself never drops,
    // so WaveEngineVpnService's own NetworkCallback (which exists for
    // exactly this class of problem, see its doc comment) never fires.
    // What actually breaks it: carrier/router NAT tables expire an idle
    // UDP mapping after as little as 30-300s, and a phone asleep for
    // minutes to hours produces exactly that — no keepalive traffic, dead
    // NAT binding, tunnel still "connected" by every signal this app can
    // see except real traffic. Reported symptom this addresses: Hysteria2
    // "stops loading" specifically after the phone has been asleep a
    // while, Direct-TLS (TCP, which the OS itself notices dying) unaffected.
    // Gated on actual elapsed time, not every resume, since a reconnect
    // has a real (if brief) cost and most app switches are seconds, not
    // minutes — nowhere near long enough for a NAT binding to matter.
    override fun onResume() {
        super.onResume()
        resumedRef = java.lang.ref.WeakReference(this)
        // An install confirmation that arrived while the app was in the
        // background (see InstallStatusReceiver): show it now.
        pendingInstallConfirm?.let { confirm ->
            pendingInstallConfirm = null
            UpdateAvailableNotifier.cancelInstallReady(this)
            try {
                startActivity(confirm)
            } catch (t: Throwable) {
                android.util.Log.w("MainActivity", "pending install confirmation failed", t)
            }
        }
        val pausedFor = System.currentTimeMillis() - pausedAtMs
        if (pausedAtMs != 0L && pausedFor >= RESUME_RECONNECT_THRESHOLD_MS) {
            // Same cross-process caveat as pingHost/updateNotificationMeta
            // below — WaveEngineVpnService.instance is never visible from
            // this (the main app) process, only from its own
            // ":RunWaveEngine" one. An Intent is what actually reaches it;
            // onStartCommand() there is a no-op if no engine is running
            // (scheduleReconnect() bails out when activeEngine is null),
            // so this is safe to send unconditionally rather than trying
            // to first ask whether a tunnel exists.
            val intent = Intent(this, WaveEngineVpnService::class.java).apply {
                action = WaveEngineVpnService.ACTION_APP_FOREGROUNDED
            }
            ContextCompat.startForegroundService(this, intent)
        }
    }

    // The app-wide engine (AppEngine): it outlives this window, so the
    // notification buttons and the Quick Settings tile can run the Dart
    // connection logic while the app is closed. Channels live in
    // AppChannels, registered once on that engine.
    // The cached-engine path, not provideFlutterEngine(): FlutterFragment
    // destroyed a provided engine together with the window (seen on the
    // phone: "FlutterJNI was detached", the shade buttons then went
    // nowhere). A cached engine is kept (shouldDestroyEngineWithHost
    // stays false).
    override fun getCachedEngineId(): String {
        AppEngine.get(this)
        return AppEngine.ENGINE_ID
    }

    override fun onDestroy() {
        if (currentRef?.get() === this) currentRef = null
        super.onDestroy()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_VPN_PERMISSION) {
            AppChannels.onVpnPermissionResult(resultCode == RESULT_OK)
        }
    }

    companion object {
        /** This activity while it's in the foreground — see [resumed]. */
        @Volatile
        private var resumedRef: java.lang.ref.WeakReference<MainActivity>? = null

        /**
         * The activity if it's on screen right now. InstallStatusReceiver
         * launches the system's install confirmation from it: a start from
         * a receiver counts as a background start, which MIUI blocks
         * silently unless "show pop-up windows while running in the
         * background" is on (field report: Redmi Note 9 Pro, update
         * downloaded, nothing happened).
         */
        fun resumed(): MainActivity? = resumedRef?.get()

        /** This activity while it exists (on screen or not). */
        @Volatile
        private var currentRef: java.lang.ref.WeakReference<MainActivity>? = null

        fun current(): MainActivity? = currentRef?.get()

        /** The system's install confirmation, held until the app is on screen. */
        @Volatile
        var pendingInstallConfirm: Intent? = null

        private const val REQUEST_POST_NOTIFICATIONS = 1001
        private const val REQUEST_VPN_PERMISSION = AppChannels.REQUEST_VPN_PERMISSION
        // A shorter app-switch (checking a notification, glancing at
        // another app) is nowhere near long enough for a carrier/router's
        // idle-UDP NAT mapping to expire — reconnecting on every resume
        // would just cost a brief blip for no reason. 90s comfortably
        // covers "actually locked the phone and put it away" without
        // firing on routine multitasking.
        private const val RESUME_RECONNECT_THRESHOLD_MS = 90_000L
    }
}
