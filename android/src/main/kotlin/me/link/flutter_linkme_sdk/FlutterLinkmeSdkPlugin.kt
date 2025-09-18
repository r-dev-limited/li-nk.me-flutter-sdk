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
        val baseUrl = args?.get("baseUrl") as? String
        if (baseUrl.isNullOrBlank()) {
            result.error("invalid_args", "baseUrl is required", null)
            return
        }
        val config = LinkMe.Config(
            baseUrl = baseUrl,
            appId = args["appId"] as? String,
            appKey = args["appKey"] as? String,
            enablePasteboard = args["enablePasteboard"] as? Boolean ?: false,
            sendDeviceInfo = args["sendDeviceInfo"] as? Boolean ?: true,
            includeVendorId = args["includeVendorId"] as? Boolean ?: true,
            includeAdvertisingId = args["includeAdvertisingId"] as? Boolean ?: false,
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
        activity = binding.activity
        binding.addOnNewIntentListener(this)
        activity?.intent?.let { LinkMe.shared.handleIntent(it) }
    }

    override fun onDetachedFromActivityForConfigChanges(binding: ActivityPluginBinding) {
        onDetachedFromActivity(binding)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity(binding: ActivityPluginBinding) {
        binding.removeOnNewIntentListener(this)
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
