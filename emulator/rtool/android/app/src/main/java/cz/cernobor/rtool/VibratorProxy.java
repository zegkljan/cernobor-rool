package cz.cernobor.rtool;

import android.os.Vibrator;

public class VibratorProxy {
    private static final long[] CONTINUOUS_VIBRATION_PATTERN = new long[]{0, 100};

    private final Vibrator vibrator;

    public VibratorProxy(Vibrator vibrator) {
        this.vibrator = vibrator;
    }

    public void vibrate(long duration) {
        if (duration < 0) {
            vibrator.vibrate(CONTINUOUS_VIBRATION_PATTERN, 0);
        } else {
            vibrator.vibrate(duration);
        }
    }

    public void stop() {
        vibrator.cancel();
    }
}
