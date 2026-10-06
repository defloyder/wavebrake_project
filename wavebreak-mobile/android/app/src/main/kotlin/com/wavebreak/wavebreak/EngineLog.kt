package com.wavebreak.wavebreak

import android.content.Context
import android.util.Log
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * The VPN service's own diagnostic log, kept on disk (two files of up to
 * 256 KB, newest last): network changes, screen off/on, health checks with
 * their latency, reconnects and their reasons. logcat on a phone keeps
 * only minutes, and the app's in-memory log is gone with its process —
 * neither held anything about a stall that happened overnight. Added to
 * the exported diagnostic log (Support > Export diagnostic logs).
 * No secrets: never links, keys or addresses of the user's traffic.
 */
object EngineLog {
    private const val TAG = "EngineLog"
    private const val FILE = "engine-log.txt"
    private const val MAX_BYTES = 256 * 1024
    private val time = SimpleDateFormat("MM-dd HH:mm:ss.SSS", Locale.US)

    @Synchronized
    fun write(context: Context, line: String) {
        Log.i(TAG, line)
        try {
            val f = File(context.filesDir, FILE)
            if (f.length() > MAX_BYTES) {
                val old = File(context.filesDir, "$FILE.1")
                old.delete()
                f.renameTo(old)
            }
            f.appendText("${time.format(Date())} $line\n")
        } catch (t: Throwable) {
            Log.w(TAG, "write failed", t)
        }
    }

    /** Both files, oldest first; empty when there's nothing yet. */
    @Synchronized
    fun read(context: Context): String = try {
        listOf("$FILE.1", FILE)
            .map { File(context.filesDir, it) }
            .filter { it.exists() }
            .joinToString("") { it.readText() }
    } catch (t: Throwable) {
        ""
    }
}
