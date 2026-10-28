package top.talyra42.verifin

import android.content.Context
import org.json.JSONObject

/**
 * Reads the app-lock preference before Flutter starts.
 *
 * Widget configuration is a separate Flutter engine and Activity. It must not show
 * ledger data or allow screenshots while the main app is protected, so native checks
 * fail closed for malformed values.
 */
object AppLockPreferences {
    private const val PREFERENCES_NAME = "FlutterSharedPreferences"
    private const val APP_LOCK_KEY = "flutter.verifin.app_lock.v1"

    fun isEnabled(context: Context): Boolean {
        val raw = context
            .getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
            .getString(APP_LOCK_KEY, null)
            ?: return false
        if (raw.isBlank()) return false
        return try {
            JSONObject(raw).optString("kind") != "none"
        } catch (_: Exception) {
            true
        }
    }
}
