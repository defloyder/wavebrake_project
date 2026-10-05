package com.wavebreak.wavebreak

import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.util.Log
import org.json.JSONObject

/**
 * WAVEBREAK in the phone's Quick Settings (next to Wi-Fi, mobile data,
 * flashlight): on = our VPN is up, the subtitle names the server. A tap
 * connects to the last server or disconnects — through the same Dart
 * logic as the app's own button ([QuickActions]). When that needs the
 * screen (not signed in, VPN consent not given yet), the app opens.
 */
class QuickTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        update(busy = false)
    }

    override fun onClick() {
        super.onClick()
        update(busy = true)
        QuickActions.dispatch(applicationContext, "toggle") { outcome ->
            if (outcome.openApp) openApp() else update(busy = false)
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

    private fun update(busy: Boolean) {
        val tile = qsTile ?: return
        val snapshot = readSnapshot(this)
        val on = AppChannels.isSystemVpnActive(this)
        tile.state = when {
            busy -> Tile.STATE_UNAVAILABLE
            on -> Tile.STATE_ACTIVE
            else -> Tile.STATE_INACTIVE
        }
        tile.label = "WAVEBREAK"
        tile.icon = android.graphics.drawable.Icon.createWithResource(this, R.drawable.ic_tile_wavebreak)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.subtitle = when {
                busy -> snapshot?.optString("tileBusy").orEmpty()
                on -> snapshot?.optString("tileSubtitle").orEmpty()
                else -> snapshot?.optString("tileOff").orEmpty()
            }.ifEmpty { null }
        }
        tile.updateTile()
    }

    companion object {
        private const val TAG = "QuickTileService"

        /** Ask the system to re-read the tile (it calls onStartListening). */
        fun refresh(context: Context) {
            try {
                requestListeningState(context, ComponentName(context, QuickTileService::class.java))
            } catch (t: Throwable) {
                Log.w(TAG, "tile refresh failed", t)
            }
        }

        fun readSnapshot(context: Context): JSONObject? = try {
            val f = java.io.File(context.filesDir, QuickActions.SNAPSHOT_FILE)
            if (f.exists()) JSONObject(f.readText()) else null
        } catch (t: Throwable) {
            null
        }
    }
}
