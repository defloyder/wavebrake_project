package com.wavebreak.wavebreak

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings

/**
 * Always-on VPN reliability: see the manifest's own comment on
 * REQUEST_IGNORE_BATTERY_OPTIMIZATIONS for why this exists. Doze/App
 * Standby can defer this app's background work (health-check callbacks,
 * holding a live QUIC/UDP session through an extended deep-sleep window)
 * even with the VpnService's foreground notification giving it SOME
 * exemption — not a full one. This is the standard, user-visible way to
 * ask for the rest: Android has no silent grant path for this, the system
 * dialog is unavoidable and that's by design (it's the user's battery to
 * spend, not this app's decision alone).
 */
object BatteryOptimization {
    fun isIgnoringBatteryOptimizations(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(context.packageName)
    }

    /**
     * The direct per-app exemption prompt — a single system dialog, not a
     * trip through Settings. ACTION_IGNORE_BATTERY_OPTIMIZATIONS_SETTINGS
     * (the general list) is deliberately not used here: this is the
     * targeted one-tap version for exactly this app, which is what
     * Android's own docs recommend for an app with a real, ongoing
     * background purpose like a VPN.
     */
    fun requestIgnoreBatteryOptimizationsIntent(context: Context): Intent {
        return Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
            data = Uri.parse("package:${context.packageName}")
        }
    }
}
