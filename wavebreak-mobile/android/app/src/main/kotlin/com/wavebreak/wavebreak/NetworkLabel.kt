package com.wavebreak.wavebreak

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager

/**
 * What network the tunnel runs over, for the diagnostic log: "Wi-Fi" or
 * "mobile <operator>" (e.g. "mobile MegaFon"). Field reports then show
 * which transport works on which carrier. The VPN's own network is
 * skipped — it's the underlying one that matters. No permission beyond
 * ACCESS_NETWORK_STATE: the operator name is the public network name
 * (TelephonyManager.networkOperatorName), not the SIM or the number.
 *
 * With two SIMs it is the one carrying mobile data: the plain
 * TelephonyManager answers for the default (voice) SIM — a phone on
 * MegaFon data with an Alfa SIM for calls was logged as "mobile Alfa".
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
                val operator = dataOperator(context)
                if (operator.isEmpty()) "mobile" else "mobile $operator"
            }
            else -> "no network"
        }
    }

    private fun dataOperator(context: Context): String {
        val tm = context.getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
            ?: return ""
        val dataSub = SubscriptionManager.getDefaultDataSubscriptionId()
        val forData = if (dataSub != SubscriptionManager.INVALID_SUBSCRIPTION_ID) {
            runCatching { tm.createForSubscriptionId(dataSub) }.getOrNull()
        } else null
        val t = forData ?: tm
        val name = t.networkOperatorName?.trim().orEmpty()
        // A virtual operator (Alfa, …) often names the network after its
        // own brand: add whose radio network it really is.
        val host = hostNetworks[t.networkOperator?.trim().orEmpty()] ?: return name
        return when {
            name.isEmpty() -> host
            name.contains(host, ignoreCase = true) -> name
            else -> "$name ($host)"
        }
    }

    /** Russian MCC+MNC → the network that carries the radio traffic. */
    private val hostNetworks = mapOf(
        "25001" to "MTS",
        "25002" to "MegaFon",
        "25011" to "Yota",
        "25020" to "Tele2",
        "25099" to "Beeline",
    )
}
