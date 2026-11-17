package com.pavliq55.efir

import android.annotation.SuppressLint
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import java.io.ByteArrayOutputStream
import kotlin.math.abs
import kotlin.math.max

/**
 * Микрофон наготове, пока приложение на экране: звук идёт в кольцо на 0,4 с и никуда не уходит.
 * Нажали — запись начинается с этих 0,4 с, поэтому первое слово не обрезается.
 */
class Mic {
    private val rate = 16000
    private var rec: AudioRecord? = null
    private var worker: Thread? = null
    @Volatile private var running = false
    private var capturing = false
    private val ring = ArrayDeque<ByteArray>()
    private var out = ByteArrayOutputStream()
    @Volatile var level = 0f
        private set

    val on: Boolean get() = running

    @SuppressLint("MissingPermission")
    fun start(): Boolean {
        if (running) return true
        val min = AudioRecord.getMinBufferSize(rate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        val r = try {
            AudioRecord(MediaRecorder.AudioSource.MIC, rate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, max(min, rate) * 2)
        } catch (e: Exception) { return false }
        if (r.state != AudioRecord.STATE_INITIALIZED) { r.release(); return false }
        try { r.startRecording() } catch (e: Exception) { r.release(); return false }
        rec = r
        running = true
        worker = Thread {
            val buf = ByteArray(rate / 10 * 2)          // 0,1 с
            while (running) {
                val n = r.read(buf, 0, buf.size)
                if (n <= 0) { Thread.sleep(20); continue }
                val chunk = buf.copyOf(n)
                var peak = 0
                var i = 0
                while (i + 1 < n) {
                    val s = ((chunk[i].toInt() and 0xff) or (chunk[i + 1].toInt() shl 8)).toShort().toInt()
                    if (abs(s) > peak) peak = abs(s)
                    i += 2
                }
                level = peak / 32768f
                synchronized(this) {
                    if (capturing) out.write(chunk, 0, n)
                    else { ring.addLast(chunk); while (ring.size > 4) ring.removeFirst() }
                }
            }
        }.apply { isDaemon = true; start() }
        return true
    }

    fun stop() {
        running = false
        worker?.join(400)
        worker = null
        rec?.let { try { it.stop() } catch (_: Exception) {}; it.release() }
        rec = null
        synchronized(this) { capturing = false; ring.clear() }
        level = 0f
    }

    fun begin() = synchronized(this) {
        out = ByteArrayOutputStream()
        ring.forEach { out.write(it) }
        ring.clear()
        capturing = true
    }

    /** Секунд записано с нажатия (вместе с кусочком до него). */
    fun seconds(): Float = synchronized(this) { out.size() / (rate * 2f) }

    fun end(): ByteArray = synchronized(this) { capturing = false; wav(out.toByteArray()) }

    fun cancel() = synchronized(this) { capturing = false; out = ByteArrayOutputStream() }

    private fun wav(pcm: ByteArray): ByteArray {
        val h = ByteArray(44)
        fun put(at: Int, v: Int, len: Int) { for (k in 0 until len) h[at + k] = (v shr (8 * k) and 0xff).toByte() }
        "RIFF".toByteArray().copyInto(h, 0); put(4, 36 + pcm.size, 4)
        "WAVE".toByteArray().copyInto(h, 8); "fmt ".toByteArray().copyInto(h, 12)
        put(16, 16, 4); put(20, 1, 2); put(22, 1, 2); put(24, rate, 4); put(28, rate * 2, 4); put(32, 2, 2); put(34, 16, 2)
        "data".toByteArray().copyInto(h, 36); put(40, pcm.size, 4)
        return h + pcm
    }
}
