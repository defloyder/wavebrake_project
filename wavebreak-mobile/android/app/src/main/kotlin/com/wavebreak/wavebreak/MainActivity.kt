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
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

// local_auth's BiometricPrompt requires a FragmentActivity host.
class MainActivity : FlutterFragmentActivity() {
    private val statusChannelName = "app.wavebreak/status_notification"
    private val engineChannelName = "app.wavebreak/vpn_engine"
    private val engineStatusChannelName = "app.wavebreak/vpn_engine/status"
    private var enginePermissionResult: MethodChannel.Result? = null
    private var engineStatusReceiver: BroadcastReceiver? = null

    private var pausedAtMs: Long = 0L

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, statusChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "show" -> {
                        val intent = Intent(this, VpnStatusNotificationService::class.java).apply {
                            putExtra(VpnStatusNotificationService.EXTRA_TITLE, call.argument<String>("title") ?: "WAVEBREAK")
                            putExtra(VpnStatusNotificationService.EXTRA_TEXT, call.argument<String>("text") ?: "")
                            putExtra(VpnStatusNotificationService.EXTRA_ONGOING, call.argument<Boolean>("ongoing") ?: true)
                        }
                        ContextCompat.startForegroundService(this, intent)
                        result.success(null)
                    }
                    "hide" -> {
                        val intent = Intent(this, VpnStatusNotificationService::class.java).apply {
                            action = VpnStatusNotificationService.ACTION_HIDE
                        }
                        ContextCompat.startForegroundService(this, intent)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.wavebreak/updater")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getApkStagingDir" -> result.success(UpdateInstaller.stagingDir(this))
                    "canRequestInstall" -> result.success(UpdateInstaller.canRequestInstall(this))
                    "openInstallUnknownAppsSettings" -> {
                        startActivity(UpdateInstaller.installUnknownAppsSettingsIntent(this))
                        result.success(null)
                    }
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("bad_args", "path is required", null)
                        } else {
                            result.success(UpdateInstaller.installApk(this, path))
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, engineChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestPermission" -> {
                        val prepareIntent = VpnService.prepare(this)
                        if (prepareIntent == null) {
                            result.success(true)
                        } else {
                            enginePermissionResult = result
                            startActivityForResult(prepareIntent, REQUEST_VPN_PERMISSION)
                        }
                    }
                    "connect" -> {
                        val link = call.argument<String>("link")
                        val xrayConfig = call.argument<String>("xrayConfig")
                        if (link.isNullOrEmpty() && xrayConfig.isNullOrEmpty()) {
                            result.error("bad_args", "missing link/xrayConfig", null)
                        } else {
                            val intent = Intent(this, WaveEngineVpnService::class.java).apply {
                                if (!link.isNullOrEmpty()) putExtra(WaveEngineVpnService.EXTRA_LINK, link)
                                if (!xrayConfig.isNullOrEmpty()) {
                                    putExtra(WaveEngineVpnService.EXTRA_XRAY_CONFIG, xrayConfig)
                                }
                            }
                            ContextCompat.startForegroundService(this, intent)
                            result.success(null)
                        }
                    }
                    "disconnect" -> {
                        val intent = Intent(this, WaveEngineVpnService::class.java).apply {
                            action = WaveEngineVpnService.ACTION_STOP
                        }
                        ContextCompat.startForegroundService(this, intent)
                        result.success(null)
                    }
                    "pingHost" -> {
                        val host = call.argument<String>("host")
                        val port = call.argument<Int>("port")
                        val timeoutMs = call.argument<Int>("timeoutMs") ?: 4000
                        if (host.isNullOrEmpty() || port == null) {
                            result.error("bad_args", "missing host/port", null)
                        } else if (!isSystemVpnActive()) {
                            // Checked here, not left to the service itself:
                            // WaveEngineVpnService only exists at all while
                            // a tunnel is up or coming up, and Android
                            // creates a fresh instance on demand for ANY
                            // startForegroundService() call targeting it —
                            // including this one. Without this check, a
                            // ping request that arrives while genuinely
                            // disconnected (the location list's own
                            // background sweep runs regardless of
                            // connection state) would spin up a real,
                            // pointless VpnService process complete with
                            // its own foreground notification just to
                            // answer "no_service".
                            result.error("no_service", "vpn not running", null)
                        } else {
                            // WaveEngineVpnService runs in its own
                            // ":RunWaveEngine" process (see its manifest
                            // entry) — a static `instance` field set there
                            // is invisible from this process's memory
                            // entirely, not just stale or racy. Confirmed
                            // on-device: a direct-reference version of this
                            // call read null 100% of the time regardless of
                            // connection state, silently falling back to an
                            // unprotected socket on every single ping. A
                            // ResultReceiver is the standard cross-process
                            // "send a request, get one async result back"
                            // primitive for exactly this — it's Parcelable,
                            // so it survives being put in an Intent to a
                            // different process and calling back into it
                            // from there.
                            val receiver = object : ResultReceiver(Handler(Looper.getMainLooper())) {
                                override fun onReceiveResult(resultCode: Int, resultData: Bundle) {
                                    val ms = resultData.getInt(WaveEngineVpnService.EXTRA_PING_MS, -1)
                                    result.success(if (ms >= 0) ms else null)
                                }
                            }
                            val intent = Intent(this, WaveEngineVpnService::class.java).apply {
                                action = WaveEngineVpnService.ACTION_PING_HOST
                                putExtra(WaveEngineVpnService.EXTRA_PING_HOST, host)
                                putExtra(WaveEngineVpnService.EXTRA_PING_PORT, port)
                                putExtra(WaveEngineVpnService.EXTRA_PING_TIMEOUT_MS, timeoutMs)
                                putExtra(WaveEngineVpnService.EXTRA_RESULT_RECEIVER, receiver)
                            }
                            ContextCompat.startForegroundService(this, intent)
                        }
                    }
                    "updateNotificationMeta" -> {
                        // One-way, unlike pingHost: nothing here needs a
                        // reply, so a plain Intent (the same cross-process-
                        // safe mechanism every other call to this service
                        // already uses — connect/disconnect/check-ping)
                        // is enough on its own, no ResultReceiver needed.
                        val intent = Intent(this, WaveEngineVpnService::class.java).apply {
                            action = WaveEngineVpnService.ACTION_UPDATE_NOTIFICATION_META
                            putExtra("locationLabel", call.argument<String>("locationLabel") ?: "WAVEBREAK")
                            putExtra("flagEmoji", call.argument<String>("flagEmoji") ?: "")
                            putExtra("pingHost", call.argument<String>("pingHost"))
                            call.argument<Int>("pingPort")?.let { putExtra("pingPort", it) }
                            putExtra("labelConnected", call.argument<String>("labelConnected") ?: "Connected")
                            putExtra("labelConnecting", call.argument<String>("labelConnecting") ?: "Connecting…")
                            putExtra("labelFailed", call.argument<String>("labelFailed") ?: "Connection failed")
                            putExtra("labelDisconnect", call.argument<String>("labelDisconnect") ?: "Disconnect")
                            putExtra("labelCheckPing", call.argument<String>("labelCheckPing") ?: "Check ping")
                            putExtra("labelPingUnavailable", call.argument<String>("labelPingUnavailable") ?: "Unavailable")
                            putExtra("labelMeasuring", call.argument<String>("labelMeasuring") ?: "Measuring…")
                        }
                        ContextCompat.startForegroundService(this, intent)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        // Android's VpnService (any engine — Xray-core or the Hysteria
        // bridge) runs in its own process and keeps the real tunnel up
        // even if the user swipes the app away and the Flutter/UI process
        // gets killed and later relaunched cold. Without this check,
        // ConnectionManager.build() always starts from `idle` on a fresh
        // launch, so the UI would show "disconnected" (or, for a guest,
        // "add your own link") while the system tunnel was genuinely still
        // running — confirmed by the user reopening the app and finding it
        // still connected once a server was reselected. Checking for an
        // active VPN transport network-wide is adapter-agnostic: it works
        // the same regardless of which engine actually holds the tunnel.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.wavebreak/vpn_state")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isSystemVpnActive" -> {
                        result.success(isSystemVpnActive())
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, engineStatusChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    val receiver = object : BroadcastReceiver() {
                        override fun onReceive(context: Context, intent: Intent) {
                            events.success(intent.getStringExtra(WaveEngineVpnService.EXTRA_STATE))
                        }
                    }
                    engineStatusReceiver = receiver
                    val filter = IntentFilter(WaveEngineVpnService.ACTION_STATUS)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
                    } else {
                        registerReceiver(receiver, filter)
                    }
                }

                override fun onCancel(arguments: Any?) {
                    engineStatusReceiver?.let { unregisterReceiver(it) }
                    engineStatusReceiver = null
                }
            })
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_VPN_PERMISSION) {
            enginePermissionResult?.success(resultCode == RESULT_OK)
            enginePermissionResult = null
        }
    }

    // Adapter-agnostic (works the same regardless of which engine holds
    // the tunnel) and process-agnostic — unlike anything that would need
    // to reach into WaveEngineVpnService's own ":RunWaveEngine" process,
    // this asks the system itself, which is visible from any process.
    private fun isSystemVpnActive(): Boolean {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val caps = cm.getNetworkCapabilities(cm.activeNetwork)
        return caps?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) ?: false
    }

    companion object {
        private const val REQUEST_POST_NOTIFICATIONS = 1001
        private const val REQUEST_VPN_PERMISSION = 1002
        // A shorter app-switch (checking a notification, glancing at
        // another app) is nowhere near long enough for a carrier/router's
        // idle-UDP NAT mapping to expire — reconnecting on every resume
        // would just cost a brief blip for no reason. 90s comfortably
        // covers "actually locked the phone and put it away" without
        // firing on routine multitasking.
        private const val RESUME_RECONNECT_THRESHOLD_MS = 90_000L
    }
}
