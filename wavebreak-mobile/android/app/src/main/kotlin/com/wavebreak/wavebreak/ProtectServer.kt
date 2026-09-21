package com.wavebreak.wavebreak

import android.net.LocalServerSocket
import android.net.LocalSocket
import android.net.VpnService
import android.os.ParcelFileDescriptor
import android.system.Os
import android.util.Log
import java.io.IOException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * Android's VpnService captures ALL traffic from this app's own UID by
 * default — including the outbound sockets Xray-core/Hysteria open to the
 * real remote server — unless each one is explicitly handed to
 * VpnService.protect() before it connects. Without this, those sockets
 * loop right back into the very tunnel they're trying to feed: the TUN
 * comes up, the app shows "Connected", but nothing ever reaches the
 * internet (this is what was actually happening after tun2socks moved
 * in-process and the phantom-process-kill and go.Seq issues were both
 * already fixed — every layer looked healthy in isolation, right up to
 * this one).
 *
 * This is the Kotlin half of the standard Android-VPN "protect socket"
 * pattern: native/hysteria_bridge's protect.go uses
 * github.com/sagernet/sing/common/control's ProtectPath, which connects
 * to a Unix domain socket and sends the fd it wants protected as
 * ancillary (SCM_RIGHTS) data, then blocks for a 1-byte ack. This class
 * is the server side of that protocol — LocalServerSocket listens in
 * Android's abstract namespace, so the path Bridge.setProtectPath() is
 * given must be NUL-prefixed to match (see WaveEngineVpnService).
 */
class ProtectServer(private val vpnService: VpnService, private val name: String) {
    @Volatile private var running = false
    private var serverSocket: LocalServerSocket? = null
    private var thread: Thread? = null

    // Bridge.setProtectPath() is called immediately after this returns,
    // and the very next thing that happens is an engine dialing out and
    // trying to protect() its socket through that path — so callers need
    // a real guarantee the socket is actually bound and accept()-ready,
    // not just that a thread was told to start one eventually.
    // LocalServerSocket's constructor does the bind/listen synchronously,
    // but on its OWN thread here (this class is otherwise reused as a
    // background accept loop), so a latch bridges that back to the
    // caller. Confirmed on-device without this: the first connection
    // attempt after switching servers routinely lost the race and failed
    // with "connect protect path: connection refused", while a retry a
    // moment later succeeded once the server had caught up.
    fun start() {
        if (running) return
        running = true
        val ready = CountDownLatch(1)
        thread = Thread({
            try {
                val server = bindWithRetry()
                serverSocket = server
                ready.countDown()
                while (running) {
                    val client = try {
                        server.accept()
                    } catch (e: Exception) {
                        if (running) Log.e(TAG, "protect server accept failed", e)
                        break
                    }
                    handleClient(client)
                }
            } catch (t: Throwable) {
                Log.e(TAG, "protect server failed to start", t)
                ready.countDown()
            }
        }, "WaveEngineProtectServer").apply { start() }
        ready.await(2, TimeUnit.SECONDS)
    }

    // Switching locations tears the whole service down (stopAll() calls
    // stopSelf()) and immediately spins a fresh one back up for the new
    // connection — sometimes fast enough that the OLD instance's
    // LocalServerSocket, bound to this same abstract-namespace name,
    // hasn't actually been released by the kernel yet when the NEW one
    // tries to bind. Confirmed on-device: "protect server failed to
    // start" / "Address already in use", right as a location switch
    // reconnected — with no server listening at all, every protect()
    // request after that silently has nowhere to go, and the new
    // connection "succeeds" at the tunnel level while its actual traffic
    // loops back into itself. The old binding releases within
    // milliseconds once that dying process finishes tearing down, so a
    // short retry is all this needs rather than failing outright.
    private fun bindWithRetry(): LocalServerSocket {
        var attempt = 0
        while (true) {
            try {
                return LocalServerSocket(name)
            } catch (e: IOException) {
                attempt++
                if (attempt >= 10) throw e
                Thread.sleep(150)
            }
        }
    }

    private fun handleClient(client: LocalSocket) {
        Thread({
            try {
                client.soTimeout = 2000
                // The dummy byte sent alongside the ancillary fd data must
                // actually be read before the fds show up on
                // getAncillaryFileDescriptors() — that's how Android's
                // LocalSocket surfaces SCM_RIGHTS payloads.
                val buf = ByteArray(1)
                client.inputStream.read(buf)
                val fds = client.ancillaryFileDescriptors
                var ok = false
                if (fds != null && fds.isNotEmpty()) {
                    for (fd in fds) {
                        // java.io.FileDescriptor doesn't expose its raw int
                        // publicly — dup() into a ParcelFileDescriptor to
                        // get one, then close that wrapper. Receiving an fd
                        // over SCM_RIGHTS (which getAncillaryFileDescriptors
                        // surfaces) hands this process its OWN duplicate
                        // pointing at the same underlying socket — Go's own
                        // copy is unaffected by protect() (it applies to the
                        // shared kernel socket, not this specific fd number)
                        // or by closing ours afterward, which just avoids
                        // leaking fds in this process.
                        val pfd = ParcelFileDescriptor.dup(fd)
                        try {
                            ok = vpnService.protect(pfd.fd) || ok
                        } finally {
                            pfd.close()
                            try {
                                Os.close(fd)
                            } catch (e: Exception) {
                            }
                        }
                    }
                }
                if (!ok) Log.w(TAG, "protect request did not protect any fd")
                client.outputStream.write(if (ok) 1 else 0)
            } catch (t: Throwable) {
                Log.e(TAG, "protect request failed", t)
            } finally {
                try {
                    client.close()
                } catch (e: Exception) {
                }
            }
        }, "WaveEngineProtectClient").start()
    }

    fun stop() {
        running = false
        try {
            serverSocket?.close()
        } catch (e: Exception) {
        }
        serverSocket = null
        thread = null
    }

    companion object {
        private const val TAG = "ProtectServer"
    }
}
