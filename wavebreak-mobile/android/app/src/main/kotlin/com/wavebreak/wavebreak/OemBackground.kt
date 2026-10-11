package com.wavebreak.wavebreak

import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log

/**
 * The phone makers' own background limits on top of Android's Doze.
 * MIUI / HyperOS (Xiaomi, Redmi, POCO) freeze a background app — its
 * VPN engine process too, foreground service or not — unless the app's
 * battery saver is "No restrictions" and Autostart is allowed: the tunnel
 * stays "connected" but passes nothing until the app is opened.
 *
 * Each screen is tried by its known component; any phone without it gets
 * the app's own system settings page, where the same switches live.
 */
object OemBackground {
    private const val TAG = "OemBackground"

    fun isXiaomi(): Boolean {
        val maker = (Build.MANUFACTURER ?: "").lowercase()
        val brand = (Build.BRAND ?: "").lowercase()
        return listOf("xiaomi", "redmi", "poco").any { maker.contains(it) || brand.contains(it) }
    }

    fun openBatterySaver(context: Context) {
        val pkg = context.packageName
        val label = context.applicationInfo.loadLabel(context.packageManager).toString()
        val candidates = if (isXiaomi()) listOf(
            Intent("miui.intent.action.HIDDEN_APPS_CONFIG_ACTIVITY").apply {
                component = ComponentName(
                    "com.miui.powerkeeper",
                    "com.miui.powerkeeper.ui.HiddenAppsConfigActivity",
                )
                putExtra("package_name", pkg)
                putExtra("package_label", label)
            },
            Intent("miui.intent.action.POWER_HIDE_MODE_APP_LIST").apply {
                putExtra("package_name", pkg)
                putExtra("package_label", label)
            },
        ) else emptyList()
        open(context, candidates + appDetails(pkg))
    }

    fun openAutostart(context: Context) {
        val pkg = context.packageName
        val candidates = if (isXiaomi()) listOf(
            Intent().apply {
                component = ComponentName(
                    "com.miui.securitycenter",
                    "com.miui.permcenter.autostart.AutoStartManagementActivity",
                )
            },
        ) else emptyList()
        open(context, candidates + appDetails(pkg))
    }

    private fun appDetails(pkg: String) =
        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$pkg"))

    private fun open(context: Context, intents: List<Intent>) {
        for (intent in intents) {
            try {
                if (context !is Activity) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(intent)
                return
            } catch (t: Throwable) {
                Log.w(TAG, "screen unavailable: ${intent.component ?: intent.action}")
            }
        }
    }
}
