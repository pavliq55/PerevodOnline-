package com.pavliq55.efir

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.SystemClock
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

/** Всё, что знает экран: вход, запись, перевод, история, голос. */
class Model(private val ctx: Context, private val mic: Mic, demo: String?) {
    private val store = Store(ctx)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val demoMode = demo != null

    var key by mutableStateOf(if (demoMode) (if (demo == "login") null else "demo") else store.key)
    val items = mutableStateListOf<Phrase>().apply { addAll(if (demoMode) (if (demo == "long") Demo.items + Demo.long else Demo.items) else store.history()) }
    var recording by mutableStateOf(demo == "rec")
    var latched by mutableStateOf(demo == "rec")      // короткое нажатие: говорим, пока не нажмут ещё раз
    var jobs by mutableIntStateOf(0)
    var hint by mutableStateOf("")
    var level by mutableFloatStateOf(0f)
    var full by mutableStateOf<Phrase?>(if (demo == "full") Demo.items.last() else null)
    var playing by mutableStateOf<Long?>(null)
    var loading by mutableStateOf<Long?>(null)
    var voice by mutableIntStateOf(store.voice)
    var busyLogin by mutableStateOf(false)
    var pick by mutableStateOf<Long?>(null)           // фраза из истории, выбранная для главного экрана
    var history by mutableStateOf(demo == "hist")

    /** На главном — одна фраза: выбранная из истории или последняя. */
    val current: Phrase? get() = items.firstOrNull { it.id == pick } ?: items.lastOrNull()
    var askMic: () -> Unit = {}
    private var pressAt = 0L
    private var player: MediaPlayer? = null

    val micReady: Boolean get() = mic.on

    // MARK: вход
    fun login(pin: String) {
        if (busyLogin) return
        busyLogin = true; hint = ""
        scope.launch {
            try {
                val k = withContext(Dispatchers.IO) { Net.login(pin.trim(), store.device) }
                store.key = k; key = k
            } catch (e: ApiError) { hint = if (e.auth) "PIN не подходит" else e.message ?: "Ошибка" }
            catch (e: Exception) { hint = "Нет интернета — попробуйте ещё раз" }
            busyLogin = false
        }
    }

    fun logout() { store.key = null; key = null; hint = "" }

    // MARK: запись
    /** Палец лёг на кнопку. */
    fun down() {
        if (demoMode) return
        if (recording) { if (latched) finish(); return }       // запись «по нажатию» — второе нажатие её заканчивает
        if (!mic.on) { askMic(); return }
        stopVoice()
        mic.begin()
        recording = true; latched = false; hint = ""
        pressAt = SystemClock.elapsedRealtime()
        key?.let { k -> scope.launch(Dispatchers.IO) { Net.warm(k) } }
        scope.launch {
            while (recording) {
                level = mic.level
                if (mic.seconds() > 60) { finish(); break }        // минута — хватит, переводим
                delay(50)
            }
            level = 0f
        }
    }

    /** Палец отпустили. Коротко нажали — запись продолжается до следующего нажатия. */
    fun up() {
        if (!recording || latched) return
        if (SystemClock.elapsedRealtime() - pressAt < 350) { latched = true; return }
        finish()
    }

    fun cancel() {
        if (!recording) return
        mic.cancel(); recording = false; latched = false; hint = "Отменено"
    }

    private fun finish() {
        if (!recording) return
        recording = false; latched = false
        val secs = mic.seconds()
        val wav = mic.end()
        if (secs < 0.8f) { hint = "Слишком коротко — скажите фразу целиком"; return }
        val k = key ?: return
        jobs++
        val t0 = SystemClock.elapsedRealtime()
        scope.launch {
            try {
                val (p, srv) = withContext(Dispatchers.IO) { Net.translate(k, wav) }
                if (p.lines.isEmpty()) hint = "Не расслышала — повторите"
                else { items.add(p); store.save(items); hint = ""; pick = null }
                val ms = SystemClock.elapsedRealtime() - t0
                val sec = (secs * 10).toInt() / 10f
                scope.launch(Dispatchers.IO) { Net.timing(k, ms, (sec * 1000).toLong(), srv, wav.size / 1024, net(), version()) }
            } catch (e: ApiError) {
                if (e.auth) logout() else hint = e.message ?: "Ошибка"
                report("translate: ${e.message}")
            } catch (e: Exception) {
                hint = "Нет интернета — повторите"
                report("translate: $e")
            }
            jobs--
        }
    }

    private fun net(): String {
        val cm = ctx.getSystemService(android.net.ConnectivityManager::class.java) ?: return "?"
        val c = cm.getNetworkCapabilities(cm.activeNetwork) ?: return "нет"
        return when {
            c.hasTransport(android.net.NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
            c.hasTransport(android.net.NetworkCapabilities.TRANSPORT_CELLULAR) -> "mobile"
            else -> "other"
        }
    }

    private fun version(): String = try {
        "a" + ctx.packageManager.getPackageInfo(ctx.packageName, 0).longVersionCode
    } catch (e: Exception) { "a?" }

    fun onPause() { if (recording) cancel(); stopVoice() }

    // MARK: голос в наушник
    fun headphones(): Boolean {
        val am = ctx.getSystemService(AudioManager::class.java) ?: return false
        val ear = setOf(AudioDeviceInfo.TYPE_WIRED_HEADPHONES, AudioDeviceInfo.TYPE_WIRED_HEADSET, AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO, AudioDeviceInfo.TYPE_USB_HEADSET, 26 /* BLE-наушники */)
        return am.getDevices(AudioManager.GET_DEVICES_OUTPUTS).any { it.type in ear }
    }

    fun play(p: Phrase) {
        if (playing == p.id || loading == p.id) { stopVoice(); return }
        if (voice == 2) { hint = "Голос выключен — включите в настройках"; return }
        if (voice == 0 && !headphones()) { hint = "Подключите наушники: из динамика голос попадёт в эфир"; return }
        val k = key ?: return
        stopVoice()
        loading = p.id
        scope.launch {
            val f = File(ctx.cacheDir, "v${p.id}.mp3")
            try {
                if (!f.exists()) withContext(Dispatchers.IO) { Net.voice(k, p.ar, f) }
                if (loading != p.id) return@launch
                val mp = MediaPlayer()
                mp.setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
                mp.setDataSource(f.path)
                mp.setOnCompletionListener { stopVoice() }
                mp.prepare(); mp.start()
                player = mp; playing = p.id
            } catch (e: Exception) {
                hint = "Голос не скачался — попробуйте ещё раз"
                report("voice: $e")
            }
            loading = null
        }
    }

    fun stopVoice() {
        player?.let { try { it.stop() } catch (_: Exception) {}; it.release() }
        player = null; playing = null; loading = null
    }

    fun setVoiceMode(v: Int) { voice = v; store.voice = v }

    fun clear() { items.clear(); pick = null; store.save(items); ctx.cacheDir.listFiles()?.filter { it.name.endsWith(".mp3") }?.forEach { it.delete() } }

    private fun report(err: String) { val k = key ?: return; if (demoMode) return; scope.launch(Dispatchers.IO) { Net.report(k, err) } }
}

/** Снимки экрана в облачной сборке (adb … --es demo main|full|rec|login). */
object Demo {
    val items = listOf(
        Phrase(1, "Привет всем! Как у вас дела?", listOf(
            Line("أهلًا يا حبايبي!", "АхлЯн я хабАйби!"), Line("إزايكم؟ عاملين إيه؟", "иззАйукум? амлИн Э?")), "Привет, мои дорогие! Как вы?"),
        Phrase(2, "Спасибо за розу, Карим, ты лучший", listOf(
            Line("شكرًا على الوردة يا كريم", "шУкран Аля иль-вАрда я карИм"), Line("انت أحسن واحد", "Инта Ахсан вАхед")), "Спасибо за розу, Карим, ты лучший"),
        Phrase(3, "Подпишитесь и поставьте лайк, если я вам нравлюсь", listOf(
            Line("اعملوا فولو ولايك يا حبايبي", "и-мАлу фоллОу уи лАйк я хабАйби"), Line("لو أنا عاجباكم", "лау Ана аджабАкум")),
            "Подпишитесь и поставьте лайк, мои дорогие, если я вам нравлюсь"),
        Phrase(5, "Можно сделать буквы поменьше?", listOf(Line("", "мУмкин нИмиль иль-хурУф Асгар шуАйя?")), "Можно сделать буквы поменьше?"),
        Phrase(6, "Ты такой молодец…", listOf(
            Line("", "Инта халУ Ауи", "ты такой молодец"), Line("", "я Альби", "сердце моё"), Line("", "Ана мамнУна лак Ауи", "я тебе очень благодарна"),
            Line("", "кунт бАуль ли вОва", "я только что говорила Вове"), Line("", "Анак я хабИби", "про тебя, любимый"),
            Line("", "Инак амАльт ли татбИк", "что ты сделал мне приложение"), Line("", "у-Аль ли", "и он сказал мне"),
            Line("", "Амсик фИк", "держись за тебя"), Line("", "зи иль-кИта", "как кошка"), Line("", "битмИск иль-гусн", "держится за ветку")),
            "Ты такой молодец… как кошка держится за ветку"),
    )
    val long = listOf(Phrase(4, "Рассказ о дне", listOf(
        Line("", "лау кунт бтИрджам насс тауИль"), Line("", "у-Ана бас бАуиль э иль-нахарда"), Line("", "инни рахт иль-тамрИн"),
        Line("", "у-инни акАльт кауИс"), Line("", "у-инни ракабт ид-дараАджа"), Line("", "у-инни кунт шаИля нафси иль-нахарда"),
        Line("", "у-инни иштагАльт катИр"), Line("", "у-инни шуфт афлам катИр"), Line("", "у-инни фтахт ютУб"), Line("", "у-инни шуфт иш-шамс")),
        "Если бы я переводила длинный текст, когда просто рассказываю, что делала сегодня: ходила на тренировку, хорошо поела, каталась на байке, занималась собой, много работала, смотрела фильмы, открывала YouTube, смотрела на солнце."))
}
