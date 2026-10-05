package com.wavebreak.wavebreak

import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Quick actions without opening the app — the Quick Settings tile. Each
 * one is handed to the Dart side over "app.wavebreak/quick" and run by the same
 * ConnectionManager code as the home screen (Core access grant, engine
 * start). The engine is started headless if the process was cold; actions
 * wait in [pending] until Dart reports "ready".
 *
 * Dart answers with a map: {result: "ok"} or {result: "open_app",
 * message: "…"} when it needs the screen (not signed in, VPN consent not
 * given yet, no subscription).
 */
object QuickActions {
    private const val TAG = "QuickActions"

    /** Written by the Dart side: locations, current one, labels. */
    const val SNAPSHOT_FILE = "quick_locations.json"

    class Outcome(val openApp: Boolean, val message: String?)

    private var channel: MethodChannel? = null
    private var ready = false
    private val pending = ArrayList<Pair<Map<String, Any?>, (Outcome) -> Unit>>()
    private val main = Handler(Looper.getMainLooper())

    fun register(engine: FlutterEngine, app: Context) {
        ready = false
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, "app.wavebreak/quick").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "ready" -> {
                        ready = true
                        val queued = ArrayList(pending)
                        pending.clear()
                        queued.forEach { (args, done) -> send(args, done) }
                        result.success(null)
                    }
                    // The connection state changed: the tile follows it.
                    "stateChanged" -> {
                        QuickTileService.refresh(app)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    /** Runs [type] on the Dart side; [done] is always called once, on the main thread. */
    fun dispatch(context: Context, type: String, locationId: String? = null, done: (Outcome) -> Unit) {
        main.post {
            var finished = false
            val once: (Outcome) -> Unit = { if (!finished) { finished = true; done(it) } }
            try {
                AppEngine.get(context)
            } catch (t: Throwable) {
                // No engine (e.g. out of memory on a weak phone): the
                // app itself is the only way left.
                Log.w(TAG, "engine start failed", t)
                once(Outcome(true, null))
                return@post
            }
            val args = mapOf("type" to type, "locationId" to locationId)
            // A Dart side that never answers (crashed boot) must not hang
            // the caller: a broadcast has ~10 s before Android kills it.
            main.postDelayed({ once(Outcome(false, null)) }, 9_000)
            try {
                if (ready) send(args, once) else pending.add(args to once)
            } catch (t: Throwable) {
                Log.w(TAG, "quick action not delivered", t)
                once(Outcome(false, null))
            }
        }
    }

    private fun send(args: Map<String, Any?>, done: (Outcome) -> Unit) {
        val ch = channel ?: return done(Outcome(false, null))
        ch.invokeMethod("action", args, object : MethodChannel.Result {
            override fun success(result: Any?) {
                val map = result as? Map<*, *>
                done(Outcome(map?.get("result") == "open_app", map?.get("message") as? String))
            }

            override fun error(code: String, message: String?, details: Any?) {
                Log.w(TAG, "quick action failed: $code $message")
                done(Outcome(false, null))
            }

            override fun notImplemented() = done(Outcome(false, null))
        })
    }

    fun launchIntent(context: Context): Intent =
        (context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: Intent(context, MainActivity::class.java))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
}

