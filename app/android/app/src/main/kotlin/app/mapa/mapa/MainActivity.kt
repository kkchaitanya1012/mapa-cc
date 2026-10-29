package app.mapa.mapa

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Rings the phone for Mapa's own incoming-call screen (the one shown when the app is open):
 * the default ringtone, looping, plus a repeating vibration. It follows the phone's ringer
 * mode like a normal call: silent stays silent, vibrate only vibrates.
 */
class MainActivity : FlutterActivity() {
    private var ringtone: Ringtone? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.mapa/ring").setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> { startRinging(); result.success(null) }
                "stop" -> { stopRinging(); result.success(null) }
                else -> result.notImplemented()
            }
        }
    }

    private fun startRinging() {
        stopRinging()
        val mode = (getSystemService(Context.AUDIO_SERVICE) as AudioManager).ringerMode
        if (mode == AudioManager.RINGER_MODE_SILENT) return
        vibrator()?.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 900, 700, 900, 1500), 0))
        if (mode == AudioManager.RINGER_MODE_NORMAL) {
            ringtone = RingtoneManager.getRingtone(this, RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE))?.apply {
                audioAttributes = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) isLooping = true
                play()
            }
        }
    }

    private fun stopRinging() {
        ringtone?.stop()
        ringtone = null
        vibrator()?.cancel()
    }

    private fun vibrator(): Vibrator? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
            (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
        else
            @Suppress("DEPRECATION") getSystemService(Context.VIBRATOR_SERVICE) as Vibrator

    override fun onDestroy() {
        stopRinging()
        super.onDestroy()
    }
}
