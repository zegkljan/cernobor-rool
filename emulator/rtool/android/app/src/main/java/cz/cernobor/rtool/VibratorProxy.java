package cz.cernobor.rtool;

import android.os.Vibrator;

public class VibratorProxy {
    private static final int MAX_MODE = 1000;
    private static final int CYCLE_DURATION = 1000;
    private final long[][] modes;

    private final Vibrator vibrator;

    public VibratorProxy(Vibrator vibrator) {
        this.vibrator = vibrator;

        modes = new long[MAX_MODE][2];
        for (int i = 0; i < MAX_MODE - 1; i++) {
            modes[i][0] = (i + 1) * CYCLE_DURATION / MAX_MODE;
            modes[i][1] = CYCLE_DURATION - (i + 1) * CYCLE_DURATION / MAX_MODE;
        }
        modes[MAX_MODE - 1][0] = CYCLE_DURATION;
        modes[MAX_MODE - 1][1] = 0;
    }

    public void vibrate(double level) {
        vibrator.cancel();
        int mode = levelToMode(level);
        if (mode == 0) {
            return;
        }
        vibrator.vibrate(modes[mode], 0);
    }

    public void stop() {
        vibrator.cancel();
    }

    private static int levelToMode(double level) {
        if (level <= 0.0) {
            return 0;
        }
        if (level >= 1.0) {
            return MAX_MODE - 1;
        }
        return (int) Math.round((MAX_MODE - 1) * level);
    }
}
