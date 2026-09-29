package com.wavebreak.wavebreak

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.telephony.TelephonyManager

/**
 * What network the tunnel runs over, for the diagnostic log: "Wi-Fi" or
 * "mobile <operator>" (e.g. "mobile MegaFon"). Field reports then show
 * which transport works on which carrier. The VPN's own network is
 * skipped — it's the underlying one that matters. No permission beyond
 * ACCESS_NETWORK_STATE: the operator name is the public network name
 * (TelephonyManager.networkOperatorName), not the SIM or the number.
 */
object NetworkLabel {
    fun describe(context: Context): String {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        var wifi = false
        var cellular = false
        var ethernet = false
        @Suppress("DEPRECATION")
        for (network in cm.allNetworks) {
            val caps = cm.getNetworkCapabilities(network) ?: continue
            if (caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) continue
            if (!caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) continue
            when {
                caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> wifi = true
                caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> cellular = true
                caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> ethernet = true
            }
        }
        // Android routes over Wi-Fi when both are up.
        return when {
            wifi -> "Wi-Fi"
            ethernet -> "Ethernet"
            cellular -> {
                val tm = context.getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
                val operator = tm?.networkOperatorName?.trim().orEmpty()
                if (operator.isEmpty()) "mobile" else "mobile $operator"
            }
            else -> "no network"
        }
    }
}
