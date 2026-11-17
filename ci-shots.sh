#!/bin/bash
# Снимки экранов «Tapny Эфир» в эмуляторе: вход, лента, крупно для камеры, запись, настройки
mkdir -p shots
adb install -r ci.apk
adb shell pm grant com.pavliq55.efir android.permission.RECORD_AUDIO
for d in login main long hist full rec; do
  adb shell am force-stop com.pavliq55.efir
  adb shell am start -n com.pavliq55.efir/.MainActivity --es demo $d
  sleep 6
  adb exec-out screencap -p > shots/$d.png
done
# настройки: шестерёнка справа вверху
adb shell am force-stop com.pavliq55.efir
adb shell am start -n com.pavliq55.efir/.MainActivity --es demo main
sleep 5
W=$(adb shell wm size | grep -o '[0-9]*x[0-9]*' | tail -1); X=${W%x*}; D=$(adb shell wm density | grep -o '[0-9]*' | tail -1)
adb shell input tap $((X - 32 * D / 160)) $(( (24 + 30) * D / 160 ))
sleep 2
adb exec-out screencap -p > shots/settings.png
# живой запуск без демо: экран входа по PIN, приложение не падает
adb shell am force-stop com.pavliq55.efir
adb shell am start -n com.pavliq55.efir/.MainActivity
sleep 5
adb exec-out screencap -p > shots/start.png
adb logcat -d | grep -E "AndroidRuntime|FATAL|efir" | tail -40 > shots/logcat.txt
ls -la shots
