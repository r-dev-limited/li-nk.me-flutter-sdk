package me.link.flutter_linkme_sdk

import android.content.Context
import java.util.UUID

// Called on the platform main thread. Core callbacks may arrive elsewhere;
// publication and pending-read bookkeeping are always posted back to main.
internal class NativeLifecycleBridge(
    private val core: Any,
    private val context: () -> Context?,
    private val post: (() -> Unit) -> Unit,
) {
    val ownerId: String = UUID.randomUUID().toString()
    var isActive = false
        private set
    private var attached = true
    private var generation = 0L
    private var listenerToken: String? = null
    private var listenerEpoch = 0L
    private var sink: ((Map<String, Any?>) -> Unit)? = null
    private val reads = mutableMapOf<UUID, Pair<Map<String, Any?>, (Map<String, Any?>) -> Unit>>()

    private fun method(name: String, vararg parameters: Class<*>) = core.javaClass.getMethod(name, *parameters)
    fun version(): Map<String, Any?> = try {
        method("linkmeLifecycle", Map::class.java, Context::class.java)
        method("linkmeLifecycleRead", Map::class.java, Function1::class.java)
        method("linkmeLifecycleListen", Function1::class.java)
        method("linkmeLifecycleUnlisten", String::class.java)
        if (attached && method("linkmeLifecycleVersion").invoke(core) == 1)
            mapOf("contractVersion" to 1, "ownerId" to ownerId)
        else mapOf("contractVersion" to 0)
    } catch (_: ReflectiveOperationException) { mapOf("contractVersion" to 0) }

    private fun integer(value: Any?): Long? =
        if (value is Int || value is Long) (value as Number).toLong() else null
    private fun header(args: Map<String, Any?>): Long? {
        if (args["ownerId"] != ownerId || integer(args["contractVersion"]) != 1L) return null
        return integer(args["clientGeneration"])?.takeIf { it in 0 until 9_007_199_254_740_991L }
    }
    private fun error(args: Map<String, Any?>, code: String): Map<String, Any?> =
        mutableMapOf<String, Any?>("contractVersion" to 1, "ok" to false, "error" to code).apply {
            header(args)?.let { put("ownerId", ownerId); put("clientGeneration", it) }
        }
    private fun valid(frame: Map<String, Any?>, expected: Long) = header(frame) == expected && frame["ok"] == true

    @Suppress("UNCHECKED_CAST")
    fun control(args: Map<String, Any?>): Map<String, Any?> {
        if (!attached) return error(args, "detached")
        if (version()["contractVersion"] != 1) return error(args, "unsupported")
        val requested = header(args) ?: return error(args, "invalid_args")
        val action = args["action"] as? String ?: return error(args, "invalid_args")
        val ctx = context()
        if (action == "configure" && ctx == null) return error(args, "no_context")
        val reply = try {
            method("linkmeLifecycle", Map::class.java, Context::class.java).invoke(core, args, ctx) as? Map<String, Any?>
                ?: return error(args, "native_error")
        } catch (_: ReflectiveOperationException) { return error(args, "native_error") }
        if (header(reply) != requested) return error(args, "native_error")
        if (reply["ok"] != true) {
            val code = reply["error"] as? String ?: "native_error"
            if (code == "owner_changed" || code == "owner_conflict") { isActive = false; settleStaleReads() }
            return error(args, code)
        }
        generation = requested
        if (action == "configure") { isActive = true; subscribeIfNeeded() }
        if (action == "dispose") { isActive = false; listenerToken = null; listenerEpoch += 1 }
        settleStaleReads()
        return mutableMapOf<String, Any?>("contractVersion" to 1, "ok" to true,
            "ownerId" to ownerId, "clientGeneration" to requested).apply {
            if (reply["duplicate"] == true) put("duplicate", true)
        }
    }

    fun ownsContext(): Boolean {
        if (!attached || !isActive) return false
        val reply = control(mapOf("contractVersion" to 1, "ownerId" to ownerId,
            "clientGeneration" to generation, "action" to "setReady"))
        if (reply["ok"] == true) return true
        isActive = false
        settleStaleReads()
        return false
    }

    fun read(args: Map<String, Any?>, completion: (Map<String, Any?>) -> Unit) {
        val expected = header(args)
        if (!attached || !isActive || expected != generation) { completion(error(args, "owner_changed")); return }
        if (args["action"] !in listOf("getInitialLink", "claimDeferredIfAvailable")) { completion(error(args, "invalid_args")); return }
        if (reads.size >= 128) { completion(error(args, "busy")); return }
        val id = UUID.randomUUID()
        reads[id] = args.toMap() to completion
        val callback: (Map<String, Any?>) -> Unit = { response ->
            val frame = response.toMap()
            post {
                reads.remove(id)?.let { pending ->
                    pending.second(if (attached && isActive && generation == expected && valid(frame, expected)) frame
                        else error(args, "owner_changed"))
                }
            }
        }
        try { method("linkmeLifecycleRead", Map::class.java, Function1::class.java).invoke(core, args, callback) }
        catch (_: ReflectiveOperationException) { reads.remove(id)?.second?.invoke(error(args, "native_error")) }
    }

    fun listen(sink: (Map<String, Any?>) -> Unit) { stopListening(); this.sink = sink; subscribeIfNeeded() }
    private fun subscribeIfNeeded() {
        if (!attached || sink == null || listenerToken != null || version()["contractVersion"] != 1) return
        val epoch = listenerEpoch
        val callback: (Map<String, Any?>) -> Unit = { response ->
            val frame = response.toMap()
            post { if (attached && isActive && listenerEpoch == epoch && valid(frame, generation)) sink?.invoke(frame) }
        }
        listenerToken = try { method("linkmeLifecycleListen", Function1::class.java).invoke(core, callback) as? String }
            catch (_: ReflectiveOperationException) { null }
    }
    fun stopListening() {
        listenerEpoch += 1
        listenerToken?.let { try { method("linkmeLifecycleUnlisten", String::class.java).invoke(core, it) }
            catch (_: ReflectiveOperationException) { } }
        listenerToken = null
        sink = null
    }
    private fun settleStaleReads() {
        val stale = reads.filterValues { !attached || !isActive || header(it.first) != generation }.toMap()
        stale.keys.forEach { reads.remove(it) }
        stale.values.forEach { it.second(error(it.first, "owner_changed")) }
    }
    fun detach() {
        if (!attached) return
        if (isActive) control(mapOf("contractVersion" to 1, "ownerId" to ownerId,
            "clientGeneration" to generation + 1, "action" to "dispose"))
        attached = false
        isActive = false
        stopListening()
        settleStaleReads()
    }
}
