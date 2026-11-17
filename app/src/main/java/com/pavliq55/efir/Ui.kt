package com.pavliq55.efir

import android.Manifest
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.Constraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.ParagraphStyle
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDirection
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties

private val Ink = Color(0xFF2A1E2E)
private val Dim = Color(0xFF7A6C7E)
private val Stress = Color(0xFFE0457B)     // ударная гласная
private val ArInk = Color(0xFF6B4FB8)
private val Warm = Brush.linearGradient(listOf(Color(0xFFFF8FB1), Color(0xFFFFA77F)))
private val Back = Brush.verticalGradient(listOf(Color(0xFFFFF3E8), Color(0xFFFFE6EE), Color(0xFFF0E7FF)))

@Composable
fun EfirApp(m: Model, onMicGranted: () -> Unit) {
    val ask = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { ok ->
        if (ok) { onMicGranted(); m.hint = "Микрофон включён — можно говорить" } else m.hint = "Без микрофона перевод не работает"
    }
    m.askMic = { ask.launch(Manifest.permission.RECORD_AUDIO) }
    Box(Modifier.fillMaxSize().background(Back)) {
        if (m.key == null) Login(m) else Main(m)
    }
    m.full?.let { Full(it) { m.full = null } }
}

// MARK: вход по PIN
@Composable
private fun Login(m: Model) {
    var pin by remember { mutableStateOf("") }
    Column(Modifier.fillMaxSize().systemBarsPadding().padding(28.dp), verticalArrangement = Arrangement.Center) {
        Text("Tapny Эфир", fontSize = 34.sp, fontWeight = FontWeight.Black, color = Ink)
        Spacer(Modifier.height(10.dp))
        Text("Говорите по-русски — приложение даст фразу по-арабски и подскажет, как её прочитать.", fontSize = 16.sp, color = Dim)
        Spacer(Modifier.height(28.dp))
        OutlinedTextField(value = pin, onValueChange = { pin = it.filter(Char::isDigit).take(12) }, label = { Text("PIN переводчика") },
            singleLine = true, visualTransformation = PasswordVisualTransformation(),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword), modifier = Modifier.fillMaxWidth())
        Spacer(Modifier.height(16.dp))
        Box(Modifier.fillMaxWidth().height(56.dp).clip(RoundedCornerShape(28.dp)).background(Warm)
            .clickable(enabled = pin.length >= 6 && !m.busyLogin) { m.login(pin) }, contentAlignment = Alignment.Center) {
            if (m.busyLogin) CircularProgressIndicator(color = Color.White, strokeWidth = 2.dp, modifier = Modifier.size(24.dp))
            else Text("Войти", color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.Bold)
        }
        if (m.hint.isNotEmpty()) { Spacer(Modifier.height(12.dp)); Text(m.hint, color = Stress, fontSize = 15.sp) }
    }
}

// MARK: главный экран — одна фраза целиком, без листания
@Composable
private fun Main(m: Model) {
    var settings by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxSize().systemBarsPadding()) {
        Row(Modifier.fillMaxWidth().padding(start = 20.dp, end = 8.dp, top = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("Tapny Эфир", fontSize = 22.sp, fontWeight = FontWeight.Black, color = Ink)
            Spacer(Modifier.weight(1f))
            if (m.items.isNotEmpty()) Round(R.drawable.ic_history, "История") { m.history = true }
            Round(R.drawable.ic_gear, "Настройки") { settings = true }
        }
        val p = m.current
        Box(Modifier.weight(1f).fillMaxWidth().padding(horizontal = 14.dp, vertical = 10.dp)) {
            if (p == null) Empty() else Current(m, p)
        }
        Bottom(m)
    }
    if (settings) Settings(m) { settings = false }
    if (m.history) History(m)
}

@Composable
private fun Round(icon: Int, label: String, onClick: () -> Unit) {
    Box(Modifier.size(48.dp).clip(CircleShape).clickable(onClick = onClick), contentAlignment = Alignment.Center) {
        Icon(painterResource(icon), label, tint = Ink, modifier = Modifier.size(24.dp))
    }
}

@Composable
private fun Empty() {
    Column(Modifier.padding(top = 30.dp, start = 8.dp, end = 8.dp)) {
        Text("Скажите фразу по-русски", fontSize = 24.sp, fontWeight = FontWeight.Bold, color = Ink)
        Spacer(Modifier.height(8.dp))
        Text("Появится, как сказать по-арабски — русскими буквами. Розовая буква — ударение.", fontSize = 16.sp, color = Dim)
    }
}

/** Чтение русскими буквами: ударная гласная — строчная, но розовая и жирнее (заглавные посреди слова глаз спотыкает). */
private fun AnnotatedString.Builder.read(t: String) {
    for (ch in t) {
        if (ch.isLetter() && ch.isUpperCase()) withStyle(SpanStyle(color = Stress, fontWeight = FontWeight.ExtraBold)) { append(ch.lowercaseChar()) }
        else append(ch)
    }
}

/** Строки фразы: каждая с новой строки, длинный рассказ — сплошным текстом через «•». */
private fun stressed(lines: List<Line>, flow: Boolean = false): AnnotatedString = buildAnnotatedString {
    lines.forEachIndexed { i, l ->
        if (i > 0) { if (flow) withStyle(SpanStyle(color = Dim)) { append("  •  ") } else append("\n") }
        read(l.read)
    }
}

/** Куски «как субтитры»: кусок для чтения, под ним мелко — что он значит. */
private fun chunks(lines: List<Line>, size: Float): AnnotatedString = buildAnnotatedString {
    val ru = (size * 0.5f).coerceAtLeast(12f)              // смысл — не мельче 12, иначе не прочитать
    lines.forEach { l ->
        withStyle(ParagraphStyle(lineHeight = (size * 1.2f).sp)) { read(l.read) }
        withStyle(ParagraphStyle(lineHeight = (ru * 1.5f).sp)) {
            withStyle(SpanStyle(fontSize = ru.sp, color = Dim, fontWeight = FontWeight.Normal, letterSpacing = 0.sp)) { append(l.ru) }
        }
    }
}

/**
 * Фраза на весь экран: размер букв подбирается так, чтобы ВСЯ фраза и её смысл влезли без листания —
 * короткая крупно, длинная мельче. Пока говорят новую — прошлая бледнеет.
 */
@Composable
private fun Current(m: Model, p: Phrase) {
    val busy = m.recording || m.jobs > 0
    val fade by animateFloatAsState(if (busy) 0.3f else 1f, label = "fade")
    Column(Modifier.fillMaxSize().clip(RoundedCornerShape(28.dp)).background(Color.White.copy(alpha = 0.9f))
        .padding(horizontal = 20.dp, vertical = 18.dp)) {
        BoxWithConstraints(Modifier.weight(1f).fillMaxWidth().alpha(fade)) {
            val measurer = rememberTextMeasurer()
            val density = LocalDensity.current
            // сервер прислал куски со смыслом — подача «как субтитры»; иначе — как раньше (откат сервера = откат подачи)
            val chunked = p.lines.isNotEmpty() && p.lines.all { it.ru.isNotBlank() }
            val back = if (chunked) "" else p.back
            val plain = remember(p.id) { stressed(p.lines, flow = p.lines.size > 3) }
            fun text(s: Float) = if (chunked) chunks(p.lines, s) else plain
            val w = constraints.maxWidth
            val h = constraints.maxHeight
            val gap = with(density) { 12.dp.roundToPx() }
            // один и тот же стиль — и для замера, и для показа: иначе замер разойдётся с тем, что на экране
            fun readStyle(s: Float) = TextStyle(fontSize = s.sp, lineHeight = (s * 1.3f).sp, fontWeight = FontWeight.SemiBold, color = Ink,
                letterSpacing = 0.2.sp)
            // слова целиком: самое длинное слово должно влезть в строку, иначе его разорвёт («иль-хуру / ф»)
            val words = remember(p.id) { p.lines.flatMap { it.read.split(Regex("\\s+")) }.filter { it.isNotBlank() } }
            fun backStyle(s: Float): TextStyle { val b = (s * 0.42f).coerceIn(11f, 18f); return TextStyle(fontSize = b.sp, lineHeight = (b * 1.3f).sp, color = Dim) }
            fun fits(s: Float): Boolean {
                val wide = readStyle(s).copy(fontWeight = FontWeight.ExtraBold)
                if (words.any { measurer.measure(it, wide, maxLines = 1, softWrap = false).size.width > w }) return false
                val r = measurer.measure(text(s), readStyle(s), constraints = Constraints(maxWidth = w))
                val bh = if (back.isBlank()) 0 else measurer.measure(back, backStyle(s), constraints = Constraints(maxWidth = w)).size.height + gap
                return r.size.height + bh <= h
            }
            val size = remember(p.id, w, h) {
                var lo = 12f
                var hi = 40f                       // не крупнее — так спокойнее читать
                if (fits(hi)) hi else {
                    repeat(9) { val mid = (lo + hi) / 2; if (fits(mid)) lo = mid else hi = mid }
                    lo
                }
            }
            Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center) {
                Text(text(size), style = readStyle(size))
                if (back.isNotBlank()) {
                    Spacer(Modifier.height(12.dp))
                    Text(back, style = backStyle(size))
                }
            }
        }
        Spacer(Modifier.height(14.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            val label = when (p.id) { m.playing -> "Стоп"; m.loading -> "Готовлю…"; else -> "Послушать" }
            Chip(if (m.playing == p.id) R.drawable.ic_stop else R.drawable.ic_speak, label, Modifier.weight(1f)) { m.play(p) }
            Chip(R.drawable.ic_full, "В камеру", Modifier.weight(1f)) { m.full = p }
        }
    }
}

/** История: прошлые фразы списком; коснуться — фраза снова на главном экране. */
@Composable
private fun History(m: Model) {
    Dialog(onDismissRequest = { m.history = false }, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Column(Modifier.fillMaxSize().background(Back).systemBarsPadding()) {
            Row(Modifier.fillMaxWidth().padding(start = 20.dp, end = 8.dp, top = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("История", fontSize = 22.sp, fontWeight = FontWeight.Black, color = Ink)
                Spacer(Modifier.weight(1f))
                Box(Modifier.size(48.dp).clip(CircleShape).clickable { m.history = false }, contentAlignment = Alignment.Center) {
                    Text("✕", fontSize = 22.sp, color = Ink)
                }
            }
            val list = rememberLazyListState(initialFirstVisibleItemIndex = (m.items.size - 1).coerceAtLeast(0))
            LazyColumn(Modifier.weight(1f).fillMaxWidth(), state = list, contentPadding = PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)) {
                itemsIndexed(m.items, key = { _, p -> p.id }) { _, p ->
                    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(Color.White.copy(alpha = 0.75f))
                        .clickable { m.pick = p.id; m.history = false }.padding(horizontal = 16.dp, vertical = 12.dp)) {
                        Text(stressed(p.lines), fontSize = 18.sp, lineHeight = 23.sp, fontWeight = FontWeight.Bold, color = Ink)
                        if (p.back.isNotBlank()) Text(p.back, fontSize = 13.sp, color = Dim, modifier = Modifier.padding(top = 4.dp))
                    }
                }
            }
        }
    }
}

@Composable
private fun Chip(icon: Int, text: String, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Row(modifier.height(42.dp).clip(RoundedCornerShape(20.dp)).background(Color(0x1A6B4FB8)).clickable(onClick = onClick)
        .padding(horizontal = 10.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.Center) {
        Icon(painterResource(icon), null, tint = ArInk, modifier = Modifier.size(18.dp))
        Spacer(Modifier.width(6.dp))
        Text(text, fontSize = 15.sp, color = ArInk, fontWeight = FontWeight.SemiBold, maxLines = 1, softWrap = false)
    }
}

// MARK: низ — подсказка и кнопка
@Composable
private fun Bottom(m: Model) {
    val status = when {
        m.recording && m.latched -> "Слушаю… нажмите, чтобы перевести"
        m.recording -> "Слушаю…"
        m.jobs > 0 -> "Перевожу…"
        m.hint.isNotEmpty() -> m.hint
        else -> "Держите и говорите"
    }
    Column(Modifier.fillMaxWidth().padding(bottom = 14.dp, top = 2.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Text(status, fontSize = 15.sp, color = if (m.recording) Stress else Dim, textAlign = TextAlign.Center,
            modifier = Modifier.heightIn(min = 22.dp).padding(horizontal = 24.dp))
        Spacer(Modifier.height(8.dp))
        Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
            MicButton(m)
            if (m.recording) Box(Modifier.align(Alignment.CenterStart).padding(start = 36.dp).size(56.dp).clip(CircleShape)
                .background(Color.White.copy(alpha = 0.7f)).clickable { m.cancel() }, contentAlignment = Alignment.Center) {
                Text("✕", fontSize = 22.sp, color = Ink)
            }
            if (m.jobs > 0 && !m.recording) CircularProgressIndicator(color = Stress, strokeWidth = 3.dp,
                modifier = Modifier.align(Alignment.CenterEnd).padding(end = 48.dp).size(32.dp))
        }
    }
}

@Composable
private fun MicButton(m: Model) {
    val grow by animateFloatAsState(if (m.recording) 1.08f + m.level * 0.5f else 1f, label = "mic")
    Box(Modifier.size(92.dp).scale(grow).clip(CircleShape)
        .background(if (m.recording) Brush.linearGradient(listOf(Color(0xFFFF5C8A), Color(0xFFFF7A59))) else Warm)
        .pointerInput(Unit) {
            detectTapGestures(onPress = {
                m.down()
                tryAwaitRelease()
                m.up()
            })
        }, contentAlignment = Alignment.Center) {
        Icon(painterResource(if (m.recording) R.drawable.ic_stop else R.drawable.ic_mic), "Говорить", tint = Color.White,
            modifier = Modifier.size(if (m.recording) 32.dp else 40.dp))
    }
}

// MARK: крупно для камеры
@Composable
private fun Full(p: Phrase, close: () -> Unit) {
    Dialog(onDismissRequest = close, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        val n = p.ar.length
        val size = when { n <= 18 -> 58.sp; n <= 36 -> 46.sp; n <= 70 -> 36.sp; n <= 120 -> 28.sp; else -> 22.sp }
        Box(Modifier.fillMaxSize().background(Brush.linearGradient(listOf(Color(0xFFFF6F9C), Color(0xFFFF9A6B), Color(0xFFB07CFF))))
            .clickable(onClick = close).padding(28.dp), contentAlignment = Alignment.Center) {
            Text(p.lines.joinToString("\n") { it.ar }, fontSize = size, lineHeight = size * 1.35f, fontWeight = FontWeight.Bold, color = Color.White,
                textAlign = TextAlign.Center, style = TextStyle(textDirection = TextDirection.Rtl,
                    shadow = Shadow(Color(0x55000000), blurRadius = 12f)))
            Text("Коснитесь, чтобы закрыть", fontSize = 13.sp, color = Color.White.copy(alpha = 0.75f),
                modifier = Modifier.align(Alignment.BottomCenter))
        }
    }
}

// MARK: настройки
@Composable
private fun Settings(m: Model, close: () -> Unit) {
    var sure by remember { mutableStateOf(false) }
    AlertDialog(onDismissRequest = close, confirmButton = { TextButton(onClick = close) { Text("Готово") } },
        title = { Text("Настройки") },
        text = {
            Column {
                Text("«Послушать» — голос по-арабски", fontWeight = FontWeight.SemiBold, color = Ink)
                listOf("Только в наушники (безопасно для эфира)", "И из динамика", "Выключен").forEachIndexed { i, t ->
                    Row(Modifier.fillMaxWidth().clickable { m.setVoiceMode(i) }, verticalAlignment = Alignment.CenterVertically) {
                        RadioButton(selected = m.voice == i, onClick = { m.setVoiceMode(i) })
                        Text(t, color = Ink)
                    }
                }
                Spacer(Modifier.height(12.dp))
                TextButton(onClick = { if (sure) { m.clear(); sure = false } else sure = true }) {
                    Text(if (sure) "Точно очистить историю?" else "Очистить историю", color = Stress)
                }
                TextButton(onClick = { m.logout(); close() }) { Text("Выйти (ввести PIN заново)", color = Dim) }
            }
        })
}
