package com.antonkarpenko.ffmpegkit;

import static com.antonkarpenko.ffmpegkit.FFmpegKitFlutterPlugin.LIBRARY_NAME;

import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import java.util.concurrent.atomic.AtomicBoolean;

import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodChannel;

public class FFmpegKitFlutterMethodResultHandler {
    interface EventSinkProvider {
        EventChannel.EventSink get();
    }

    private final Handler handler;
    private final AtomicBoolean attached;

    FFmpegKitFlutterMethodResultHandler() {
        handler = new Handler(Looper.getMainLooper());
        attached = new AtomicBoolean(true);
    }

    void attach() {
        attached.set(true);
    }

    void detach() {
        attached.set(false);
        handler.removeCallbacksAndMessages(null);
    }

    public void successAsync(final MethodChannel.Result result, final Object object) {
        handler.post(() -> {
            if (!attached.get()) {
                return;
            } else if (result != null) {
                result.success(object);
            } else {
                Log.w(LIBRARY_NAME, String.format("ResultHandler can not send successful response %s on a null method call result.", object));
            }
        });
    }

    void successAsync(final EventSinkProvider eventSinkProvider, final Object object) {
        handler.post(() -> {
            if (!attached.get()) {
                return;
            }
            final EventChannel.EventSink eventSink = eventSinkProvider.get();
            if (eventSink != null) {
                eventSink.success(object);
            } else {
                Log.w(LIBRARY_NAME, String.format("ResultHandler can not send event %s on a null event sink.", object));
            }
        });
    }

    void errorAsync(final MethodChannel.Result result, final String errorCode, final String errorMessage) {
        errorAsync(result, errorCode, errorMessage, null);
    }

    void errorAsync(final MethodChannel.Result result, final String errorCode, final String errorMessage, final Object errorDetails) {
        handler.post(() -> {
            if (!attached.get()) {
                return;
            } else if (result != null) {
                result.error(errorCode, errorMessage, errorDetails);
            } else {
                Log.w(LIBRARY_NAME, String.format("ResultHandler can not send failure response %s:%s on a null method call result.", errorCode, errorMessage));
            }
        });
    }

    void notImplementedAsync(final MethodChannel.Result result) {
        handler.post(() -> {
            if (!attached.get()) {
                return;
            } else if (result != null) {
                result.notImplemented();
            } else {
                Log.w(LIBRARY_NAME, "ResultHandler can not send not implemented response on a null method call result.");
            }
        });
    }

}
