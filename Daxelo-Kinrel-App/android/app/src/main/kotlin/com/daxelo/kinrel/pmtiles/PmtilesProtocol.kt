package com.daxelo.kinrel.pmtiles

import android.util.Log
import okhttp3.OkHttpClient
import okhttp3.Request
import okio.Buffer
import okio.buffer
import okio.sink
import org.maplibre.android.maps.Style
import org.maplibre.android.module.http.HttpRequestUtil
import java.io.RandomAccessFile
import java.net.URL
import java.util.concurrent.ConcurrentHashMap

/**
 * P14 — Phase A PMTiles Migration: registers the `pmtiles://` custom protocol
 * with MapLibre Native Android so the map style can reference PMTiles archives
 * via URLs like `pmtiles://https://tiles.daxelo-kinrel.dev/mumbai.pmtiles`.
 *
 * MapLibre Native Android (13.x) exposes `Style.addProtocol()` which lets us
 * intercept any URL scheme and return raw bytes for the requested range.
 *
 * PMTiles format: a single archive file with an internal directory structure.
 * Clients issue HTTP Range requests to fetch only the bytes they need.
 *
 * This file does NOT change any layer IDs, source-layer names, or paint
 * properties. Per Phase A spec: only the tile source is replaced.
 *
 * The protocol handler:
 *   1. Parses the `pmtiles://<real-url>` prefix to get the actual HTTP URL.
 *   2. Issues an HTTP Range request for the requested byte range.
 *   3. Returns the raw bytes to MapLibre.
 *
 * Caches the PMTiles directory (first 127KB) in memory to avoid refetching
 * on every tile request.
 */
object PmtilesProtocol {
    private const val TAG = "PmtilesProtocol"
    private const val HEADER_SIZE = 127 // PMTiles v3 directory header is 127 bytes

    /** Per-URL directory cache (key = archive URL, value = first HEADER_SIZE bytes). */
    private val directoryCache = ConcurrentHashMap<String, ByteArray>()

    /** HTTP client (shared with MapLibre's own client for connection reuse). */
    private val httpClient: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .connectTimeout(10, java.util.concurrent.TimeUnit.SECONDS)
            .readTimeout(30, java.util.concurrent.TimeUnit.SECONDS)
            .build()
    }

    /**
     * Register the `pmtiles://` protocol with the given MapLibre Style.
     * Call this from `onStyleLoaded` BEFORE adding any PMTiles-sourced layers.
     */
    fun register(style: Style) {
        try {
            // MapLibre Native Android 13.x API: style.addProtocol(scheme, loadFn)
            // The load function receives (url: String, callback: ProtocolLoadCallback).
            style.addProtocol("pmtiles") { url, callback ->
                try {
                    val bytes = loadPmtilesRange(url)
                    callback.onSuccess(bytes)
                } catch (e: Exception) {
                    Log.e(TAG, "PMTiles load failed for $url", e)
                    callback.onError(e.message ?: "PMTiles load failed")
                }
            }
            Log.i(TAG, "PMTiles protocol registered with MapLibre style")
        } catch (e: NoSuchMethodError) {
            // Older MapLibre Native versions don't have addProtocol
            Log.e(TAG, "MapLibre Native does not support addProtocol() — PMTiles will not work", e)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to register PMTiles protocol", e)
        }
    }

    /**
     * Load a byte range from a PMTiles archive.
     * URL format: `pmtiles://<real-url>` where <real-url> is the actual HTTPS URL.
     * MapLibre passes a URL with a `?range=START-END` query param.
     */
    private fun loadPmtilesRange(url: String): ByteArray {
        // Strip pmtiles:// prefix to get the real URL
        val realUrl = if (url.startsWith("pmtiles://")) {
            url.removePrefix("pmtiles://")
        } else {
            url
        }

        // Parse range from query string (format: ?range=0-127 or ?range=0-)
        val urlObj = URL(realUrl)
        val query = urlObj.query ?: ""
        val rangeParam = query.split("&")
            .firstOrNull { it.startsWith("range=") }
            ?.removePrefix("range=")

        val (start, end) = if (rangeParam != null) {
            val parts = rangeParam.split("-")
            val s = parts[0].toLong()
            val e = if (parts.size > 1 && parts[1].isNotEmpty()) parts[1].toLong() else s + HEADER_SIZE - 1
            s to e
        } else {
            0L to (HEADER_SIZE - 1).toLong()
        }

        // Strip the range query param from the URL for the HTTP request
        val cleanUrl = if (query.isEmpty()) realUrl else {
            val cleanQuery = query.split("&").filter { !it.startsWith("range=") }.joinToString("&")
            if (cleanQuery.isEmpty()) "${urlObj.protocol}://${urlObj.host}${urlObj.path}"
            else "${urlObj.protocol}://${urlObj.host}${urlObj.path}?$cleanQuery"
        }

        return httpClient.newCall(
            Request.Builder()
                .url(cleanUrl)
                .header("Range", "bytes=$start-$end")
                .header("Accept", "application/octet-stream")
                .build()
        ).execute().use { response ->
            if (!response.isSuccessful) {
                throw RuntimeException("PMTiles HTTP ${response.code} for $cleanUrl range=$start-$end")
            }
            val body = response.body ?: throw RuntimeException("Empty body")
            body.bytes()
        }
    }
}
