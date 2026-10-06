package com.wavebreak.wavebreak

import android.content.Context
import java.io.File
import java.security.SecureRandom

/**
 * This installation's id for Core's device registration (sent as
 * `install_id`): signing in again returns the same device instead of
 * taking another subscription slot.
 *
 * Kept in noBackupFilesDir, not in shared preferences: Android backs
 * preferences up and restores them on a new phone, and two phones with one
 * id would share one device record. Survives sign-out; gone on uninstall
 * or "clear data".
 */
object InstallId {
    private const val FILE = "install-id"

    @Synchronized
    fun get(context: Context): String {
        val file = File(context.noBackupFilesDir, FILE)
        runCatching { file.readText().trim() }.getOrNull()
            ?.takeIf { it.length == 32 }
            ?.let { return it }
        val bytes = ByteArray(16).also { SecureRandom().nextBytes(it) }
        val id = bytes.joinToString("") { "%02x".format(it) }
        file.writeText(id)
        return id
    }
}
