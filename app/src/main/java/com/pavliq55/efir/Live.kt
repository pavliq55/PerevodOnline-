package com.pavliq55.efir

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.withTimeoutOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString
import okio.ByteString.Companion.toByteString
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/**
 * Живой режим: с нажатия звук идёт на сервер, Deepgram распознаёт на ходу (слова — сразу на экран),
 * на паузах сервер уже переводит готовые куски. После отпускания остаётся перевести только хвост.
 * Что-то пошло не так — результат null, и приложение переводит запись целиком, как раньше.
 */
class Live(private val key: String, private val v: String, private val onHeard: (String) -> Unit) {
    private var ws: WebSocket? = null
    private val pending = ArrayList<ByteArray>()
    private var ready = false
    @Volatile private var dead = false
    private val result = CompletableDeferred<Pair<Phrase, Int>?>()

    fun start() {
        val req = Request.Builder().url("wss://perevod.molly-trade.workers.dev/api/arlive").header("User-Agent", "TapnyEfir").build()
        ws = client.newWebSocket(req, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                webSocket.send(JSONObject().put("key", key).put("v", v).toString())
            }
            override fun onMessage(webSocket: WebSocket, text: String) {
                val o = try { JSONObject(text) } catch (e: Exception) { return }
                when (o.optString("t")) {
                    "ready" -> synchronized(this@Live) { ready = true; pending.forEach { webSocket.send(it.toByteString()) }; pending.clear() }
                    "heard" -> onHeard(o.optString("text"))
                    "result" -> result.complete(Phrase.of(o, System.currentTimeMillis()) to o.optInt("ms"))
                    "error" -> fail()
                }
            }
            override fun onMessage(webSocket: WebSocket, bytes: ByteString) {}
            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) = fail()
            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) = fail()
        })
    }

    private fun fail() { dead = true; result.complete(null) }

    /** Кусок звука (μ-law). До «готов» копится здесь: сервер ещё открывает распознавание. */
    fun audio(b: ByteArray) {
        synchronized(this) {
            if (dead) return
            if (ready) ws?.send(b.toByteString())
            else if (pending.size < 600) pending.add(b)
        }
    }

    fun end() { ws?.send("{\"t\":\"end\"}") }

    fun cancel() { dead = true; try { ws?.send("{\"t\":\"cancel\"}"); ws?.close(1000, null) } catch (_: Exception) {}; result.complete(null) }

    suspend fun await(ms: Long): Pair<Phrase, Int>? = withTimeoutOrNull(ms) { result.await() }

    companion object {
        private val client = OkHttpClient.Builder().pingInterval(15, TimeUnit.SECONDS).readTimeout(0, TimeUnit.MILLISECONDS).build()
    }
}
