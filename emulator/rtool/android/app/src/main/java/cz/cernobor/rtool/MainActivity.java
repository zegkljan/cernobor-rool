package cz.cernobor.rtool;

import android.annotation.TargetApi;
import android.media.*;
import android.os.Build;
import android.os.Bundle;

import android.os.Vibrator;
import io.flutter.app.FlutterActivity;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugins.GeneratedPluginRegistrant;

public class MainActivity extends FlutterActivity {
    private static final String CHANNEL = "cernobor";
    private AudioTrack audioTrack;
    private VibratorProxy vibratorProxy;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        GeneratedPluginRegistrant.registerWith(this);

        new MethodChannel(getFlutterView(), CHANNEL).setMethodCallHandler(
                new MethodChannel.MethodCallHandler() {
                    @Override
                    public void onMethodCall(MethodCall methodCall, MethodChannel.Result result) {
                        switch (methodCall.method) {
                            case "playFrequency": {
                                int frequency = methodCall.<Integer>argument("frequency");
                                Integer duration = methodCall.<Integer>argument("duration");
                                if (duration == null) {
                                    playFrequency(frequency);
                                } else {
                                    playFrequency(frequency, duration);
                                }
                                break;
                            }
                            case "stopSound":
                                stopSound();
                                break;
                            case "vibrate": {
                                Double level = methodCall.argument("level");
                                if (vibratorProxy == null) {
                                    vibratorProxy = new VibratorProxy((Vibrator) getSystemService(VIBRATOR_SERVICE));
                                }
                                vibratorProxy.vibrate(level);
                                break;
                            }
                            case "stopVibrate":
                                vibratorProxy.stop();
                                break;
                        }
                    }
                }
        );
    }

    @TargetApi(Build.VERSION_CODES.ECLAIR)
    private void playFrequency(int frequency, int duration) {
        int sampleRate = 25000;
        int samplesNum = duration * sampleRate / 1000;
        byte[] snd = generateSamples(frequency, sampleRate, samplesNum);

        stopSound();
        audioTrack = new AudioTrack(
                AudioManager.STREAM_ALARM,
                sampleRate,
                AudioFormat.CHANNEL_CONFIGURATION_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                samplesNum,
                AudioTrack.MODE_STATIC
        );
        audioTrack.write(snd, 0, snd.length);
        audioTrack.play();
    }

    @TargetApi(Build.VERSION_CODES.ECLAIR)
    private void playFrequency(int frequency) {
        int sampleRate = 25000;
        int samplesNum = sampleRate / 2;
        byte[] snd = generateSamples(frequency, sampleRate, samplesNum);

        stopSound();
        audioTrack = new AudioTrack(
                AudioManager.STREAM_ALARM,
                sampleRate,
                AudioFormat.CHANNEL_CONFIGURATION_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                snd.length,
                AudioTrack.MODE_STATIC
        );
        audioTrack.write(snd, 0, snd.length);
        audioTrack.setLoopPoints(0, samplesNum, -1);
        audioTrack.play();
    }

    @TargetApi(Build.VERSION_CODES.CUPCAKE)
    private void stopSound() {
        if (audioTrack != null) {
            audioTrack.release();
            audioTrack = null;
        }
    }

    private byte[] generateSamples(int frequency, int sampleRate, int samplesNum) {
        byte[] snd = new byte[2 * samplesNum];
        for (int i = 0; i < samplesNum; i++) {
            double sample = Math.sin(2 * Math.PI * i / (sampleRate / frequency));
            final short val = (short) (sample * 32767);
            snd[2 * i] = (byte) (val & 0x00ff);
            snd[2 * i + 1] = (byte) ((val & 0xff00) >>> 8);
        }
        return snd;
    }
}
