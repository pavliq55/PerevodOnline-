package com.pavliq55.efir

import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

/** Одна строка для эфира: по-арабски и как её прочитать русскими буквами (ударная гласная — заглавная). */
data class Line(val ar: String, val read: String)

/** Фраза: что сказали по-русски, строки для эфира, обратный перевод для проверки смысла. */
data class Phrase(val id: Long, val ru: String, val lines: List<Line>, val back: String) {
    val ar: String get() = lines.joinToString(" ") { it.ar }

    fun toJson(): JSONObject = JSONObject().put("id", id).put("ru", ru).put("back", back)
        .put("lines", JSONArray().apply { lines.forEach { put(JSONObject().put("ar", it.ar).put("read", it.read)) } })

    companion object {
        fun of(o: JSONObject, id: Long): Phrase {
            val a = o.optJSONArray("lines") ?: JSONArray()
            val lines = (0 until a.length()).map { a.getJSONObject(it) }.map { Line(it.optString("ar"), it.optString("read")) }
            return Phrase(id, o.optString("ru"), lines, o.optString("back"))
        }
    }
}

class ApiError(msg: String, val auth: Boolean = false) : Exception(msg)

/** Сервер переводчика (тот же, что у Tapny на айфоне): /api/ar — режим «Эфир». */
object Net {
    private const val BASE = "https://perevod.molly-trade.workers.dev"

    private fun open(path: String, key: String, post: Boolean): HttpURLConnection =
        (URL(BASE + path).openConnection() as HttpURLConnection).apply {
            requestMethod = if (post) "POST" else "GET"
            connectTimeout = 10_000
            readTimeout = 40_000
            setRequestProperty("X-Pin", key)
            if (post) doOutput = true
        }

    private fun answer(c: HttpURLConnection): JSONObject {
        val code = c.responseCode
        val body = (if (code in 200..299) c.inputStream else c.errorStream)?.bufferedReader()?.use { it.readText() } ?: ""
        val o = try { JSONObject(body) } catch (e: Exception) { JSONObject() }
        if (code == 401) throw ApiError("PIN не подходит", auth = true)
        if (code !in 200..299) throw ApiError(o.optString("error").ifBlank { "Сервер ответил $code" })
        return o
    }

    /** Вход: PIN → ключ этого телефона. Сам PIN на телефоне не хранится. */
    fun login(pin: String, id: String): String {
        val c = open("/api/device", pin, true)
        c.setRequestProperty("Content-Type", "application/json")
        c.outputStream.use { it.write(JSONObject().put("id", id).toString().toByteArray()) }
        return answer(c).optString("token").ifBlank { throw ApiError("Не получилось войти") }
    }

    /** Запись (WAV 16 кГц) → фраза для эфира. Пустая фраза — ничего не расслышали. */
    fun translate(key: String, wav: ByteArray): Phrase {
        val c = open("/api/ar", key, true)
        c.setRequestProperty("Content-Type", "audio/wav")
        c.setFixedLengthStreamingMode(wav.size)
        c.outputStream.use { it.write(wav) }
        return Phrase.of(answer(c), System.currentTimeMillis())
    }

    /** Арабский женский голос — в файл. */
    fun voice(key: String, text: String, into: File) {
        val c = open("/api/tts?l=ar&g=f&q=" + URLEncoder.encode(text.take(900), "UTF-8"), key, false)
        if (c.responseCode != 200) throw ApiError("Голос не скачался")
        val tmp = File(into.path + ".part")
        c.inputStream.use { inp -> tmp.outputStream().use { inp.copyTo(it) } }
        tmp.renameTo(into)
    }

    /** Ошибка на телефоне — в журнал сервера (видно, что пошло не так). */
    fun report(key: String, err: String) {
        try {
            val c = open("/api/diag", key, true)
            c.setRequestProperty("Content-Type", "application/json")
            c.outputStream.use { it.write(JSONObject().put("t", "js").put("where", "android-efir").put("err", err.take(300)).toString().toByteArray()) }
            c.responseCode
        } catch (_: Exception) {}
    }
}
