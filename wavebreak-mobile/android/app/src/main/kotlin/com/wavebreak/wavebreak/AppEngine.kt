package com.wavebreak.wavebreak

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * The one Flutter engine of the app process, shared by MainActivity and
 * the headless quick actions (notification buttons, Quick Settings tile).
 * It outlives the activity: closing the window keeps the Dart side (and
 * its connection state) alive while the process is, so a quick action
 * doesn't cold-boot Flutter and reopening the app is instant. Created on
 * first use only — never in the VPN service's own ":RunWaveEngine"
 * process, which doesn't touch this class.
 */
object AppEngine {
    const val ENGINE_ID = "wavebreak_main"

    @Synchronized
    fun get(context: Context): FlutterEngine {
        FlutterEngineCache.getInstance().get(ENGINE_ID)?.let { return it }
        val app = context.applicationContext
        val engine = FlutterEngine(app)
        AppChannels.register(engine, app)
        // The FlutterEngine constructor already initialised the loader.
        engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
        return engine
    }
}
