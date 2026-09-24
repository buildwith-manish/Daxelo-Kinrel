// Daxelo-Kinrel-App/android/app/src/main/kotlin/com/daxelo/kinrel/PredictionWidgetProvider.kt
//
// Phase 3.21 — Home-screen widget for the Prediction Battle.
//
// Renders a 2x1 widget showing the top family's current prediction
// state. For multi-family users, a "1/N" cycle chip in the corner
// lets the user cycle through their families by tapping the chip.
// Long-press the chip → opens the family-picker sheet (TODO — for
// now, the chip just cycles through all families).
//
// Data flow:
//   1. The Dart side (pb_v1_prediction_widget_updater.dart) writes a
//      JSON array of families to SharedPreferences under
//      'kinrel_prediction_widget_data'.
//   2. This provider reads the JSON, picks the family at the
//      'kinrel_prediction_widget_selected_index' index, and renders
//      the card.
//   3. Tapping the cycle chip increments the index (mod N) and
//      re-renders. Tapping the card body deep-links into the app.
//
// The widget is a RemoteViews-based AppWidgetProvider — it doesn't
// run Dart. All the business logic (urgency scoring, countdown text)
// is computed on the Dart side and serialized into the JSON. The
// Kotlin side just renders + handles taps.

package com.daxelo.kinrel

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import androidx.core.content.edit
import org.json.JSONArray
import org.json.JSONObject

class PredictionWidgetProvider : AppWidgetProvider() {

    companion object {
        private const val DATA_KEY = "kinrel_prediction_widget_data"
        private const val COUNT_KEY = "kinrel_prediction_widget_count"
        private const val SELECTED_INDEX_KEY = "kinrel_prediction_widget_selected_index"
        private const val HOME_WIDGET_GROUP = "HomeWidgetPreferences"

        // Intent action for the cycle-chip tap.
        private const val ACTION_CYCLE = "com.daxelo.kinrel.action.CYCLE_PREDICTION_WIDGET"
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_CYCLE) {
            // Increment the selected index, then update all widgets.
            val prefs = context.getSharedPreferences(HOME_WIDGET_GROUP, Context.MODE_PRIVATE)
            val count = prefs.getInt(COUNT_KEY, 0)
            if (count == 0) return
            var idx = prefs.getInt(SELECTED_INDEX_KEY, 0)
            idx = (idx + 1) % count
            prefs.edit { putInt(SELECTED_INDEX_KEY, idx) }
            // Trigger an update for all widget instances.
            val mgr = AppWidgetManager.getInstance(context)
            val ids = mgr.getAppWidgetIds(
                android.content.ComponentName(context, PredictionWidgetProvider::class.java)
            )
            for (id in ids) {
                updateWidget(context, mgr, id)
            }
        }
    }

    private fun updateWidget(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int
    ) {
        val prefs = context.getSharedPreferences(HOME_WIDGET_GROUP, Context.MODE_PRIVATE)
        val count = prefs.getInt(COUNT_KEY, 0)
        val views = RemoteViews(context.packageName, R.layout.prediction_widget)

        if (count == 0) {
            // No data yet — show an empty state.
            views.setTextViewText(R.id.widget_title, "Prediction Battle")
            views.setTextViewText(R.id.widget_question, "Open the app to set up your family")
            views.setTextViewText(R.id.widget_countdown, "")
            views.setTextViewText(R.id.widget_cycle_chip, "")
            views.setViewVisibility(R.id.widget_cycle_chip, android.view.View.GONE)
            // Tapping the empty state opens the app.
            val openAppIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            views.setOnClickPendingIntent(
                R.id.widget_root,
                PendingIntent.getActivity(
                    context, appWidgetId, openAppIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
            )
            appWidgetManager.updateAppWidget(appWidgetId, views)
            return
        }

        // Read + parse the JSON.
        val jsonString = prefs.getString(DATA_KEY, "[]") ?: "[]"
        val families = try {
            JSONArray(jsonString)
        } catch (e: Exception) {
            JSONArray()
        }
        if (families.length() == 0) return

        // Pick the selected family (clamped to bounds).
        var idx = prefs.getInt(SELECTED_INDEX_KEY, 0)
        if (idx >= families.length()) idx = 0
        val family = families.optJSONObject(idx) ?: return

        val familyName = family.optString("family_name", "Family")
        val questionText = family.optString("question_text", "")
        val unitLabel = family.optString("unit_label", "")
        val status = family.optString("status", "open")
        val countdown = family.optString("countdown_text", "")
        val streakInDanger = family.optBoolean("streak_in_danger", false)
        val currentStreak = family.optInt("current_streak", 0)
        val familyId = family.optString("family_id", "")
        val myGuess = if (family.isNull("my_guess")) null else family.optDouble("my_guess")

        // ── Render ──────────────────────────────────────────────────
        views.setTextViewText(R.id.widget_title, "🔮 $familyName")
        views.setTextViewText(R.id.widget_question, questionText)
        if (unitLabel.isNotEmpty()) {
            views.setTextViewText(R.id.widget_question, "$questionText (in $unitLabel)")
        }

        // Status-specific copy.
        if (status == "revealed") {
            views.setTextViewText(R.id.widget_countdown, "Reveal is in — tap to see result")
        } else if (myGuess != null) {
            views.setTextViewText(R.id.widget_countdown, "Guess locked · $countdown")
        } else if (streakInDanger) {
            views.setTextViewText(
                R.id.widget_countdown,
                "🔥 $countdown (streak: $currentStreak)"
            )
        } else {
            views.setTextViewText(R.id.widget_countdown, "Submit · $countdown")
        }

        // Cycle chip — only shown if there's more than one family.
        if (count > 1) {
            views.setViewVisibility(R.id.widget_cycle_chip, android.view.View.VISIBLE)
            views.setTextViewText(R.id.widget_cycle_chip, "${idx + 1}/$count")
        } else {
            views.setViewVisibility(R.id.widget_cycle_chip, android.view.View.GONE)
        }

        // ── Tap intents ─────────────────────────────────────────────
        // Card body tap → deep-link to this family's prediction screen.
        val deepLink = "kinrel://family/$familyId/prediction-battle-v1"
        val cardIntent = Intent(Intent.ACTION_VIEW, Uri.parse(deepLink)).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        views.setOnClickPendingIntent(
            R.id.widget_root,
            PendingIntent.getActivity(
                context, appWidgetId, cardIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        )
        // Cycle chip tap → broadcast the ACTION_CYCLE intent, which
        // we handle in onReceive above to increment the index + update.
        val cycleIntent = Intent(context, PredictionWidgetProvider::class.java).apply {
            action = ACTION_CYCLE
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
        }
        views.setOnClickPendingIntent(
            R.id.widget_cycle_chip,
            PendingIntent.getBroadcast(
                context, appWidgetId, cycleIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        )

        appWidgetManager.updateAppWidget(appWidgetId, views)
    }
}
