package me.link.flutter_linkme_sdk

import android.content.Context
import android.content.ContextWrapper
import org.junit.Assert.*
import org.junit.Test

class NativeLifecycleBridgeTest {
    class Core {
        val commands = mutableListOf<Map<String, Any?>>()
        val reads = mutableListOf<(Map<String, Any?>) -> Unit>()
        var listener: ((Map<String, Any?>) -> Unit)? = null
        var unlistened = 0
        var rejectOwnership = false
        var overrideReply: Map<String, Any?>? = null
        fun linkmeLifecycleVersion() = 1
        fun linkmeLifecycle(args: Map<String, Any?>, context: Context?): Map<String, Any?> {
            commands.add(args.toMap())
            overrideReply?.let { return it }
            if (rejectOwnership) return args.filterKeys { it in setOf("contractVersion", "ownerId", "clientGeneration") } + mapOf("ok" to false, "error" to "owner_changed")
            return args.filterKeys { it in setOf("contractVersion", "ownerId", "clientGeneration") } + ("ok" to true)
        }
        fun linkmeLifecycleRead(args: Map<String, Any?>, completion: (Map<String, Any?>) -> Unit) { reads.add(completion) }
        fun linkmeLifecycleListen(listener: (Map<String, Any?>) -> Unit): String { this.listener = listener; return "subscription" }
        fun linkmeLifecycleUnlisten(token: String) { unlistened += 1; listener = null }
    }
    private val core = Core()
    private val queue = ArrayDeque<() -> Unit>()
    private val bridge = NativeLifecycleBridge(core, { ContextWrapper(null) }, { queue.addLast(it) })
    private fun args(action: String, generation: Long = 1) = mapOf<String, Any?>(
        "contractVersion" to 1, "ownerId" to bridge.ownerId, "clientGeneration" to generation, "action" to action)
    private fun frame(generation: Long) = args("unused", generation) + mapOf("ok" to true, "payload" to mapOf("path" to "/ready"))
    private fun drain() { while (queue.isNotEmpty()) queue.removeFirst().invoke() }

    @Test fun discoveryDoesNotAdvertiseOlderCoreAndInvalidHeaderCannotMutate() {
        assertEquals(0, NativeLifecycleBridge(Any(), { null }, {}).version()["contractVersion"])
        assertEquals(1, bridge.version()["contractVersion"])
        for (bad in listOf(mapOf("ownerId" to "other"), mapOf("clientGeneration" to true),
            mapOf("clientGeneration" to 9_007_199_254_740_991L))) {
            assertEquals("invalid_args", bridge.control(args("configure") + bad)["error"])
        }
        assertTrue(core.commands.isEmpty())
        assertEquals("no_context", NativeLifecycleBridge(core, { null }, {}).let { empty ->
            empty.control(args("configure") + ("ownerId" to empty.ownerId))["error"] })
    }

    @Test fun queuedReadCannotCrossCancellationAndLateDuplicateCompletionSettlesOnce() {
        bridge.control(args("configure"))
        val results = mutableListOf<Map<String, Any?>>()
        bridge.read(args("getInitialLink")) { results.add(it) }
        core.reads.single()(frame(1))
        bridge.control(args("cancelPendingRequests", 2))
        assertEquals(1, results.size)
        assertEquals("owner_changed", results.single()["error"])
        assertFalse(results.single().containsKey("payload"))
        repeat(2) { core.reads.single()(frame(1)) }
        drain()
        assertEquals(1, results.size)
        bridge.read(args("getInitialLink", 2)) { results.add(it) }
        core.reads.last()(frame(2))
        drain()
        assertEquals(true, results.last()["ok"])
        assertEquals(2, results.size)
    }

    @Test fun listenerUsesFinalGenerationAndRemovedSubscriptionCannotReachReplacementSink() {
        val frames = mutableListOf<Map<String, Any?>>()
        bridge.listen { frames.add(it) }
        bridge.control(args("configure"))
        val old = requireNotNull(core.listener)
        old(frame(1))
        bridge.control(args("cancelPendingRequests", 2))
        drain()
        assertTrue(frames.isEmpty())
        old(frame(2))
        bridge.listen { frames.add(it) }
        drain()
        assertTrue(frames.isEmpty())
        requireNotNull(core.listener)(frame(2))
        drain()
        assertEquals(1, frames.size)
        repeat(2) { bridge.stopListening() }
        assertEquals(2, core.unlistened)
    }

    @Test fun detachDisposesOnlyItsOwnerAndSettlesPendingBeforeLatePublication() {
        bridge.control(args("configure"))
        val results = mutableListOf<Map<String, Any?>>()
        bridge.read(args("getInitialLink")) { results.add(it) }
        repeat(2) { bridge.detach() }
        assertEquals(listOf("configure", "dispose"), core.commands.map { it["action"] })
        assertEquals(2L, core.commands.last()["clientGeneration"])
        assertEquals(bridge.ownerId, core.commands.last()["ownerId"])
        assertEquals(1, results.size)
        core.reads.single()(frame(1)); drain()
        assertEquals(1, results.size)
        assertEquals("detached", bridge.control(args("configure", 3))["error"])
        val inactive = Core()
        NativeLifecycleBridge(inactive, { null }, {}).detach()
        assertTrue(inactive.commands.isEmpty())
    }

    @Test fun pendingReadsAreBoundedAndDisposeAllowsScopedReconfiguration() {
        bridge.control(args("configure"))
        val results = mutableListOf<Map<String, Any?>>()
        repeat(129) { bridge.read(args("getInitialLink")) { results.add(it) } }
        assertEquals(128, core.reads.size)
        assertEquals("busy", results.single()["error"])
        bridge.control(args("dispose", 2))
        assertEquals(129, results.size)
        assertFalse(bridge.isActive)
        bridge.control(args("configure", 3))
        assertTrue(bridge.isActive)
        bridge.read(args("getInitialLink", 3)) { results.add(it) }
        core.reads.last()(frame(3)); drain()
        assertEquals(true, results.last()["ok"])
    }

    @Test fun directCoreOwnershipChangePreventsUrlHandoffAndDoesNotDisposeForeignContext() {
        bridge.control(args("configure"))
        assertTrue(bridge.ownsContext())
        val results = mutableListOf<Map<String, Any?>>()
        bridge.read(args("getInitialLink")) { results.add(it) }
        core.rejectOwnership = true
        assertFalse(bridge.ownsContext())
        assertEquals("owner_changed", results.single()["error"])
        bridge.detach()
        assertFalse(core.commands.any { it["action"] == "dispose" })
    }

    @Test fun malformedCoreAcknowledgementCannotDiscloseForeignPayloadAndReadActionValidates() {
        core.overrideReply = mapOf("contractVersion" to 1, "ownerId" to "foreign", "clientGeneration" to 1L,
            "ok" to true, "payload" to mapOf("path" to "/foreign"))
        val rejected = bridge.control(args("configure"))
        assertEquals("native_error", rejected["error"])
        assertFalse(rejected.containsKey("payload"))
        assertEquals(bridge.ownerId, rejected["ownerId"])
        assertFalse(bridge.isActive)
        core.overrideReply = null
        bridge.control(args("configure"))
        var result: Map<String, Any?>? = null
        bridge.read(args("track")) { result = it }
        assertEquals("invalid_args", result?.get("error"))
        assertTrue(core.reads.isEmpty())
    }
}
