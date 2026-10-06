package com.wavebreak.wavebreak

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
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
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Every platform channel the Dart side uses, registered on the app-wide
 * engine ([AppEngine]) with the APPLICATION context — so they keep working
 * while no activity is on screen (a quick action from the notification or
 * the Quick Settings tile runs the Dart connection logic headless). Calls
 * that need a visible screen (VPN consent, share sheet, installer,
 * settings screens) use [MainActivity.current] when there is one; a
 * background start is blocked on MIUI, and VPN consent has no headless
 * form at all.
 */
object AppChannels {
    private const val TAG = "AppChannels"
    private const val STATUS_CHANNEL = "app.wavebreak/status_notification"
    private const val ENGINE_CHANNEL = "app.wavebreak/vpn_engine"
    private const val ENGINE_STATUS_CHANNEL = "app.wavebreak/vpn_engine/status"
    const val REQUEST_VPN_PERMISSION = 1002

    private var permissionResult: MethodChannel.Result? = null
    private var statusReceiver: BroadcastReceiver? = null

    /** Delivered by MainActivity.onActivityResult. */
    fun onVpnPermissionResult(granted: Boolean) {
        permissionResult?.success(granted)
        permissionResult = null
    }

    fun register(engine: FlutterEngine, app: Context) {
        val messenger = engine.dartExecutor.binaryMessenger
        // The activity when one is alive (MIUI blocks activity starts from
        // the background), else the application context.
        fun ui(): Context = MainActivity.current() ?: app

        MethodChannel(messenger, STATUS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "show" -> {
                    val intent = Intent(app, VpnStatusNotificationService::class.java).apply {
                        putExtra(VpnStatusNotificationService.EXTRA_TITLE, call.argument<String>("title") ?: "WAVEBREAK")
                        putExtra(VpnStatusNotificationService.EXTRA_TEXT, call.argument<String>("text") ?: "")
                        putExtra(VpnStatusNotificationService.EXTRA_ONGOING, call.argument<Boolean>("ongoing") ?: true)
                    }
                    startService(app, intent)
                    result.success(null)
                }
                "hide" -> {
                    val intent = Intent(app, VpnStatusNotificationService::class.java).apply {
                        action = VpnStatusNotificationService.ACTION_HIDE
                    }
                    startService(app, intent)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, "app.wavebreak/share").setMethodCallHandler { call, result ->
            when (call.method) {
                "shareFile" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("bad_args", "path is required", null)
                    } else {
                        try {
                            result.success(
                                FileSharer.share(
                                    ui(),
                                    path,
                                    call.argument<String>("mimeType") ?: "text/plain",
                                    call.argument<String>("text"),
                                ),
                            )
                        } catch (t: Throwable) {
                            result.error("share_failed", t.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, "app.wavebreak/updater").setMethodCallHandler { call, result ->
            when (call.method) {
                "getApkStagingDir" -> result.success(UpdateInstaller.stagingDir(app))
                "canRequestInstall" -> result.success(UpdateInstaller.canRequestInstall(app))
                // Picks the per-architecture APK (a third of the universal one).
                "supportedAbis" -> result.success(Build.SUPPORTED_ABIS.toList())
                "openInstallUnknownAppsSettings" -> {
                    startSettingsScreen(
                        ui(),
                        UpdateInstaller.installUnknownAppsSettingsIntent(app),
                        Intent(Settings.ACTION_SECURITY_SETTINGS),
                    )
                    result.success(null)
                }
                "installApk" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("bad_args", "path is required", null)
                    } else {
                        result.success(UpdateInstaller.installApk(ui(), path))
                    }
                }
                "showUpdateAvailableNotification" -> {
                    val versionName = call.argument<String>("versionName") ?: ""
                    val versionCode = call.argument<Number>("versionCode")?.toLong()
                    if (versionCode != null) {
                        UpdateAvailableNotifier.showOnce(app, versionCode, versionName)
                    } else {
                        UpdateAvailableNotifier.show(app, versionName)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, ENGINE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                // VPN consent already given (no system dialog needed)?
                "hasPermission" -> result.success(VpnService.prepare(app) == null)
                "requestPermission" -> {
                    val prepareIntent = VpnService.prepare(app)
                    val activity = MainActivity.current()
                    when {
                        prepareIntent == null -> result.success(true)
                        // Consent needs a screen: a headless quick action
                        // answers "no" and the Dart side opens the app.
                        activity == null -> result.success(false)
                        else -> {
                            permissionResult = result
                            activity.startActivityForResult(prepareIntent, REQUEST_VPN_PERMISSION)
                        }
                    }
                }
                "connect" -> {
                    val link = call.argument<String>("link")
                    val xrayConfig = call.argument<String>("xrayConfig")
                    if (link.isNullOrEmpty() && xrayConfig.isNullOrEmpty()) {
                        result.error("bad_args", "missing link/xrayConfig", null)
                    } else {
                        val intent = Intent(app, WaveEngineVpnService::class.java).apply {
                            if (!link.isNullOrEmpty()) putExtra(WaveEngineVpnService.EXTRA_LINK, link)
                            if (!xrayConfig.isNullOrEmpty()) {
                                putExtra(WaveEngineVpnService.EXTRA_XRAY_CONFIG, xrayConfig)
                            }
                        }
                        if (startService(app, intent)) {
                            result.success(null)
                        } else {
                            result.error("start_blocked", "could not start the VPN service", null)
                        }
                    }
                }
                "disconnect" -> {
                    val intent = Intent(app, WaveEngineVpnService::class.java).apply {
                        action = WaveEngineVpnService.ACTION_STOP
                    }
                    startService(app, intent)
                    result.success(null)
                }
                "pingHost" -> {
                    val host = call.argument<String>("host")
                    val port = call.argument<Int>("port")
                    val timeoutMs = call.argument<Int>("timeoutMs") ?: 4000
                    if (host.isNullOrEmpty() || port == null) {
                        result.error("bad_args", "missing host/port", null)
                    } else if (!isSystemVpnActive(app)) {
                        // WaveEngineVpnService only exists while a tunnel is
                        // up: a start Intent here would spin up a pointless
                        // VPN process just to answer "no_service".
                        result.error("no_service", "vpn not running", null)
                    } else {
                        // The service runs in its own ":RunWaveEngine"
                        // process — a ResultReceiver (Parcelable) carries
                        // the answer back across processes.
                        val receiver = object : ResultReceiver(Handler(Looper.getMainLooper())) {
                            override fun onReceiveResult(resultCode: Int, resultData: Bundle) {
                                val ms = resultData.getInt(WaveEngineVpnService.EXTRA_PING_MS, -1)
                                result.success(if (ms >= 0) ms else null)
                            }
                        }
                        val intent = Intent(app, WaveEngineVpnService::class.java).apply {
                            action = WaveEngineVpnService.ACTION_PING_HOST
                            putExtra(WaveEngineVpnService.EXTRA_PING_HOST, host)
                            putExtra(WaveEngineVpnService.EXTRA_PING_PORT, port)
                            putExtra(WaveEngineVpnService.EXTRA_PING_TIMEOUT_MS, timeoutMs)
                            putExtra(WaveEngineVpnService.EXTRA_RESULT_RECEIVER, receiver)
                        }
                        startService(app, intent)
                    }
                }
                // Latency through the active tunnel (HTTP 204 via the
                // engine) — same method for every protocol.
                "tunnelLatency" -> {
                    if (!isSystemVpnActive(app)) {
                        result.error("no_service", "vpn not running", null)
                    } else {
                        val receiver = object : ResultReceiver(Handler(Looper.getMainLooper())) {
                            override fun onReceiveResult(resultCode: Int, resultData: Bundle) {
                                val ms = resultData.getInt(WaveEngineVpnService.EXTRA_PING_MS, -1)
                                result.success(if (ms >= 0) ms else null)
                            }
                        }
                        val intent = Intent(app, WaveEngineVpnService::class.java).apply {
                            action = WaveEngineVpnService.ACTION_TUNNEL_LATENCY
                            putExtra(WaveEngineVpnService.EXTRA_RESULT_RECEIVER, receiver)
                        }
                        startService(app, intent)
                    }
                }
                "updateNotificationMeta" -> {
                    val intent = Intent(app, WaveEngineVpnService::class.java).apply {
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
                    startService(app, intent)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // Live throughput written by the VPN service every second (it runs
        // in the :RunWaveEngine process). Null when stale.
        MethodChannel(messenger, "app.wavebreak/metrics").setMethodCallHandler { call, result ->
            when (call.method) {
                "liveTraffic" -> {
                    val f = java.io.File(app.filesDir, WaveEngineVpnService.LIVE_TRAFFIC_FILE)
                    val text = runCatching {
                        if (f.exists() && System.currentTimeMillis() - f.lastModified() < 5000) f.readText() else null
                    }.getOrNull()
                    result.success(text)
                }
                else -> result.notImplemented()
            }
        }

        // The tunnel outlives the UI process; a cold start asks the system
        // whether it's still up (adapter-agnostic).
        MethodChannel(messenger, "app.wavebreak/vpn_state").setMethodCallHandler { call, result ->
            when (call.method) {
                "isSystemVpnActive" -> result.success(isSystemVpnActive(app))
                "vpnSessionStartedAtMs" -> result.success(WaveEngineVpnService.sessionStartedAtMs(app))
                "networkLabel" -> result.success(runCatching { NetworkLabel.describe(app) }.getOrNull())
                // The VPN service's on-disk log (EngineLog), for the diagnostic export.
                "engineLog" -> result.success(EngineLog.read(app))
                // Device registration id kept outside backups (see InstallId).
                "installId" -> result.success(runCatching { InstallId.get(app) }.getOrNull())
                "isIgnoringBatteryOptimizations" ->
                    result.success(BatteryOptimization.isIgnoringBatteryOptimizations(app))
                // Only the user can turn on "Always-on VPN" + "Block
                // connections without VPN": open the system VPN screen.
                "openVpnSettings" -> {
                    startSettingsScreen(
                        ui(),
                        Intent(Settings.ACTION_VPN_SETTINGS),
                        Intent(Settings.ACTION_WIRELESS_SETTINGS),
                    )
                    result.success(null)
                }
                // Android 13+: the system's own "add this tile?" sheet.
                // Answers its result code (0 not added, 1 already there,
                // 2 added, negative = error), or -1 below Android 13
                // where the user drags the tile in by hand.
                "requestAddTile" -> {
                    if (Build.VERSION.SDK_INT < 33) {
                        result.success(-1)
                    } else {
                        try {
                            val sbm = app.getSystemService(android.app.StatusBarManager::class.java)
                            sbm.requestAddTileService(
                                android.content.ComponentName(app, QuickTileService::class.java),
                                "WAVEBREAK",
                                android.graphics.drawable.Icon.createWithResource(app, R.drawable.ic_tile_wavebreak),
                                app.mainExecutor,
                            ) { code -> result.success(code) }
                        } catch (t: Throwable) {
                            Log.w(TAG, "requestAddTileService failed", t)
                            result.success(-1)
                        }
                    }
                }
                "requestIgnoreBatteryOptimizations" -> {
                    startSettingsScreen(
                        ui(),
                        BatteryOptimization.requestIgnoreBatteryOptimizationsIntent(app),
                        Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS),
                    )
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // State broadcasts from the VPN service. Registered on the
        // application context: an activity-scoped receiver died with the
        // activity and the engine (which now outlives it) went deaf.
        EventChannel(messenger, ENGINE_STATUS_CHANNEL).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                statusReceiver?.let { runCatching { app.unregisterReceiver(it) } }
                val receiver = object : BroadcastReceiver() {
                    override fun onReceive(context: Context, intent: Intent) {
                        events.success(
                            mapOf(
                                "state" to intent.getStringExtra(WaveEngineVpnService.EXTRA_STATE),
                                "detail" to intent.getStringExtra(WaveEngineVpnService.EXTRA_ERROR_DETAIL),
                            ),
                        )
                    }
                }
                statusReceiver = receiver
                val filter = IntentFilter(WaveEngineVpnService.ACTION_STATUS)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    app.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
                } else {
                    app.registerReceiver(receiver, filter)
                }
            }

            override fun onCancel(arguments: Any?) {
                statusReceiver?.let { runCatching { app.unregisterReceiver(it) } }
                statusReceiver = null
            }
        })

        QuickActions.register(engine, app)
    }

    /** startForegroundService that reports a blocked background start. */
    private fun startService(context: Context, intent: Intent): Boolean = try {
        ContextCompat.startForegroundService(context, intent)
        true
    } catch (t: Throwable) {
        Log.w(TAG, "service start failed: ${intent.action}", t)
        false
    }

    // Our own VPN among all networks (since 1.1.7 the app excludes itself
    // from its tunnel, so activeNetwork is never the VPN). ownerUid is
    // API 30 — calling it on Android 10 crashed (Redmi Note 9 Pro).
    @Suppress("DEPRECATION")
    fun isSystemVpnActive(context: Context): Boolean {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        return cm.allNetworks.any { network ->
            val caps = cm.getNetworkCapabilities(network) ?: return@any false
            caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN) &&
                (Build.VERSION.SDK_INT < Build.VERSION_CODES.R || caps.ownerUid == android.os.Process.myUid())
        }
    }

    /**
     * A system settings screen without crashing on ROMs that lack it:
     * [primary], then [fallback], then nothing.
     */
    private fun startSettingsScreen(context: Context, primary: Intent, fallback: Intent) {
        for (intent in listOf(primary, fallback)) {
            try {
                if (context !is Activity) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(intent)
                return
            } catch (t: Throwable) {
                Log.w(TAG, "settings screen unavailable: ${intent.action}", t)
            }
        }
    }
}
