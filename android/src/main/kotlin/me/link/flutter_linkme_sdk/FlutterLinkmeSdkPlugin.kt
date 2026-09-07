package me.link.flutter_linkme_sdk

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.net.HttpURLConnection
import java.net.URL
import me.link.sdk.LinkMe
import me.link.sdk.LinkPayload

class FlutterLinkmeSdkPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    ActivityAware,
    PluginRegistry.NewIntentListener,
    EventChannel.StreamHandler {

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private val mainHandler = Handler(Looper.getMainLooper())

    private var applicationContext: Context? = null
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var eventSink: EventChannel.EventSink? = null
    private var unsubscribe: (() -> Unit)? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        methodChannel = MethodChannel(binding.binaryMessenger, "flutter_linkme_sdk")
        methodChannel.setMethodCallHandler(this)
        eventChannel = EventChannel(binding.binaryMessenger, "flutter_linkme_sdk/events")
        eventChannel.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        unsubscribe?.invoke()
        unsubscribe = null
        eventSink = null
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        applicationContext = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "configure" -> handleConfigure(call, result)
            "getInitialLink" -> handleGetInitialLink(result)
            "claimDeferredIfAvailable" -> handleClaimDeferred(result)
            "setUserId" -> {
                if ((call.arguments as? Map<*, *>)?.containsKey("userId") != true) {
                    result.error("invalid_args", "userId is required (or null to clear)", null)
                    return
                }
                val userId = call.argument<String>("userId")
                if (userId == null) {
                    // The currently published Android core (0.2.13) has no nullable
                    // setter. Keep the bridge binary-compatible until a new artifact
                    // containing LinkMe.setUserId(String?) is published.
                    result.error("clear_identity_unsupported", "Update the Android core SDK to clear user identity", null)
                    return
                }
                if (userId.isBlank()) {
                    result.error("invalid_args", "userId must not be blank", null)
                    return
                }
                LinkMe.shared.setUserId(userId)
                result.success(null)
            }
            "setAdvertisingConsent" -> {
                val granted = call.argument<Boolean>("granted") ?: false
                LinkMe.shared.setAdvertisingConsent(granted)
                result.success(null)
            }
            "track" -> {
                val event = call.argument<String>("event")
                if (event.isNullOrBlank()) {
                    result.error("invalid_args", "event is required", null)
                    return
                }
                @Suppress("UNCHECKED_CAST")
                val props = call.argument<Map<String, Any?>>("properties")
                LinkMe.shared.track(event, props)
                result.success(null)
            }
            "setReady" -> {
                // Android processes links immediately after configure.
                result.success(null)
            }
            "openExternalUrl" -> {
                val url = call.argument<String>("url")
                if (url.isNullOrBlank()) {
                    result.error("invalid_args", "url is required", null)
                    return
                }
                val ctx = applicationContext
                if (ctx == null) {
                    result.error("no_context", "Plugin not attached to context", null)
                    return
                }
                try {
                    val intent = Intent(Intent.ACTION_VIEW, android.net.Uri.parse(url)).apply {
                        addCategory(Intent.CATEGORY_BROWSABLE)
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    ctx.startActivity(intent)
                    result.success(null)
                } catch (t: Throwable) {
                    result.error("open_url_failed", t.message, null)
                }
            }
            "debugVisitUrl" -> handleDebugVisit(call, result)
            else -> result.notImplemented()
        }
    }

    private fun handleConfigure(call: MethodCall, result: MethodChannel.Result) {
        val ctx = applicationContext
        if (ctx == null) {
            result.error("no_context", "Plugin not attached to context", null)
            return
        }
        val args = call.arguments as? Map<*, *>
        val baseUrl = args?.get("baseUrl") as? String ?: "https://li-nk.me"
        @Suppress("DEPRECATION")
        val config = LinkMe.Config(
            baseUrl = baseUrl,
            appId = args?.get("appId") as? String,
            appKey = args?.get("appKey") as? String,
            enablePasteboard = args?.get("enablePasteboard") as? Boolean ?: false,
            sendDeviceInfo = args?.get("sendDeviceInfo") as? Boolean ?: true,
            includeVendorId = args?.get("includeVendorId") as? Boolean ?: true,
            includeAdvertisingId = args?.get("includeAdvertisingId") as? Boolean ?: false,
            debug = args?.get("debug") as? Boolean ?: false,
        )
        LinkMe.shared.configure(ctx, config)
        activity?.intent?.let { LinkMe.shared.handleIntent(it) }
        result.success(null)
    }

    private fun handleGetInitialLink(result: MethodChannel.Result) {
        LinkMe.shared.getInitialLink { payload ->
            mainHandler.post { result.success(payload?.toMap()) }
        }
    }

    private fun handleClaimDeferred(result: MethodChannel.Result) {
        val ctx = applicationContext
        if (ctx == null) {
            result.error("no_context", "Plugin not attached to context", null)
            return
        }
        
        LinkMe.shared.claimDeferredIfAvailable(ctx) { payload ->
            mainHandler.post { result.success(payload?.toMap()) }
        }
    }

    private fun handleDebugVisit(call: MethodCall, result: MethodChannel.Result) {
        val url = call.argument<String>("url")
        if (url.isNullOrBlank()) {
            result.error("invalid_args", "url is required", null)
            return
        }
        @Suppress("UNCHECKED_CAST")
        val headers = call.argument<Map<String, String>>("headers") ?: emptyMap()
        Thread {
            try {
                val conn = (URL(url).openConnection() as HttpURLConnection)
                conn.requestMethod = "GET"
                conn.instanceFollowRedirects = false
                conn.connectTimeout = 5000
                conn.readTimeout = 5000
                for ((key, value) in headers) {
                    conn.setRequestProperty(key, value)
                }
                val status = conn.responseCode
                try { conn.inputStream?.close() } catch (_: Throwable) {}
                try { conn.errorStream?.close() } catch (_: Throwable) {}
                mainHandler.post { result.success(status) }
            } catch (t: Throwable) {
                mainHandler.post { result.error("debug_visit_failed", t.message, null) }
            }
        }.start()
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        unsubscribe?.invoke()
        eventSink = events
        unsubscribe = LinkMe.shared.addListener { payload ->
            mainHandler.post { events?.success(payload.toMap()) }
        }
    }

    override fun onCancel(arguments: Any?) {
        unsubscribe?.invoke()
        unsubscribe = null
        eventSink = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        activity = binding.activity
        binding.addOnNewIntentListener(this)
        activity?.intent?.let { LinkMe.shared.handleIntent(it) }
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding?.removeOnNewIntentListener(this)
        activityBinding = null
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeOnNewIntentListener(this)
        activityBinding = null
        activity = null
    }

    override fun onNewIntent(intent: Intent): Boolean {
        LinkMe.shared.onNewIntent(intent)
        return false
    }
}

private fun LinkPayload.toMap(): Map<String, Any?> {
    val map = mutableMapOf<String, Any?>()
    // Keep the bridge binary-compatible with the currently published Android
    // core (0.2.13), then pick up cid/duplicate when a newer core exposes
    // those fields. Direct property access would make old consumers fail to
    // compile before they can upgrade the native artifact.
    optionalProperty("cid")?.let { map["cid"] = it }
    linkId?.let { map["linkId"] = it }
    path?.let { map["path"] = it }
    params?.let { map["params"] = it }
    utm?.let { map["utm"] = it }
    custom?.let { map["custom"] = it }
    url?.let { map["url"] = it }
    isLinkMe?.let { map["isLinkMe"] = it }
    optionalProperty("duplicate")?.let { map["duplicate"] = it }
    forceRedirectWeb?.let { map["forceRedirectWeb"] = it }
    webFallbackUrl?.let { map["webFallbackUrl"] = it }
    return map
}

private fun LinkPayload.optionalProperty(name: String): Any? {
    val suffix = name.replaceFirstChar { it.uppercaseChar() }
    return runCatching {
        javaClass.getMethod("get$suffix").invoke(this)
    }.getOrNull()
}
