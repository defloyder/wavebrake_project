package com.wavebreak.wavebreak

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** H1: which network callbacks restart the engine. */
class NetworkChangePolicyTest {
    @Test
    fun firstNetworkIsNotAChange() {
        assertFalse(networkChangeNeedsReconnect(null, "wifi", wasLost = false, outageMs = 0))
    }

    @Test
    fun sameNetworkBackAfterBlipDoesNotReconnect() {
        assertFalse(networkChangeNeedsReconnect("wifi", "wifi", wasLost = true, outageMs = 800))
        assertFalse(networkChangeNeedsReconnect("wifi", "wifi", wasLost = true, outageMs = NETWORK_BLIP_MS - 1))
    }

    @Test
    fun sameNetworkBackAfterLongOutageReconnects() {
        assertTrue(networkChangeNeedsReconnect("wifi", "wifi", wasLost = true, outageMs = NETWORK_BLIP_MS))
    }

    @Test
    fun sameNetworkNeverLostDoesNotReconnect() {
        assertFalse(networkChangeNeedsReconnect("wifi", "wifi", wasLost = false, outageMs = 0))
    }

    @Test
    fun differentNetworkReconnects() {
        assertTrue(networkChangeNeedsReconnect("wifi", "lte", wasLost = false, outageMs = 0))
        assertTrue(networkChangeNeedsReconnect("wifi", "lte", wasLost = true, outageMs = 100))
    }
}
