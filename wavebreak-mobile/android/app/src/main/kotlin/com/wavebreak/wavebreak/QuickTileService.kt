package com.wavebreak.wavebreak

import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.util.Log
import androidx.core.content.ContextCompat
import org.json.JSONObject

/**
 * WAVEBREAK in the phone's Quick Settings (next to Wi-Fi, mobile data,
 * flashlight): on = our VPN is up, the subtitle names the server. A tap
 * connects to the last server or disconnects — through the same Dart
 * logic as the app's own button ([QuickActions]). When that needs the
 * screen (not signed in, VPN consent not given yet), the app opens.
 *
 * The tap decides "on" or "off" from the system's real VPN state, never
 * from the Dart side's (which can lag after a process restart — it then
 * connected when the user meant to disconnect). The tile is never put in
 * STATE_UNAVAILABLE: the system drops taps on an unavailable tile, and a
 * lost refresh left it deaf. "Off" has a native fallback: if the VPN is
 * still up a moment later, the service is stopped directly.
 */
class QuickTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        update()
    }

    override fun onClick() {
        super.onClick()
        if (busy) return
        busy = true
        val app = applicationContext
        val wasOn = AppChannels.isSystemVpnActive(app)
        show(active = !wasOn, subtitle = readSnapshot(app)?.optString("tileBusy"))
        // Safety: never stay "busy" for long, whatever happens below.
        main.postDelayed({ busy = false }, 15_000)
        try {
            QuickActions.dispatch(app, if (wasOn) "off" else "on") { outcome ->
                busy = false
                when {
                    outcome.openApp -> openApp()
                    wasOn -> ensureStopped(app)
                }
                update()
            }
        } catch (t: Throwable) {
            Log.w(TAG, "tile action failed", t)
            busy = false
            if (wasOn) ensureStopped(app) else openApp()
        }
    }

    private fun openApp() {
        val intent = QuickActions.launchIntent(this)
        try {
            if (Build.VERSION.SDK_INT >= 34) {
                startActivityAndCollapse(
                    PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_IMMUTABLE),
                )
            } else {
                @Suppress("DEPRECATION")
                startActivityAndCollapse(intent)
            }
        } catch (t: Throwable) {
            Log.w(TAG, "could not open the app", t)
        }
    }

    private fun show(active: Boolean, subtitle: String?) {
        val tile = qsTile ?: return
        try {
            tile.state = if (active) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
            tile.label = "WAVEBREAK"
            tile.icon = Icon.createWithResource(this, R.drawable.ic_tile_wavebreak)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                tile.subtitle = subtitle?.ifEmpty { null }
            }
            tile.updateTile()
        } catch (t: Throwable) {
            Log.w(TAG, "tile update failed", t)
        }
    }

    private fun update() {
        val snapshot = readSnapshot(this)
        val on = AppChannels.isSystemVpnActive(this)
        show(
            active = on,
            subtitle = if (on) snapshot?.optString("tileSubtitle") else snapshot?.optString("tileOff"),
        )
    }

    companion object {
        private const val TAG = "QuickTileService"
        private val main = Handler(Looper.getMainLooper())

        @Volatile
        private var busy = false

        /** Ask the system to re-read the tile (it calls onStartListening). */
        fun refresh(context: Context) {
            try {
                requestListeningState(context, ComponentName(context, QuickTileService::class.java))
            } catch (t: Throwable) {
                Log.w(TAG, "tile refresh failed", t)
            }
        }

        /** "Off" must turn the VPN off even if the Dart side didn't. */
        private fun ensureStopped(context: Context) {
            main.postDelayed({
                if (!AppChannels.isSystemVpnActive(context)) return@postDelayed
                try {
                    val stop = Intent(context, WaveEngineVpnService::class.java)
                        .setAction(WaveEngineVpnService.ACTION_STOP)
                    ContextCompat.startForegroundService(context, stop)
                } catch (t: Throwable) {
                    Log.w(TAG, "direct stop failed", t)
                }
                refresh(context)
            }, 2_500)
        }

        fun readSnapshot(context: Context): JSONObject? = try {
            val f = java.io.File(context.filesDir, QuickActions.SNAPSHOT_FILE)
            if (f.exists()) JSONObject(f.readText()) else null
        } catch (t: Throwable) {
            null
        }
    }
}
