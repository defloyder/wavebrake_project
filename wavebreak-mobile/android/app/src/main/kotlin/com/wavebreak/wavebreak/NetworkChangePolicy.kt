package com.wavebreak.wavebreak

/**
 * How long the same default network may disappear and come back before it
 * counts as a real outage (sockets on it likely dead) rather than a blip.
 * Field logs: the blip right after establish() lasts well under a second.
 */
const val NETWORK_BLIP_MS = 3_000L

/**
 * Whether a newly available default network means the tunnel must be
 * re-dialled. [previous] is the network it was using (or the one just
 * lost); [wasLost] and [outageMs] describe a loss in between.
 *
 * - First network ever seen: nothing to redo.
 * - A different network (Wi-Fi <-> mobile): reconnect.
 * - The same network back after a real outage: reconnect.
 * - The same network back after a blip: keep the running session.
 */
fun <N> networkChangeNeedsReconnect(previous: N?, current: N, wasLost: Boolean, outageMs: Long): Boolean {
    if (previous == null) return false
    if (previous != current) return true
    return wasLost && outageMs >= NETWORK_BLIP_MS
}
