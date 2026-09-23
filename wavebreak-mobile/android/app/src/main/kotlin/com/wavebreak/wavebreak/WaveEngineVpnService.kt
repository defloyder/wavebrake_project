package com.wavebreak.wavebreak

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.widget.RemoteViews
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.os.ResultReceiver
import android.util.Log
import app.wavebreak.bridge.bridge.Bridge
import java.net.InetSocketAddress
import java.net.Socket

/**
 * Real system-level VPN tunnel for every protocol WAVEBREAK supports on
 * Android, backed by [Bridge] (native/hysteria_bridge) — one gomobile
 * binding embedding Xray-core (VLESS/VMess/Trojan/Shadowsocks/REALITY —
 * MPL-2.0), the MIT-licensed apernet/hysteria client for Hysteria2, AND
 * (as of tun2socks.go) an in-process TUN-to-SOCKS5 bridge
 * (github.com/xjasonlyu/tun2socks, MIT). Three separate rewrites landed
 * here in sequence, each fixing a real on-device failure the previous one
 * didn't catch:
 *  1. Xray-core used to come from flutter_v2ray's own separately
 *     gomobile-bound libv2ray.aar — two independently built Go runtimes
 *     sharing one process turned out not to be binary-compatible despite
 *     matching Java-level signatures (confirmed via logcat: both native
 *     libraries loaded, then the process died with no Java exception the
 *     moment one touched the other's shared go.Seq bridge). Embedding
 *     Xray-core in this same binding — one go.Seq — fixed that.
 *  2. tun2socks used to be flutter_v2ray's bundled libtun2socks.so,
 *     launched as a subprocess via ProcessBuilder. That worked at first,
 *     but Android's platform-level "phantom process" killer terminates
 *     unrecognized child processes a few seconds in on stricter OEM
 *     builds (confirmed via logcat: "Process PhantomProcessRecord
 *     {...:libtun2socks.so/...} died") — the TUN interface stayed
 *     established with nothing left reading from it: exactly the
 *     "connected, but nothing loads" symptom, for both engines, since
 *     they shared that one subprocess. Running the bridge as goroutines
 *     inside this already-running, already-foreground-service process
 *     isn't a process Android's killer can see at all.
 *  3. Even with tun2socks in-process, still "connected, nothing loads":
 *     Android's VpnService captures ALL traffic from this app's own UID
 *     by default, including the outbound sockets Xray-core/Hysteria open
 *     to the real remote server — those looped right back into the
 *     tunnel they were feeding. [ProtectServer] + native/hysteria_bridge's
 *     protect.go wire up the standard VpnService.protect() pattern to fix
 *     that.
 *
 * Either engine ends up as a local SOCKS5 proxy — Xray-core because its
 * own JSON config always includes one (see share_link_config.dart's
 * `inbound`, always port 1080), Hysteria because bridge.go's Start()
 * builds one explicitly — so establishing the TUN interface and bridging
 * it into that SOCKS5 proxy via Bridge.startTun2Socks is identical either
 * way.
 */
class WaveEngineVpnService : VpnService() {
    private var tunInterface: ParcelFileDescriptor? = null
    private var protectServer: ProtectServer? = null
    private var activeEngine: Engine? = null
    @Volatile private var stopping = false

    // Replayed by reconnectNow() on a detected network change — the exact
    // same string that started the current connection, since Kotlin has no
    // other way to rebuild it (the real request came from Dart, and by the
    // time a reconnect is needed that call is long over).
    private var lastLink: String? = null
    private var lastXrayConfig: String? = null

    private var connectivityManager: ConnectivityManager? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var trackedNetwork: Network? = null
    private val reconnectHandler = Handler(Looper.getMainLooper())
    private var pendingReconnect: Runnable? = null
    private var pendingFdCheck: Runnable? = null
    private var pendingHealthCheck: Runnable? = null
    private var consecutiveHealthCheckFailures = 0
    private var connectRetryCount = 0

    // Everything the notification needs to render as a real, branded
    // WAVEBREAK surface instead of a stock two-line system notification —
    // set once per connect via updateNotificationMeta() (called from Dart
    // through MainActivity, since that's the only side that knows the
    // current location's display name/flag and the app's own localized
    // strings) and refreshed in place as the connection state or a ping
    // result changes. @Volatile: read from the main thread (building the
    // notification) and written from background connect/ping threads.
    @Volatile private var notifLocationLabel: String = "WAVEBREAK"
    @Volatile private var notifFlagEmoji: String = ""
    @Volatile private var notifPingHost: String? = null
    @Volatile private var notifPingPort: Int? = null
    @Volatile private var notifPingText: String = ""
    @Volatile private var notifStatusText: String = ""
    @Volatile private var notifLabelConnected: String = "Connected"
    @Volatile private var notifLabelConnecting: String = "Connecting…"
    @Volatile private var notifLabelFailed: String = "Connection failed"
    @Volatile private var notifLabelDisconnect: String = "Disconnect"
    @Volatile private var notifLabelCheckPing: String = "Check ping"
    @Volatile private var notifLabelPingUnavailable: String = "Unavailable"
    @Volatile private var notifLabelMeasuring: String = "Measuring…"

    private enum class Engine { XRAY, HYSTERIA }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // MainActivity always launches this service through
        // ContextCompat.startForegroundService(...) — for EVERY action,
        // disconnect included — and Android requires startForeground() to
        // be called within a few seconds of that or it kills the process
        // with ForegroundServiceDidNotStartInTimeException. The old
        // structure below only called it on the connect path, so a
        // disconnect (or a malformed start with neither extra set) hit
        // that exception and crashed the service — confirmed via on-device
        // logcat right as this stopped being a Hysteria-only service and
        // started also handling disconnects triggered from more places
        // (e.g. ConnectionManager.reconcileWithSystem()'s teardown path).
        // Call it first, unconditionally, before branching on anything.
        try {
            startForeground(NOTIFICATION_ID, buildNotification())
        } catch (t: Throwable) {
            // This runs on the main thread — anything thrown here (an OEM
            // notification quirk, a revoked POST_NOTIFICATIONS permission
            // racing this call, ...) would otherwise crash the whole app
            // rather than just this connection attempt.
            Log.e(TAG, "startForeground failed", t)
            broadcastState(STATE_FAILED)
            stopSelf()
            return START_NOT_STICKY
        }

        if (intent?.action == ACTION_STOP) {
            stopAll(broadcastIdle = true)
            return START_NOT_STICKY
        }
        if (intent?.action == ACTION_CHECK_PING) {
            handleCheckPingAction()
            return START_NOT_STICKY
        }
        if (intent?.action == ACTION_PING_HOST) {
            handlePingHostAction(intent)
            return START_NOT_STICKY
        }
        if (intent?.action == ACTION_UPDATE_NOTIFICATION_META) {
            handleUpdateNotificationMetaAction(intent)
            return START_NOT_STICKY
        }
        if (intent?.action == ACTION_APP_FOREGROUNDED) {
            notifyAppForegrounded()
            return START_NOT_STICKY
        }
        val link = intent?.getStringExtra(EXTRA_LINK)
        val xrayConfig = intent?.getStringExtra(EXTRA_XRAY_CONFIG)
        if (link.isNullOrEmpty() && xrayConfig.isNullOrEmpty()) {
            stopAll(broadcastIdle = false)
            return START_NOT_STICKY
        }
        stopping = false
        broadcastState(STATE_CONNECTING)
        registerNetworkWatch()
        scheduleFdCheck()
        scheduleHealthCheck()
        if (!xrayConfig.isNullOrEmpty()) {
            activeEngine = Engine.XRAY
            lastXrayConfig = xrayConfig
            lastLink = null
            Thread({ connectXray(xrayConfig) }, "WaveEngineConnect").start()
        } else {
            activeEngine = Engine.HYSTERIA
            lastLink = link
            lastXrayConfig = null
            Thread({ connectHysteria(link!!) }, "WaveEngineConnect").start()
        }
        return START_STICKY
    }

    // Wi-Fi<->cellular handovers, a flaky Wi-Fi reconnect, or the radio
    // power-cycling after the phone wakes from sleep all leave the TUN
    // interface itself looking fine while the actual protected sockets
    // underneath (Xray-core's TCP connection, Hysteria's QUIC session) are
    // now talking to a dead interface — nothing tells them to redial on
    // their own, so the tunnel silently stops passing traffic until the
    // user notices and manually reconnects. NET_CAPABILITY_NOT_VPN keeps
    // this from reacting to our own tunnel's network coming and going.
    private fun registerNetworkWatch() {
        if (networkCallback != null) return
        val cm = getSystemService(ConnectivityManager::class.java) ?: return
        val request = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
            .build()
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                val previous = trackedNetwork
                trackedNetwork = network
                if (previous != null && previous != network) {
                    scheduleReconnect("network changed")
                }
            }

            override fun onLost(network: Network) {
                if (network == trackedNetwork) {
                    trackedNetwork = null
                    scheduleReconnect("network lost")
                }
            }
        }
        try {
            cm.registerNetworkCallback(request, callback)
            connectivityManager = cm
            networkCallback = callback
        } catch (t: Throwable) {
            Log.e(TAG, "registerNetworkCallback failed", t)
        }
    }

    private fun unregisterNetworkWatch() {
        val cm = connectivityManager
        val cb = networkCallback
        if (cm != null && cb != null) {
            try {
                cm.unregisterNetworkCallback(cb)
            } catch (t: Throwable) {
            }
        }
        connectivityManager = null
        networkCallback = null
        trackedNetwork = null
        pendingReconnect?.let { reconnectHandler.removeCallbacks(it) }
        pendingReconnect = null
        pendingFdCheck?.let { reconnectHandler.removeCallbacks(it) }
        pendingFdCheck = null
        pendingHealthCheck?.let { reconnectHandler.removeCallbacks(it) }
        pendingHealthCheck = null
    }

    // Debounced: a handover fires onLost then onAvailable in quick
    // succession — reacting to each separately would tear the tunnel down
    // and rebuild it twice for one real transition. Waiting for the dust to
    // settle also skips reacting at all to a blip shorter than this window.
    private fun scheduleReconnect(reason: String) {
        if (stopping || activeEngine == null) return
        pendingReconnect?.let { reconnectHandler.removeCallbacks(it) }
        val runnable = Runnable { reconnectNow(reason) }
        pendingReconnect = runnable
        reconnectHandler.postDelayed(runnable, 1200)
    }

    // Replays whichever connect the user actually asked for through the
    // exact same connectXray/connectHysteria path a fresh connect uses.
    //
    // Real-device bug this fixes, found investigating a report that the
    // health check below "doesn't fully" recover a stale tunnel: Telegram
    // (and everything else) stays stuck on "Connecting..." with no
    // traffic even after a health-check-triggered reconnect succeeds —
    // WaveBreak itself shows Connected throughout, because its own
    // fresh health-probe socket genuinely works over the new path.
    //
    // Root cause was sequencing, not the health check itself.
    // establishTun()'s Builder().establish() DOES hand back a genuinely
    // new tun fd each time, and Bridge.startTun2Socks() DOES self-heal
    // (stops the previous tun2socks engine — and closes ITS fd — before
    // starting the new one; see native/hysteria_bridge/tun2socks.go).
    // But that stop-then-start used to happen back-to-back inside one
    // call with no real gap in between, from the same thread, in well
    // under a millisecond. Android's connectivity stack treats that as
    // one continuous VPN network having its interface silently swapped,
    // not a real down-then-up transition — there's no window for the OS
    // (or any other app watching for a network change) to ever observe
    // the old interface as gone. An app like Telegram sitting on an
    // already-established, currently idle TCP connection through the
    // OLD tun path gets no signal whatsoever that anything changed; its
    // packets just silently go nowhere on a socket it has no reason to
    // give up on, often for a very long time (exactly "no self-heal,
    // user has to intervene").
    //
    // releaseTunOnly() below explicitly closes the current interface
    // FIRST, and RECONNECT_INTERFACE_DOWN_GAP_MS gives Android's
    // connectivity stack an actual beat to register that before a new
    // one gets established — turning the swap into a real (if brief)
    // down/up cycle other apps' stale sockets can actually notice and
    // recover from, the same way a manual disconnect+reconnect already
    // did (that just went through a much bigger gap: a full
    // stopSelf()/new-service cycle).
    private fun reconnectNow(reason: String) {
        if (stopping) return
        Log.d(TAG, "reconnecting after $reason")
        broadcastState(STATE_CONNECTING)
        releaseTunOnly()
        reconnectHandler.postDelayed({
            if (stopping) return@postDelayed
            when (activeEngine) {
                Engine.XRAY -> lastXrayConfig?.let { cfg ->
                    Thread({ connectXray(cfg) }, "WaveEngineReconnect").start()
                }
                Engine.HYSTERIA -> lastLink?.let { link ->
                    Thread({ connectHysteria(link) }, "WaveEngineReconnect").start()
                }
                null -> {}
            }
        }, RECONNECT_INTERFACE_DOWN_GAP_MS)
    }

    // Tears down just the OS-visible side of the tunnel (tun2socks + the
    // TUN interface itself) without touching the underlying Xray/
    // Hysteria proxy engine — that engine's own Bridge.startXray/start
    // already self-heals fine on its own and doesn't need (or want, if
    // it costs session/handshake state) an extra stop-restart cycle just
    // to fix what's really an interface-visibility problem. Shared by
    // reconnectNow's real down/up gap above and releaseEngineResources'
    // full teardown below.
    private fun releaseTunOnly() {
        try {
            Bridge.stopTun2Socks()
        } catch (t: Throwable) {
        }
        try {
            tunInterface?.close()
        } catch (t: Throwable) {
        }
        tunInterface = null
    }

    // Confirmed on-device: ordinary browsing over an otherwise-healthy
    // connection climbs toward the process's fd limit (32768 on this
    // device) within minutes — somewhere in tun2socks' or Xray-core's own
    // per-connection handling, not this app's code, so there's no single
    // call site to fix. Polling Bridge.openFdCount() (native/
    // hysteria_bridge/fdwatch.go) and reconnecting early, before a real
    // request gets EMFILE and the tunnel just stops passing traffic with
    // no obvious cause, trades a brief, automatic reconnect for what used
    // to be a silent stall the user had no way to explain.
    private fun scheduleFdCheck() {
        pendingFdCheck?.let { reconnectHandler.removeCallbacks(it) }
        val runnable = object : Runnable {
            override fun run() {
                if (stopping || activeEngine == null) return
                try {
                    val count = Bridge.openFdCount()
                    if (count > FD_WARN_THRESHOLD) {
                        Log.w(TAG, "open fd count high ($count), reconnecting")
                        scheduleReconnect("fd count high")
                    } else {
                        // Also covers count == -1 (openFdCount() couldn't
                        // read /proc/self/fd) — retry rather than treat an
                        // unreadable count as either a pass or a failure.
                        reconnectHandler.postDelayed(this, FD_CHECK_INTERVAL_MS)
                    }
                } catch (t: Throwable) {
                    // Bridge not loaded yet (race with the very first
                    // connect) — just try again next interval rather than
                    // treating it as a real failure.
                    reconnectHandler.postDelayed(this, FD_CHECK_INTERVAL_MS)
                }
            }
        }
        pendingFdCheck = runnable
        reconnectHandler.postDelayed(runnable, FD_CHECK_INTERVAL_MS)
    }

    // The bug this exists for: the phone sleeps/locks (or reboots) on an
    // otherwise-unchanged Wi-Fi network — no handover, so
    // registerNetworkWatch()'s onLost/onAvailable never fires at all —
    // while the carrier/router's NAT mapping for the tunnel's actual
    // outbound socket times out from being idle during that stretch, or
    // Doze suspends something mid-flight. The TUN interface and this
    // service both look completely fine the whole time; only an actual
    // attempt to pass traffic through the tunnel reveals it's dead. Confirmed
    // as the real-device symptom: app shows "Connected", Telegram (and
    // everything else) doesn't work, for a long time with nothing to
    // notice or recover on its own until the user manually toggles the
    // connection — this is what makes that recovery automatic instead.
    //
    // Deliberately a real socket connect, not just a TCP SYN/RST check —
    // ping-style probes can succeed against a NAT table entry that still
    // exists locally even once the actual path is dead. This process's
    // own sockets are captured into the tunnel by VpnService by default
    // (same as every other app's), so an ordinary unprotected connect
    // here really does exercise the whole tun2socks -> engine -> real
    // server path, not a shortcut around it.
    private fun scheduleHealthCheck() {
        pendingHealthCheck?.let { reconnectHandler.removeCallbacks(it) }
        consecutiveHealthCheckFailures = 0
        val runnable = object : Runnable {
            override fun run() {
                if (stopping || activeEngine == null) return
                Thread({
                    val alive = probeTunnelAlive()
                    reconnectHandler.post {
                        if (stopping || activeEngine == null) return@post
                        if (alive) {
                            consecutiveHealthCheckFailures = 0
                            reconnectHandler.postDelayed(this, HEALTH_CHECK_INTERVAL_MS)
                        } else {
                            consecutiveHealthCheckFailures++
                            Log.w(TAG, "tunnel health check failed ($consecutiveHealthCheckFailures/$HEALTH_CHECK_FAILURE_THRESHOLD)")
                            if (consecutiveHealthCheckFailures >= HEALTH_CHECK_FAILURE_THRESHOLD) {
                                consecutiveHealthCheckFailures = 0
                                scheduleReconnect("health check failed")
                            } else {
                                // One failure could just be a genuinely slow
                                // real network blip — only a SECOND
                                // consecutive failure earns a reconnect, so
                                // this doesn't fight a connection that's
                                // merely momentarily congested.
                                reconnectHandler.postDelayed(this, HEALTH_CHECK_RETRY_MS)
                            }
                        }
                    }
                }, "WaveEngineHealthCheck").start()
            }
        }
        pendingHealthCheck = runnable
        reconnectHandler.postDelayed(runnable, HEALTH_CHECK_INTERVAL_MS)
    }

    // Runs on a background thread (see scheduleHealthCheck) — blocking
    // socket I/O, never call this on the main thread.
    private fun probeTunnelAlive(): Boolean {
        return try {
            Socket().use { socket ->
                socket.connect(
                    InetSocketAddress(HEALTH_CHECK_HOST, HEALTH_CHECK_PORT),
                    HEALTH_CHECK_TIMEOUT_MS,
                )
            }
            true
        } catch (t: Throwable) {
            false
        }
    }

    // Starts the local protect socket server and points the Go side at it
    // — must happen before either engine opens its first outbound socket,
    // since that's exactly what needs to be protect()ed. Safe to call more
    // than once per process (ProtectServer.start() and Bridge's own
    // sync.Once both no-op past the first call).
    private fun setUpProtection() {
        System.loadLibrary("hysteriabridge")
        if (protectServer == null) {
            val server = ProtectServer(this, PROTECT_SOCKET_NAME)
            server.start()
            protectServer = server
        }
        // LocalServerSocket binds in Android's abstract namespace, which
        // on the wire is a NUL-prefixed name — control.ProtectPath (Go
        // side) does a plain syscall.Connect with whatever string it's
        // given, so the NUL prefix has to be added here to match.
        Bridge.setProtectPath(" $PROTECT_SOCKET_NAME")
        val regErr = Bridge.protectRegisterError()
        if (regErr.isNotEmpty()) {
            Log.e(TAG, "RegisterDialerController failed: $regErr")
        } else {
            Log.d(TAG, "RegisterDialerController ok")
        }
    }

    // Switching servers reuses this already-running service instance and
    // deliberately skips a full stopAll() (see selectLocation()'s comment
    // in connection_manager.dart) — Bridge.startXray()/start() each
    // self-heal against a STALE INSTANCE OF THE SAME ENGINE, but neither
    // one ever knew to stop the OTHER engine. Switching Direct-TLS
    // (Xray) -> Hysteria2 left the old Xray instance (and its tun2socks
    // bridge) fully running while Hysteria's own Bridge.start() tried to
    // start alongside it — confirmed on-device this is what produced
    // "connect protect path: connection refused" during Hysteria's own
    // dial, not a stale/rebinding ProtectServer (that one path is
    // unaffected by an engine switch, since protectServer != null skips
    // recreating it). Two engines both driving tun2socks/the TUN fd at
    // once is wrong regardless of whether that's the exact failure mode
    // every time, which is also the likely source of the 8-10s stalls
    // reported on same-engine switches under the same contention.
    private fun stopOtherEngine(target: Engine) {
        val previous = activeEngine
        if (previous == null || previous == target) return
        Log.d(TAG, "stopping $previous before starting $target")
        try {
            Bridge.stopTun2Socks()
        } catch (t: Throwable) {
        }
        try {
            when (previous) {
                Engine.XRAY -> Bridge.stopXray()
                Engine.HYSTERIA -> Bridge.stop()
            }
        } catch (t: Throwable) {
        }
    }

    private fun connectXray(configJson: String) {
        try {
            stopOtherEngine(Engine.XRAY)
            setUpProtection()
            // Only matters when the generated config actually references
            // geosite:/geoip: rules (smart-routing's RU-direct policy — see
            // share_link_config.dart's routing_policy handling), but it's
            // cheap and idempotent to call unconditionally: Xray-core
            // simply never looks at XRAY_LOCATION_ASSET when a config has
            // no such rules.
            Bridge.ensureGeoAssets(filesDir.absolutePath)
            Bridge.startXray(configJson)
            // share_link_config.dart's inbound is always a SOCKS5 listener
            // on 127.0.0.1:1080 — Xray-core doesn't hand a port back the
            // way Hysteria's bridge does, but there's nothing to discover
            // since this app controls both ends of that config.
            establishTun(XRAY_SOCKS_PORT)
            if (!stopping) broadcastState(STATE_CONNECTED)
            connectRetryCount = 0
        } catch (t: Throwable) {
            Log.e(TAG, "xray connect failed", t)
            handleConnectFailure(t) { connectXray(configJson) }
        }
    }

    private fun connectHysteria(link: String) {
        try {
            stopOtherEngine(Engine.HYSTERIA)
            setUpProtection()
            val port = Bridge.start(link)
            establishTun(port.toInt())
            if (!stopping) broadcastState(STATE_CONNECTED)
            connectRetryCount = 0
        } catch (t: Throwable) {
            // Deliberately catches Throwable, not just Exception: gomobile's
            // generated native layer can throw UnsatisfiedLinkError /
            // NoSuchMethodError (subclasses of Error, not Exception). An
            // uncaught Error on ANY thread is fatal to the whole process by
            // default on Android — not just this service — so a narrower
            // catch here previously took the entire app down on a failed
            // connection instead of just failing that one attempt.
            Log.e(TAG, "hysteria connect failed", t)
            handleConnectFailure(t) { connectHysteria(link) }
        }
    }

    // A connect attempt that fails with UnsatisfiedLinkError specifically —
    // confirmed on-device as "dlopen failed: library ... not found" from
    // System.loadLibrary(), called at the very top of every (re)connect —
    // means the process was at its fd ceiling at that exact moment (this
    // device's is 32768; the fd-watchdog's own reading right before this
    // fired showed 32765, three free). That's not "library missing", it's
    // "no fd left for the loader's own bookkeeping to use", and it can hit
    // ANY syscall needing a new fd, not just this one. stopAll() below does
    // release this attempt's (never-fully-started) fds plus the previous
    // connection's via Bridge's self-heal-on-stop path, so a short wait for
    // the OS to actually reclaim them and ONE retry has a real chance where
    // failing immediately does not. Capped at one retry: a genuine config/
    // network failure (wrong credentials, unreachable host, ...) would just
    // fail the same way again and this isn't meant to mask that as a hang.
    private fun handleConnectFailure(error: Throwable, retry: () -> Unit) {
        if (error is UnsatisfiedLinkError && connectRetryCount < 1 && !stopping) {
            connectRetryCount++
            Log.w(TAG, "connect failed (fd exhaustion suspected), retrying once")
            // releaseEngineResources(), not stopAll(): stopAll() sets
            // `stopping = true` and calls stopSelf(), which would race the
            // retry against this same service instance being torn down by
            // Android — a genuinely retry-safe cleanup can only release
            // what the failed attempt was holding, not end the service.
            releaseEngineResources()
            reconnectHandler.postDelayed({
                if (!stopping) Thread({ retry() }, "WaveEngineConnectRetry").start()
            }, 1500)
            return
        }
        connectRetryCount = 0
        stopAll(broadcastIdle = false)
        broadcastState(STATE_FAILED, detail = "${error.javaClass.simpleName}: ${error.message}")
    }

    // The resource-release half of stopAll(), without any of its
    // service-lifecycle side effects (stopping flag, network watch
    // teardown, stopForeground/stopSelf) — see handleConnectFailure()'s
    // retry path, the one caller that needs cleanup without ending the
    // service.
    private fun releaseEngineResources() {
        releaseTunOnly()
        try {
            when (activeEngine) {
                Engine.XRAY -> Bridge.stopXray()
                Engine.HYSTERIA -> Bridge.stop()
                null -> {}
            }
        } catch (t: Throwable) {
        }
    }

    private fun establishTun(socksPort: Int) {
        val builder = Builder()
            .setSession("WAVEBREAK")
            .setMtu(TUN_MTU)
            .addAddress(TUN_ADDRESS, 30)
            .addRoute("0.0.0.0", 0)
            // Plain IPs only — Android's VpnService.Builder.addDnsServer()
            // throws IllegalArgumentException on anything that isn't a bare
            // IP (confirmed the hard way early this project: see
            // share_link_config.dart's dns comment).
            .addDnsServer("1.1.1.1")
            .addDnsServer("8.8.8.8")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setMetered(false)
        }
        for (packageName in RU_VPN_DETECTING_APPS) {
            try {
                builder.addDisallowedApplication(packageName)
            } catch (t: PackageManager.NameNotFoundException) {
                // Not installed on this device — nothing to exclude, and
                // addDisallowedApplication would otherwise abort the whole
                // establish() call over one absent app.
            }
        }
        val iface = builder.establish() ?: throw IllegalStateException("VpnService.Builder.establish() returned null")
        tunInterface = iface
        // detachFd() hands sole ownership of the raw fd to the Go engine —
        // it does the reading/writing/closing from here on. Keeping the
        // ParcelFileDescriptor around afterward would just be a dangling
        // wrapper around an fd number the OS is free to reuse for anything
        // else the moment the engine closes it.
        val fd = iface.detachFd()
        Bridge.startTun2Socks(fd.toLong(), TUN_MTU.toLong(), "127.0.0.1:$socksPort")
        tunInterface = null
    }

    private fun stopAll(broadcastIdle: Boolean) {
        stopping = true
        unregisterNetworkWatch()
        try {
            Bridge.stopTun2Socks()
        } catch (t: Throwable) {
        }
        try {
            when (activeEngine) {
                Engine.XRAY -> Bridge.stopXray()
                Engine.HYSTERIA -> Bridge.stop()
                null -> {}
            }
        } catch (t: Throwable) {
        }
        activeEngine = null
        // Only relevant if establishTun() itself threw before reaching
        // detachFd() — once detached, Bridge.stopTun2Socks() above already
        // owns closing it, and this is a safe no-op (Android's
        // ParcelFileDescriptor tolerates a redundant close after detach).
        try {
            tunInterface?.close()
        } catch (t: Throwable) {
        }
        tunInterface = null
        if (broadcastIdle) broadcastState(STATE_IDLE)
        stopForeground(true)
        stopSelf()
    }

    override fun onRevoke() {
        stopAll(broadcastIdle = true)
    }

    override fun onDestroy() {
        stopAll(broadcastIdle = false)
        protectServer?.stop()
        protectServer = null
        super.onDestroy()
    }

    // A ping test that opens its own unprotected socket while this tunnel
    // is up gets captured into it like any other app traffic — but unlike
    // a real cold dial, `host:port` here is the VPN node itself, which
    // Xray-core/Hysteria already hold an open, multiplexed session to. The
    // "connect" that comes back measures that existing session handing out
    // a new local stream, not a fresh round trip to the actual remote
    // server, which is why it read as an implausible 2-4ms even for a
    // server the phone is nowhere near. protect()ing this socket — same
    // call every real engine dial already goes through via [ProtectServer]
    // — routes it around the tunnel entirely, onto the phone's real
    // network interface, for a genuine external RTT.
    fun pingHost(host: String, port: Int, timeoutMs: Int): Int? {
        var socket: java.net.Socket? = null
        return try {
            socket = java.net.Socket()
            // Confirmed on-device: protect(socket) alone returned false
            // here — `new Socket()` on Android doesn't necessarily
            // materialize a real underlying native fd until the socket is
            // actually bound or connected, and protect() has nothing to
            // attach to before that exists. Binding to an ephemeral local
            // port (":0" — the OS picks one) forces that fd into
            // existence without otherwise touching where this socket
            // eventually connects to. ProtectServer.kt's own path never
            // hit this: it protects an fd Go's syscall.Socket() already
            // created directly, not a lazily-backed java.net.Socket.
            socket.bind(java.net.InetSocketAddress(0))
            val protected = protect(socket)
            if (!protected) Log.w(TAG, "pingHost: protect() returned false for $host:$port")
            val start = System.nanoTime()
            socket.connect(java.net.InetSocketAddress(host, port), timeoutMs)
            ((System.nanoTime() - start) / 1_000_000L).toInt()
        } catch (t: Throwable) {
            Log.w(TAG, "pingHost failed for $host:$port: ${t.javaClass.simpleName}: ${t.message}")
            null
        } finally {
            try {
                socket?.close()
            } catch (e: Exception) {
            }
        }
    }

    private fun broadcastState(state: String, detail: String? = null) {
        notifStatusText = when (state) {
            STATE_CONNECTING -> notifLabelConnecting
            STATE_CONNECTED -> notifLabelConnected
            STATE_FAILED -> notifLabelFailed
            else -> notifStatusText
        }
        // A ping from the PREVIOUS server reads as this server's ping the
        // instant the notification updates for a new one — worse than
        // just clearing it, since it's a plausible-looking wrong number
        // rather than an obvious blank.
        if (state == STATE_CONNECTING) notifPingText = ""
        refreshNotification()
        val intent = Intent(ACTION_STATUS)
        intent.setPackage(packageName)
        intent.putExtra(EXTRA_STATE, state)
        // The actual Xray-core/Hysteria error (a dial failure, TLS/REALITY
        // handshake rejection, malformed config, ...) previously only
        // ever reached Log.e — invisible without adb, which is exactly
        // the tool unavailable for the real-device reports this exists to
        // help diagnose. Riding along on the same broadcast the Dart side
        // already listens to costs nothing extra and means
        // AppLogger/the diagnostic log export actually captures it.
        if (detail != null) intent.putExtra(EXTRA_ERROR_DETAIL, detail)
        sendBroadcast(intent)
    }

    /// Called from MainActivity right as Dart starts a connect/switch —
    /// the only side that knows the target location's display name/flag
    /// and holds the app's own localized strings (see AppStrings; Kotlin
    /// has no access to those). [pingHost]/[pingPort] null means this
    /// location isn't TCP-probeable (Hysteria2 — see ConnectionTestService's
    /// identical rule on the Dart side), so the notification's own "check
    /// ping" always reads as honestly unavailable instead of quietly
    /// reusing whatever the last TCP-based location measured.
    fun updateNotificationMeta(
        locationLabel: String,
        flagEmoji: String,
        pingHost: String?,
        pingPort: Int?,
        labelConnected: String,
        labelConnecting: String,
        labelFailed: String,
        labelDisconnect: String,
        labelCheckPing: String,
        labelPingUnavailable: String,
        labelMeasuring: String,
    ) {
        notifLocationLabel = locationLabel
        notifFlagEmoji = flagEmoji
        notifPingHost = pingHost
        notifPingPort = pingPort
        notifPingText = ""
        notifLabelConnected = labelConnected
        notifLabelConnecting = labelConnecting
        notifLabelFailed = labelFailed
        notifLabelDisconnect = labelDisconnect
        notifLabelCheckPing = labelCheckPing
        notifLabelPingUnavailable = labelPingUnavailable
        notifLabelMeasuring = labelMeasuring
        Log.d(TAG, "updateNotificationMeta: label=$locationLabel flag=$flagEmoji pingHost=$pingHost")
        refreshNotification()
    }

    // Unpacks the Intent MainActivity actually sends (see its comment on
    // why this has to be an Intent, not a direct call to a companion
    // `instance` — this service runs in its own ":RunWaveEngine" process)
    // and forwards to the in-process updateNotificationMeta() above.
    private fun handleUpdateNotificationMetaAction(intent: Intent) {
        updateNotificationMeta(
            locationLabel = intent.getStringExtra("locationLabel") ?: "WAVEBREAK",
            flagEmoji = intent.getStringExtra("flagEmoji") ?: "",
            pingHost = intent.getStringExtra("pingHost"),
            pingPort = if (intent.hasExtra("pingPort")) intent.getIntExtra("pingPort", 0) else null,
            labelConnected = intent.getStringExtra("labelConnected") ?: "Connected",
            labelConnecting = intent.getStringExtra("labelConnecting") ?: "Connecting…",
            labelFailed = intent.getStringExtra("labelFailed") ?: "Connection failed",
            labelDisconnect = intent.getStringExtra("labelDisconnect") ?: "Disconnect",
            labelCheckPing = intent.getStringExtra("labelCheckPing") ?: "Check ping",
            labelPingUnavailable = intent.getStringExtra("labelPingUnavailable") ?: "Unavailable",
            labelMeasuring = intent.getStringExtra("labelMeasuring") ?: "Measuring…",
        )
    }

    // pingHost's own cross-process counterpart to handleUpdateNotification
    // MetaAction above — same reasoning, plus a reply: MainActivity's
    // ResultReceiver (Parcelable, so it survives crossing the process
    // boundary inside this same Intent) is what actually gets the
    // measurement back to the Dart caller waiting on it. MainActivity
    // already confirmed a tunnel is active (and validated host/port)
    // before ever sending this — this service only exists in the first
    // place because that's true, so a bad request here just reports an
    // honest null the same way an unreachable host would, rather than a
    // dedicated error path for a case that shouldn't reach this point.
    private fun handlePingHostAction(intent: Intent) {
        val receiver = extractResultReceiver(intent) ?: return
        val host = intent.getStringExtra(EXTRA_PING_HOST)
        val port = intent.getIntExtra(EXTRA_PING_PORT, -1)
        val timeoutMs = intent.getIntExtra(EXTRA_PING_TIMEOUT_MS, 4000)
        if (host.isNullOrEmpty() || port <= 0) {
            receiver.send(0, Bundle())
            return
        }
        // pingHost()'s own socket.connect(address, timeoutMs) only bounds
        // the TCP handshake leg — `InetSocketAddress(host, port)` resolves
        // the hostname synchronously BEFORE that line ever runs, with no
        // timeout of its own. Android's resolver has no hard cap on a
        // slow/unreachable DNS path, so a bad lookup can block this
        // worker thread for far longer than the caller's intended
        // timeoutMs — the connection_test_service.dart side clamps that
        // value specifically to keep a stuck attempt from tying up a
        // protect()ed socket for too long (see its own comment on the
        // protect-socket server hitting EMFILE from exactly this kind of
        // long-lived attempt), and a DNS hang here would defeat that cap
        // entirely while still holding one of those same fds open.
        //
        // A watchdog bounds what the CALLER sees to timeoutMs regardless:
        // the worker thread is left to finish (or keep hanging on DNS) on
        // its own, but the ResultReceiver always fires within bounds, so
        // the Dart-side await this backs never hangs past what it asked
        // for. `responded` guards against both firing — Android logs (and
        // some versions throw) on a ResultReceiver used more than once.
        val responded = java.util.concurrent.atomic.AtomicBoolean(false)
        val watchdogHandler = Handler(Looper.getMainLooper())
        val watchdog = Runnable {
            if (responded.compareAndSet(false, true)) {
                Log.w(TAG, "pingHost: watchdog fired past ${timeoutMs}ms for $host:$port (likely a slow/hung DNS lookup)")
                receiver.send(0, Bundle())
            }
        }
        watchdogHandler.postDelayed(watchdog, (timeoutMs + 500).toLong())
        Thread({
            val ms = pingHost(host, port, timeoutMs)
            if (responded.compareAndSet(false, true)) {
                watchdogHandler.removeCallbacks(watchdog)
                val data = Bundle().apply { if (ms != null) putInt(EXTRA_PING_MS, ms) }
                receiver.send(0, data)
            }
        }, "WaveEnginePing").start()
    }

    // Bundle#getParcelable(String) is deprecated (API 33+) in favor of the
    // 2-arg overload, but the 2-arg one doesn't exist before API 33 — this
    // picks whichever is actually available at runtime instead of hard-
    // coding one and either warning or crashing on the other half of
    // devices.
    @Suppress("DEPRECATION")
    private fun extractResultReceiver(intent: Intent): ResultReceiver? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(EXTRA_RESULT_RECEIVER, ResultReceiver::class.java)
        } else {
            intent.getParcelableExtra(EXTRA_RESULT_RECEIVER)
        }
    }

    // Called from MainActivity.onResume() after a long-enough background
    // stretch — see its doc comment for why a UDP-based tunnel needs this
    // even when Android never reports a network change at all. Routes
    // through the exact same debounced scheduleReconnect() path a real
    // network-change event uses, so it gets the same stopOtherEngine()-safe
    // handling — no separate reconnect implementation to keep in sync.
    fun notifyAppForegrounded() {
        scheduleReconnect("app foregrounded after background stretch")
    }

    // The notification's own "check ping" button (expanded view only —
    // RemoteViews collapsed content has no room for it) — fires this same
    // ACTION_CHECK_PING through onStartCommand rather than binding a
    // Messenger/callback, since a PendingIntent is the only thing a
    // notification can actually invoke. host/port were resolved by Dart
    // (ConnectionTestService's own logic — Kotlin doesn't parse share
    // links) and handed over by updateNotificationMeta().
    private fun handleCheckPingAction() {
        val host = notifPingHost
        val port = notifPingPort
        if (host == null || port == null) {
            notifPingText = notifLabelPingUnavailable
            refreshNotification()
            return
        }
        notifPingText = notifLabelMeasuring
        refreshNotification()
        Thread({
            val ms = pingHost(host, port, 4000)
            notifPingText = if (ms != null) "$ms ms" else notifLabelPingUnavailable
            refreshNotification()
        }, "WaveEngineNotifPing").start()
    }

    private fun refreshNotification() {
        try {
            val manager = getSystemService(NotificationManager::class.java) ?: return
            manager.notify(NOTIFICATION_ID, buildNotification())
        } catch (t: Throwable) {
            Log.w(TAG, "refreshNotification failed", t)
        }
    }

    private fun pendingServiceIntent(action: String, requestCode: Int): PendingIntent {
        val intent = Intent(this, WaveEngineVpnService::class.java).apply { this.action = action }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        return PendingIntent.getService(this, requestCode, intent, flags)
    }

    // A fully custom RemoteViews notification instead of a stock
    // Notification.Builder layout — the only way to show the app's own
    // colors/wave motif, the selected location's flag, and a live ping
    // reading with its own "check" button, none of which the standard
    // template supports. Deliberately NOT DecoratedCustomViewStyle: that
    // keeps the system's own card/background wrapped AROUND the custom
    // content, which is exactly what read as "only the inside is
    // themed" — a plain system-grey card with a themed rectangle floating
    // inside it. Passing no style at all hands the ENTIRE notification
    // surface to notification_vpn_collapsed/expanded.xml's own
    // @drawable/notif_bg, so the gradient actually reaches every edge.
    // The trade-off is losing the system's small-icon-in-the-corner/
    // timestamp chrome and its own tap-to-expand affordance — setSmallIcon
    // still controls the status-bar icon regardless of style, and the
    // notification is still expandable by dragging same as any other
    // multi-height notification, just without the little chevron hint.
    private fun buildNotification(): Notification {
        val channelId = "wavebreak_vpn"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            val channel = NotificationChannel(channelId, "WAVEBREAK VPN", NotificationManager.IMPORTANCE_LOW)
            manager.createNotificationChannel(channel)
        }

        val flagAndLocation = if (notifFlagEmoji.isNotEmpty()) {
            "$notifFlagEmoji $notifLocationLabel"
        } else {
            notifLocationLabel
        }
        val statusLine = if (notifPingText.isNotEmpty()) {
            "$notifStatusText · $notifPingText"
        } else {
            notifStatusText
        }

        val collapsed = RemoteViews(packageName, R.layout.notification_vpn_collapsed).apply {
            setTextViewText(R.id.notif_location, flagAndLocation)
            setTextViewText(R.id.notif_status, statusLine)
            setOnClickPendingIntent(R.id.notif_disconnect, pendingServiceIntent(ACTION_STOP, 1))
        }

        val expanded = RemoteViews(packageName, R.layout.notification_vpn_expanded).apply {
            setTextViewText(R.id.notif_location_exp, flagAndLocation)
            setTextViewText(R.id.notif_status_exp, notifStatusText)
            setTextViewText(R.id.notif_ping_exp, notifPingText)
            setTextViewText(R.id.notif_check_ping_label, notifLabelCheckPing)
            setTextViewText(R.id.notif_disconnect_label, notifLabelDisconnect)
            setOnClickPendingIntent(R.id.notif_check_ping, pendingServiceIntent(ACTION_CHECK_PING, 2))
            setOnClickPendingIntent(R.id.notif_disconnect_exp, pendingServiceIntent(ACTION_STOP, 1))
        }

        return Notification.Builder(this, channelId)
            .setSmallIcon(R.drawable.ic_stat_wavebreak)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            // The standard category for an ongoing foreground-service
            // notification — on stock Android this is what keeps it
            // grouped with other "current activity" notifications rather
            // than sorted purely by post time (which is what put a fresh
            // Telegram message above this one, confirmed on-device). Not
            // guaranteed on every OEM shade (MIUI's own notification list
            // implementation may not honor it the same way AOSP's does),
            // but it's the real API surface for this rather than
            // something to route around.
            .setCategory(Notification.CATEGORY_SERVICE)
            .setCustomContentView(collapsed)
            .setCustomBigContentView(expanded)
            .build()
    }

    companion object {
        private const val TAG = "WaveEngineVpnService"
        private const val TUN_ADDRESS = "26.26.26.1"
        private const val TUN_MTU = 1500
        private const val NOTIFICATION_ID = 2

        // Split-tunneling via VpnService.Builder.addDisallowedApplication()
        // — Android's own per-app tunnel-exclusion mechanism, the same one
        // NordVPN/ExpressVPN call "split tunneling." Real-device testing
        // found Russian marketplace apps actively detect an active VPN and
        // refuse to proceed ("отключите VPN") once connected — routing
        // their own traffic around the tunnel entirely (rather than trying
        // to out-fingerprint their detection, which is the fragile,
        // whack-a-mole path) makes WAVEBREAK invisible to them by
        // construction. A curated set rather than scattered literals so
        // it's a one-line add per future app — no per-app-toggle UI yet,
        // that's future work. Package names verified against their
        // current Google Play Store listings (not guessed):
        // - Wildberries: com.wildberries.ru
        // - Ozon: ru.ozon.app.android
        private val RU_VPN_DETECTING_APPS = setOf(
            "com.wildberries.ru",
            "ru.ozon.app.android",
        )
        private const val XRAY_SOCKS_PORT = 1080
        // This device's fd limit is 32768. 8000/20s used to be the
        // threshold here, on the assumption the leak trends up gradually —
        // confirmed on-device that assumption doesn't hold under repeated
        // server switching: one 20s window read a healthy count, the very
        // next read 32765 (3 fds of headroom left, already past the point
        // a reconnect's own dlopen/loadLibrary bookkeeping could succeed —
        // "UnsatisfiedLinkError: dlopen failed" is what a process that
        // truly cannot open one more fd for ANYTHING looks like, not a
        // missing library). A lower threshold and a tighter poll interval
        // can't fix the underlying leak (still unresolved — see the class
        // doc), but they buy real margin: catching it at 4000/8s instead
        // of 8000/20s means a reconnect still has ~28000 fds of room to
        // work with instead of 3.
        private const val FD_WARN_THRESHOLD = 4000
        private const val FD_CHECK_INTERVAL_MS = 8_000L

        // See scheduleHealthCheck()'s doc comment for the bug this exists
        // for. 1.1.1.1:443 — same stable, fast, TLS-capable public target
        // already used elsewhere in this app for reachability probes
        // (ConnectionTestService's own pattern on the Dart side); no
        // WAVEBREAK-operated endpoint needed.
        private const val HEALTH_CHECK_HOST = "1.1.1.1"
        private const val HEALTH_CHECK_PORT = 443
        private const val HEALTH_CHECK_TIMEOUT_MS = 6_000
        private const val HEALTH_CHECK_INTERVAL_MS = 45_000L
        private const val HEALTH_CHECK_RETRY_MS = 10_000L
        private const val HEALTH_CHECK_FAILURE_THRESHOLD = 2

        // See reconnectNow()'s own doc comment for the bug this exists to
        // fix: without a real gap here, tearing down and re-establishing
        // the tun interface back-to-back on the same thread never gives
        // Android's connectivity stack (or any other app watching for a
        // network change) a chance to observe the old interface as
        // actually gone before the new one appears. Long enough to be a
        // real, observable transition; short enough that a user actively
        // watching a reconnect never perceives it as a separate stall.
        private const val RECONNECT_INTERFACE_DOWN_GAP_MS = 500L

        // Per-process, not a fixed name: a prior WaveEngineVpnService
        // process that died without a clean onDestroy (OOM-killed, force-
        // stopped mid-connect, or MIUI's own background killer) can leave
        // this abstract-namespace Unix socket bound with nothing left to
        // ever release it — LocalServerSocket has no SO_REUSEADDR-style
        // escape hatch, so a fresh process reusing the same fixed name
        // would fail to bind at all. Confirmed on-device: "protect server
        // failed to start" / "Address already in use", from a BRAND NEW
        // process's very first connection attempt — no amount of retrying
        // helped because there was nothing transient about it. Folding
        // this process's own pid into the name means a new process can
        // never collide with whatever an old one left behind.
        private val PROTECT_SOCKET_NAME = "wavebreak_protect_${android.os.Process.myPid()}"

        const val ACTION_STOP = "app.wavebreak.engine.STOP"
        const val ACTION_CHECK_PING = "app.wavebreak.engine.CHECK_PING"
        const val ACTION_STATUS = "app.wavebreak.engine.STATUS"
        const val EXTRA_LINK = "link"
        const val EXTRA_XRAY_CONFIG = "xray_config"
        const val EXTRA_STATE = "state"
        const val EXTRA_ERROR_DETAIL = "error_detail"
        const val STATE_CONNECTING = "CONNECTING"
        const val STATE_CONNECTED = "CONNECTED"
        const val STATE_FAILED = "FAILED"
        const val STATE_IDLE = "IDLE"

        const val ACTION_PING_HOST = "app.wavebreak.engine.PING_HOST"
        const val ACTION_UPDATE_NOTIFICATION_META = "app.wavebreak.engine.UPDATE_NOTIFICATION_META"
        const val ACTION_APP_FOREGROUNDED = "app.wavebreak.engine.APP_FOREGROUNDED"
        const val EXTRA_PING_HOST = "ping_host"
        const val EXTRA_PING_PORT = "ping_port"
        const val EXTRA_PING_TIMEOUT_MS = "ping_timeout_ms"
        const val EXTRA_RESULT_RECEIVER = "result_receiver"
        const val EXTRA_PING_MS = "ping_ms"
    }
}
