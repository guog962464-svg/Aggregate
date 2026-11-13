package io.github.guog962464.aggregate

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.net.Inet4Address
import java.net.InetAddress
import java.util.ArrayDeque

internal class HostDiscoveryChannel(
    context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "aggregate/host_discovery")
    private val nsdManager = context.getSystemService(Context.NSD_SERVICE) as NsdManager
    private val handler = Handler(Looper.getMainLooper())
    private val serviceType = "_aggregate-host._tcp."
    private val discoveredServices = mutableSetOf<String>()
    private val resolveQueue = ArrayDeque<NsdServiceInfo>()
    private val endpoints = linkedSetOf<String>()

    private var pendingResult: MethodChannel.Result? = null
    private var targetHostId: String? = null
    private var discoveryListener: NsdManager.DiscoveryListener? = null
    private var isResolving = false
    private var discoveryFinished = false
    private var discoveryGeneration = 0
    private var timeout: Runnable? = null

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "discover" -> discover(call, result)
            else -> result.notImplemented()
        }
    }

    private fun discover(call: MethodCall, result: MethodChannel.Result) {
        val hostId = call.argument<String>("hostId")
        if (hostId == null || !Regex("^host-[a-f0-9]{32}$").matches(hostId)) {
            result.error("invalid_args", "Host identifier is invalid", null)
            return
        }
        if (pendingResult != null) {
            result.error("busy", "Host discovery is already running", null)
            return
        }

        pendingResult = result
        targetHostId = hostId
        val generation = ++discoveryGeneration
        discoveredServices.clear()
        resolveQueue.clear()
        endpoints.clear()
        isResolving = false
        discoveryFinished = false

        val listener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(serviceType: String) = Unit

            override fun onServiceFound(serviceInfo: NsdServiceInfo) {
                if (generation != discoveryGeneration || discoveryFinished) return
                if (serviceInfo.serviceType != this@HostDiscoveryChannel.serviceType) return
                if (discoveredServices.add(serviceInfo.serviceName)) {
                    resolveQueue.addLast(serviceInfo)
                    resolveNext(generation)
                }
            }

            override fun onServiceLost(serviceInfo: NsdServiceInfo) = Unit

            override fun onDiscoveryStopped(serviceType: String) = Unit

            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
                if (generation != discoveryGeneration) return
                discoveryFinished = true
                finishDiscovery()
            }

            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {
                if (generation != discoveryGeneration) return
                discoveryFinished = true
                finishIfReady()
            }
        }
        discoveryListener = listener
        val timeoutTask = Runnable {
            if (generation == discoveryGeneration) {
                discoveryFinished = true
                completeDiscovery(generation)
            }
        }
        timeout = timeoutTask
        handler.postDelayed(timeoutTask, 4500L)
        try {
            nsdManager.discoverServices(serviceType, NsdManager.PROTOCOL_DNS_SD, listener)
        } catch (_: RuntimeException) {
            if (generation != discoveryGeneration) return
            discoveryFinished = true
            finishDiscovery()
        }
    }

    @Suppress("DEPRECATION")
    private fun resolveNext(generation: Int) {
        if (generation != discoveryGeneration || pendingResult == null || isResolving) return
        val service = resolveQueue.pollFirst()
        if (service == null) {
            finishIfReady()
            return
        }
        isResolving = true
        try {
            nsdManager.resolveService(service, object : NsdManager.ResolveListener {
                override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                    if (generation != discoveryGeneration) return
                    isResolving = false
                    resolveNext(generation)
                }

                override fun onServiceResolved(serviceInfo: NsdServiceInfo) {
                    if (generation != discoveryGeneration) return
                    isResolving = false
                    addEndpointIfMatching(serviceInfo)
                    resolveNext(generation)
                }
            })
        } catch (_: RuntimeException) {
            if (generation != discoveryGeneration) return
            isResolving = false
            resolveNext(generation)
        }
    }

    private fun addEndpointIfMatching(serviceInfo: NsdServiceInfo) {
        val hostId = targetHostId ?: return
        val publishedHostId = serviceInfo.attributes["hostId"]
            ?.let { String(it, Charsets.UTF_8) }
        if (publishedHostId != hostId || serviceInfo.port !in 1..65535) return
        val address = serviceInfo.host ?: return
        if (address !is Inet4Address || !isPrivateIpv4(address)) return
        val endpoint = "wss://${address.hostAddress}:${serviceInfo.port}/host"
        if (endpoints.add(endpoint) && endpoints.size >= 8) {
            resolveQueue.clear()
            finishDiscovery()
        }
    }

    private fun isPrivateIpv4(address: InetAddress): Boolean {
        val bytes = address.address
        if (bytes.size != 4 || address.isLoopbackAddress || address.isLinkLocalAddress) {
            return false
        }
        val first = bytes[0].toInt() and 0xff
        val second = bytes[1].toInt() and 0xff
        return first == 10 ||
            (first == 172 && second in 16..31) ||
            (first == 192 && second == 168)
    }

    private fun finishDiscovery() {
        stopDiscovery()
        discoveryFinished = true
        resolveNext(discoveryGeneration)
        finishIfReady()
    }

    private fun finishIfReady() {
        if (!discoveryFinished || isResolving || resolveQueue.isNotEmpty()) return
        completeDiscovery(discoveryGeneration)
    }

    private fun completeDiscovery(generation: Int) {
        if (generation != discoveryGeneration) return
        val result = pendingResult ?: return
        discoveryGeneration += 1
        timeout?.let(handler::removeCallbacks)
        timeout = null
        stopDiscovery()
        resolveQueue.clear()
        isResolving = false
        pendingResult = null
        targetHostId = null
        discoveryListener = null
        result.success(endpoints.toList())
    }

    private fun stopDiscovery() {
        val listener = discoveryListener ?: return
        discoveryListener = null
        try {
            nsdManager.stopServiceDiscovery(listener)
        } catch (_: RuntimeException) {
            // The listener can already have stopped after an NSD failure.
        }
    }

    fun close() {
        discoveryGeneration += 1
        timeout?.let(handler::removeCallbacks)
        timeout = null
        stopDiscovery()
        val result = pendingResult
        pendingResult = null
        targetHostId = null
        resolveQueue.clear()
        isResolving = false
        if (result != null) result.success(emptyList<String>())
        channel.setMethodCallHandler(null)
    }
}
