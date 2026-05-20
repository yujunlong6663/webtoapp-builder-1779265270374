#!/bin/bash

echo "=== Patching Android permissions ==="

MANIFEST_FILE="android/app/src/main/AndroidManifest.xml"

if [ ! -f "$MANIFEST_FILE" ]; then
    echo "ERROR: AndroidManifest.xml not found!"
    exit 1
fi

# 1. Add all required permissions to AndroidManifest.xml
for perm in "android.permission.ACCESS_FINE_LOCATION" "android.permission.ACCESS_COARSE_LOCATION" "android.permission.CAMERA" "android.permission.READ_MEDIA_IMAGES" "android.permission.READ_EXTERNAL_STORAGE" "android.permission.READ_CONTACTS" "android.permission.WRITE_CONTACTS" "android.permission.CALL_PHONE" "android.permission.READ_PHONE_STATE"; do
    if ! grep -q "$perm" "$MANIFEST_FILE"; then
        sed -i "/<\/manifest>/i\    <uses-permission android:name=\"$perm\" />" "$MANIFEST_FILE"
        echo "Added permission: $perm"
    fi
done

# 2. Add tel intent query for phone calls
if ! grep -q "android.intent.action.DIAL" "$MANIFEST_FILE"; then
    if grep -q "<queries>" "$MANIFEST_FILE"; then
        sed -i '/<queries>/a\\        <intent>\n            <action android:name="android.intent.action.DIAL" />\n            <data android:scheme="tel" />\n        </intent>' "$MANIFEST_FILE"
    else
        sed -i '/<application/i\\    <queries>\n        <intent>\n            <action android:name="android.intent.action.DIAL" />\n            <data android:scheme="tel" />\n        </intent>\n    </queries>' "$MANIFEST_FILE"
    fi
fi

# 3. Add usesCleartextTraffic to allow HTTP URLs
if ! grep -q "usesCleartextTraffic" "$MANIFEST_FILE"; then
    sed -i 's/<application/<application android:usesCleartextTraffic="true"/' "$MANIFEST_FILE"
    echo "Added usesCleartextTraffic"
fi

# 4. Replace MainActivity with custom one that handles permissions
ACTIVITY_DIR="android/app/src/main/java/com/webtoapp/app"
# Remove old MainActivity files (could be .java or .kt)
rm -f "$ACTIVITY_DIR/MainActivity.java" "$ACTIVITY_DIR/MainActivity.kt" 2>/dev/null || true
# Also search for any other MainActivity locations
find android/app/src/main/java -name "MainActivity.*" -delete 2>/dev/null || true
mkdir -p "$ACTIVITY_DIR"
cat > "$ACTIVITY_DIR/MainActivity.java" << 'MAINACTIVITY_EOF'
package com.webtoapp.app;

import android.content.pm.PackageManager;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.webkit.WebView;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;
import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {

    private static final String TAG = "WebToApp";
    private static final int PERM_REQ = 100;
    private String[] reqPerms = new String[]{"android.permission.ACCESS_FINE_LOCATION", "android.permission.ACCESS_COARSE_LOCATION", "android.permission.CAMERA", "android.permission.READ_MEDIA_IMAGES", "android.permission.READ_EXTERNAL_STORAGE", "android.permission.READ_CONTACTS", "android.permission.WRITE_CONTACTS", "android.permission.CALL_PHONE", "android.permission.READ_PHONE_STATE"};
    private Handler gpsTimer = null;

    @Override
    public void onCreate(Bundle b) {
        super.onCreate(b);
        Log.d(TAG, "onCreate");
        new Handler(Looper.getMainLooper()).postDelayed(new Runnable() {
            public void run() { requestPerms(); }
        }, 1500);
        new Handler(Looper.getMainLooper()).postDelayed(new Runnable() {
            public void run() { setupGps(); }
        }, 3000);
    }

    private void setupGps() {
        try {
            if (getBridge() == null) {
                new Handler(Looper.getMainLooper()).postDelayed(new Runnable() {
                    public void run() { setupGps(); }
                }, 2000);
                return;
            }
            WebView wv = getBridge().getWebView();
            if (wv == null) {
                new Handler(Looper.getMainLooper()).postDelayed(new Runnable() {
                    public void run() { setupGps(); }
                }, 2000);
                return;
            }
            injectGps(wv);
            gpsTimer = new Handler(Looper.getMainLooper());
            gpsTimer.postDelayed(new Runnable() {
                public void run() {
                    if (gpsTimer == null) return;
                    try {
                        WebView v = getBridge().getWebView();
                        if (v != null) injectGps(v);
                    } catch (Exception ex) {
                        Log.e(TAG, "GPS inject err: " + ex.getMessage());
                    }
                    if (gpsTimer != null) gpsTimer.postDelayed(this, 5000);
                }
            }, 5000);
            Log.d(TAG, "GPS override started");
        } catch (Exception e) {
            Log.e(TAG, "GPS setup err: " + e.getMessage());
        }
    }

    private void injectGps(WebView wv) {
        String js = "(function(){if(navigator.geolocation){var g=navigator.geolocation;var og=g.getCurrentPosition.bind(g);var ow=g.watchPosition.bind(g);g.getCurrentPosition=function(s,e,o){o=o||{};o.enableHighAccuracy=true;return og(s,e,o)};g.watchPosition=function(s,e,o){o=o||{};o.enableHighAccuracy=true;return ow(s,e,o)}}})();";
        wv.evaluateJavascript(js, null);
    }

    @Override
    protected void onDestroy() {
        gpsTimer = null;
        super.onDestroy();
    }

    private void requestPerms() {
        if (reqPerms == null || reqPerms.length == 0) return;
        java.util.ArrayList needed = new java.util.ArrayList();
        for (int i = 0; i < reqPerms.length; i++) {
            if (ContextCompat.checkSelfPermission(this, reqPerms[i]) != PackageManager.PERMISSION_GRANTED) {
                needed.add(reqPerms[i]);
            }
        }
        if (needed.size() > 0) {
            String[] perms = new String[needed.size()];
            for (int j = 0; j < needed.size(); j++) perms[j] = (String)needed.get(j);
            ActivityCompat.requestPermissions(this, perms, PERM_REQ);
        }
    }

    @Override
    public void onRequestPermissionsResult(int reqCode, String[] perms, int[] results) {
        super.onRequestPermissionsResult(reqCode, perms, results);
    }
}

MAINACTIVITY_EOF
echo "Custom MainActivity.java created at $ACTIVITY_DIR/MainActivity.java"
cat "$ACTIVITY_DIR/MainActivity.java" | head -5

# 4. Copy custom icon if exists
if [ -f "app-icon.png" ]; then
    echo "Custom icon detected, copying..."
    for dir in mdpi hdpi xhdpi xxhdpi xxxhdpi; do
        mkdir -p "android/app/src/main/res/mipmap-$dir"
        cp app-icon.png "android/app/src/main/res/mipmap-$dir/ic_launcher.png"
    done
fi

echo "=== Permission patch completed! ==="
echo "Manifest permissions added: 9"
echo "Runtime permissions: 9"