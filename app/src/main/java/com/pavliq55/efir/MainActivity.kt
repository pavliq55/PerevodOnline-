package com.pavliq55.efir

import android.Manifest
import android.content.pm.PackageManager
import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge

class MainActivity : ComponentActivity() {
    private val mic = Mic()
    private lateinit var model: Model

    override fun onCreate(saved: Bundle?) {
        super.onCreate(saved)
        enableEdgeToEdge()
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)   // во время эфира экран не гаснет
        model = Model(applicationContext, mic, intent.getStringExtra("demo"))
        setContent { EfirApp(model, onMicGranted = { mic.start() }) }
    }

    override fun onResume() {
        super.onResume()
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) mic.start()
    }

    override fun onPause() {
        model.onPause()
        mic.stop()                       // ушли с экрана — микрофон выключен совсем
        super.onPause()
    }
}
