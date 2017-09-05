package cz.cernobor.rtool;

import android.os.Vibrator;

public class VibratorProxy {
    private final Vibrator vibrator;

    private static final long[][] MODES = new long[][]{
            {1000, 0},
            {900, 100},
            {800, 200},
            {700, 300},
            {600, 400},
            {500, 500},
            {400, 600},
            {300, 700},
            {200, 800},
            {100, 900},
            {0, 1000},
    };

    public VibratorProxy(Vibrator vibrator) {
        this.vibrator = vibrator;
    }

    public void vibrate(int level) {
        vibrator.vibrate(MODES[capLevel(level)], 0);
    }

    public void stop() {
        vibrator.cancel();
    }

    private static int capLevel(int level) {
        return Math.max(0, Math.min(10, level));
    }
}
