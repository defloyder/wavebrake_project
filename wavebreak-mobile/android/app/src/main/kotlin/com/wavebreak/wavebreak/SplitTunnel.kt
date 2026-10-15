package com.wavebreak.wavebreak

import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import java.io.ByteArrayOutputStream

/**
 * Per-app split tunneling (owner, 15.10; like Happ): the apps the user
 * sends past the tunnel. Stored natively, not in Flutter's preferences,
 * because the VPN service reads it in establish() — also when it is
 * started by the Quick Settings tile or always-on VPN with no Flutter
 * engine running.
 */
object SplitTunnel {
    private const val PREFS = "wavebreak_split_tunnel"
    private const val KEY_BYPASS = "bypass"
    private const val ICON_PX = 96

    fun userBypass(context: Context): Set<String> =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getStringSet(KEY_BYPASS, emptySet())
            ?.toSet() ?: emptySet()

    fun setUserBypass(context: Context, packages: Collection<String>) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putStringSet(KEY_BYPASS, packages.map { it.trim() }.filter { it.isNotEmpty() }.toSet())
            .apply()
    }

    /**
     * Apps with a launcher entry (phone launcher or the TV's leanback
     * one), this app left out: id, label, a small PNG icon, and whether
     * it came with the system. Slow on a phone with many apps — call off
     * the main thread.
     */
    fun installedApps(context: Context): List<Map<String, Any?>> {
        val pm = context.packageManager
        val seen = LinkedHashMap<String, ApplicationInfo>()
        for (category in listOf(Intent.CATEGORY_LAUNCHER, Intent.CATEGORY_LEANBACK_LAUNCHER)) {
            val intent = Intent(Intent.ACTION_MAIN).addCategory(category)
            for (ri in pm.queryIntentActivities(intent, 0)) {
                val info = ri.activityInfo?.applicationInfo ?: continue
                seen.putIfAbsent(info.packageName, info)
            }
        }
        seen.remove(context.packageName)
        return seen.values.map { info ->
            mapOf(
                "id" to info.packageName,
                "label" to pm.getApplicationLabel(info).toString(),
                "icon" to runCatching { iconPng(pm.getApplicationIcon(info)) }.getOrNull(),
                "system" to ((info.flags and ApplicationInfo.FLAG_SYSTEM) != 0 &&
                    (info.flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) == 0),
            )
        }.sortedBy { (it["label"] as String).lowercase() }
    }

    private fun iconPng(drawable: Drawable): ByteArray {
        val bitmap = Bitmap.createBitmap(ICON_PX, ICON_PX, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, ICON_PX, ICON_PX)
        drawable.draw(canvas)
        val out = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
        bitmap.recycle()
        return out.toByteArray()
    }
}

/**
 * Every package to exclude from the tunnel, in order and each once: this
 * app itself (its Core API calls go direct), the built-in [safetyNet]
 * (apps that refuse to work behind a VPN — always direct, whatever the
 * user chose), then the user's own choice. Blank entries are dropped.
 */
internal fun excludedPackages(
    own: String,
    safetyNet: Collection<String>,
    user: Collection<String>,
): Set<String> {
    val out = LinkedHashSet<String>()
    out.add(own)
    out.addAll(safetyNet)
    for (p in user) {
        val name = p.trim()
        if (name.isNotEmpty()) out.add(name)
    }
    return out
}
