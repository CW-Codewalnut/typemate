package com.codewalnut.typemate

import android.content.Context
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * One headless Flutter engine (and therefore one loaded speech model) for
 * the native dictation surfaces (the floating mic and the physical-
 * keyboard shortcut), which borrow it here instead of each hosting their
 * own copy of a ~1 GB model.
 *
 * Reference counted: the engine starts with the first surface and is torn
 * down (freeing the model) when the last one goes away.
 */
object SpeechEngineHolder {

    const val CHANNEL_NAME = "typemate/dictation"

    private var engine: FlutterEngine? = null
    private var channel: MethodChannel? = null
    private var references = 0

    @Synchronized
    fun acquire(context: Context): MethodChannel {
        references += 1
        val existing = channel
        if (existing != null) {
            return existing
        }
        // automaticallyRegisterPlugins = false: this engine must register
        // ONLY what dictation needs. Auto-registration would pull in
        // every plugin - including background_downloader, whose native
        // side then binds to THIS engine (no Dart listener here) instead
        // of the app's, breaking the model download the moment any
        // lifecycle event fires.
        val created = FlutterEngine(context.applicationContext, null, false)
        // Recording is the only natively-registered plugin dictation
        // needs; path_provider registers itself from the Dart side. The
        // jni pair must be present too: the Dart plugin registrant
        // initializes package:jni in EVERY engine, and without its Java
        // side the process dies at startup ("JNI is not initialized")
        // whenever this service starts the process before the app UI.
        created.plugins.add(com.github.dart_lang.jni.JniPlugin())
        created.plugins.add(com.github.dart_lang.jni_flutter.JniFlutterPlugin())
        created.plugins.add(com.llfbandit.record.RecordPlugin())
        created.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(
                FlutterInjector.instance().flutterLoader().findAppBundlePath(),
                "dictationServiceMain",
            ),
        )
        val createdChannel =
            MethodChannel(created.dartExecutor.binaryMessenger, CHANNEL_NAME)
        engine = created
        channel = createdChannel
        return createdChannel
    }

    @Synchronized
    fun release() {
        references -= 1
        if (references > 0) {
            return
        }
        references = 0
        val toDestroy = engine
        engine = null
        channel = null
        if (toDestroy == null) {
            return
        }
        // Destroy only AFTER the Dart shutdown handler returns: it kills
        // the worker isolate that holds the ~1 GB model. Destroying the
        // engine first would race that and leak the model. A watchdog
        // destroys anyway if shutdown never answers.
        val destroyed = java.util.concurrent.atomic.AtomicBoolean(false)
        fun destroyOnce() {
            if (destroyed.compareAndSet(false, true)) {
                toDestroy.destroy()
            }
        }
        val handler = android.os.Handler(android.os.Looper.getMainLooper())
        handler.postDelayed({ destroyOnce() }, 3000)
        MethodChannel(toDestroy.dartExecutor.binaryMessenger, CHANNEL_NAME)
            .invokeMethod(
                "shutdown",
                null,
                object : MethodChannel.Result {
                    override fun success(result: Any?) = destroyOnce()
                    override fun error(c: String, m: String?, d: Any?) =
                        destroyOnce()
                    override fun notImplemented() = destroyOnce()
                },
            )
    }
}
