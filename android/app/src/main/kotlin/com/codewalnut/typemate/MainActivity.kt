package com.codewalnut.typemate

import android.content.ComponentName
import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import android.text.TextUtils
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private companion object {
        const val CHANNEL = "typemate/floating_mic"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isEnabled" -> result.success(isServiceEnabled())
                    "openSettings" -> {
                        openAccessibilitySettings()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun openAccessibilitySettings() {
        val component =
            ComponentName(this, TypeMateAccessibilityService::class.java)
                .flattenToString()
        val args = Bundle().apply { putString("extra_pref_show_fragment_args", component) }
        // Land directly on TypeMate's own toggle page (API 30+); fall back
        // to the full list if the OEM does not honor the detail deep link.
        val direct = Intent("android.settings.ACCESSIBILITY_DETAILS_SETTINGS")
            .putExtra("android.provider.extra.ACCESSIBILITY_COMPONENT_NAME", component)
            .putExtra(":settings:show_fragment_args", args)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            startActivity(direct)
        } catch (_: Exception) {
            startActivity(
                Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        }
    }

    private fun isServiceEnabled(): Boolean {
        val enabled = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
        ) ?: return false
        // Compare as ComponentName, not strings: entries can be the short
        // form (pkg/.Cls) - notably when enabled via adb or on some OEMs -
        // which does not string-equal the flattened full form.
        val ours = ComponentName(this, TypeMateAccessibilityService::class.java)
        val splitter = TextUtils.SimpleStringSplitter(':')
        splitter.setString(enabled)
        for (component in splitter) {
            if (ComponentName.unflattenFromString(component) == ours) {
                return true
            }
        }
        return false
    }
}
