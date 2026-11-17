package com.pavliq55.efir

import android.content.Context
import org.json.JSONArray
import java.util.UUID

/** Настройки и история на телефоне. */
class Store(ctx: Context) {
    private val p = ctx.getSharedPreferences("efir", Context.MODE_PRIVATE)

    var key: String?
        get() = p.getString("key", null)
        set(v) = p.edit().putString("key", v).apply()

    val device: String
        get() = p.getString("device", null) ?: UUID.randomUUID().toString().also { p.edit().putString("device", it).apply() }

    /** «Послушать»: 0 — только в наушники, 1 — и из динамика, 2 — выключено. */
    var voice: Int
        get() = p.getInt("voice", 0)
        set(v) = p.edit().putInt("voice", v).apply()

    fun history(): List<Phrase> = try {
        val a = JSONArray(p.getString("hist", "[]"))
        (0 until a.length()).map { a.getJSONObject(it) }.map { Phrase.of(it, it.optLong("id")) }
    } catch (e: Exception) { emptyList() }

    fun save(items: List<Phrase>) {
        val a = JSONArray()
        items.takeLast(60).forEach { a.put(it.toJson()) }
        p.edit().putString("hist", a.toString()).apply()
    }
}
