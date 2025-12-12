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
                val userId = call.argument<String>("userId")
                if (userId.isNullOrBlank()) {
                    result.error("invalid_args", "userId is required", null)
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
        
        // Get config for potential fallback (native SDK's InstallReferrer may fail on emulator)
        val config = try {
            val configField = LinkMe.shared::class.java.getDeclaredField("config")
            configField.isAccessible = true
            configField.get(LinkMe.shared) as? LinkMe.Config
        } catch (_: Throwable) { null }
        
        LinkMe.shared.claimDeferredIfAvailable(ctx) { payload ->
            if (payload != null) {
                mainHandler.post { result.success(payload.toMap()) }
            } else if (config != null) {
                // Fallback: try direct fingerprint claim (InstallReferrer unavailable)
                directFingerprintClaim(ctx, config, result)
            } else {
                mainHandler.post { result.success(null) }
            }
        }
    }
    
    private fun directFingerprintClaim(ctx: Context, config: LinkMe.Config, result: MethodChannel.Result) {
        Thread {
            try {
                val url = URL("${config.baseUrl.trimEnd('/')}/api/deferred/claim")
                val conn = url.openConnection() as HttpURLConnection
                conn.requestMethod = "POST"
                conn.setRequestProperty("Content-Type", "application/json")
                conn.setRequestProperty("Accept", "application/json")
                config.appId?.let { conn.setRequestProperty("x-app-id", it) }
                config.appKey?.let { conn.setRequestProperty("x-api-key", it) }
                conn.connectTimeout = 10000
                conn.readTimeout = 10000
                conn.doOutput = true
                
                val body = "{\"bundleId\":\"${ctx.packageName}\",\"platform\":\"android\"}"
                conn.outputStream.use { it.write(body.toByteArray()) }
                
                if (conn.responseCode in 200..299) {
                    val responseBody = conn.inputStream.bufferedReader().use { it.readText() }
                    val payloadMap = parseJsonToMap(responseBody)
                    mainHandler.post { result.success(payloadMap) }
                } else {
                    mainHandler.post { result.success(null) }
                }
            } catch (_: Throwable) {
                mainHandler.post { result.success(null) }
            }
        }.start()
    }
    
    private fun parseJsonToMap(json: String): Map<String, Any?>? {
        try {
            val linkIdMatch = Regex("\"linkId\"\\s*:\\s*\"([^\"]+)\"").find(json)
            if (linkIdMatch != null) {
                return mapOf("linkId" to linkIdMatch.groupValues[1])
            }
        } catch (_: Throwable) {}
        return null
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
    linkId?.let { map["linkId"] = it }
    path?.let { map["path"] = it }
    params?.let { map["params"] = it }
    utm?.let { map["utm"] = it }
    custom?.let { map["custom"] = it }
    return map
}
