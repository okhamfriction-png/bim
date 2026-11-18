package com.okhamfriction.bim

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Typeface
import android.text.SpannableString
import android.text.Spanned
import android.text.style.ForegroundColorSpan
import android.text.style.StyleSpan
import android.view.View
import android.widget.RemoteViews
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * Widget d'écran d'accueil : les tâches du sprint à gauche (4/6), l'agenda du jour à droite (2/6).
 * Il lit le résumé que l'appli écrit dans ses préférences sous la clé « widget ».
 */
class BimWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) manager.updateAppWidget(id, build(context))
    }

    companion object {
        private val taskIds = intArrayOf(R.id.t1, R.id.t2, R.id.t3)
        private val agendaIds = intArrayOf(R.id.a1, R.id.a2, R.id.a3)
        /** Fond et icône d'une tâche d'après sa catégorie. */
        private fun look(cat: String, call: Boolean): Pair<Int, String> = when {
            call -> Pair(R.drawable.bim_w_mission, "📞")
            cat == "Mission" -> Pair(R.drawable.bim_w_mission, "💼")
            cat == "Contenu" -> Pair(R.drawable.bim_w_contenu, "🎬")
            cat == "Destiny" -> Pair(R.drawable.bim_w_destiny, "🎭")
            cat == "Parking" -> Pair(R.drawable.bim_w_parking, "🅿️")
            else -> Pair(R.drawable.bim_w_personnel, "📘")
        }

        fun refresh(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, BimWidget::class.java))
            for (id in ids) manager.updateAppWidget(id, build(context))
        }

        private fun build(context: Context): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.bim_widget)
            val open = PendingIntent.getActivity(
                context, 0, Intent(context, MainActivity::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.root, open)

            val raw = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                .getString("flutter.widget", null)
            val data = try { if (raw == null) null else JSONObject(raw) } catch (e: Exception) { null }

            // Gauche : les tâches du sprint, par priorité.
            val tasks = data?.optJSONArray("tasks")
            for (i in taskIds.indices) {
                val t = tasks?.optJSONObject(i)
                if (t == null) {
                    views.setViewVisibility(taskIds[i], View.GONE)
                    continue
                }
                val (bg, icon) = look(t.optString("c", "Personnel"), t.optBoolean("call", false))
                views.setTextViewText(taskIds[i], "$icon  ${t.optString("t")}")
                views.setInt(taskIds[i], "setBackgroundResource", bg)
                views.setViewVisibility(taskIds[i], View.VISIBLE)
            }
            if (data == null || (tasks?.length() ?: 0) == 0) {
                views.setTextViewText(taskIds[0], if (data == null) "Ouvre Bim pour remplir le widget" else "✅  Sprint : rien à faire")
                views.setInt(taskIds[0], "setBackgroundResource", R.drawable.bim_w_parking)
                views.setViewVisibility(taskIds[0], View.VISIBLE)
            }

            // Droite : l'agenda du jour.
            val now = Date()
            val key = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(now)
            views.setTextViewText(
                R.id.right_title,
                SimpleDateFormat("EEE d MMM", Locale.FRENCH).format(now).replaceFirstChar { it.uppercase() }
            )
            val day = data?.optJSONObject("days")?.optJSONObject(key)
            val week = day?.optString("week", "") ?: ""
            views.setTextViewText(R.id.week, week)
            views.setTextColor(
                R.id.week,
                if (day?.optBoolean("kids", false) == true) 0xFFEC4899.toInt() else 0xFF0EA5E9.toInt()
            )
            views.setViewVisibility(R.id.week, if (week.isEmpty()) View.GONE else View.VISIBLE)
            // Seulement ce qui reste de la journée.
            val cal = Calendar.getInstance()
            val nowMin = cal.get(Calendar.HOUR_OF_DAY) * 60 + cal.get(Calendar.MINUTE)
            val all = day?.optJSONArray("lines")
            val left = ArrayList<JSONObject>()
            if (all != null) {
                for (i in 0 until all.length()) {
                    val l = all.optJSONObject(i) ?: continue
                    if (l.optInt("end", 24 * 60) >= nowMin) left.add(l)
                }
            }
            for (i in agendaIds.indices) {
                val l = left.getOrNull(i)
                if (l == null) {
                    views.setViewVisibility(agendaIds[i], View.GONE)
                    continue
                }
                val hour = l.optString("h")
                val text = SpannableString("$hour  ${l.optString("l")}")
                text.setSpan(StyleSpan(Typeface.BOLD), 0, hour.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                text.setSpan(ForegroundColorSpan(0xFFF59E0B.toInt()), 0, hour.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                views.setTextViewText(agendaIds[i], text)
                views.setViewVisibility(agendaIds[i], View.VISIBLE)
            }
            if (left.isEmpty()) {
                views.setTextViewText(
                    agendaIds[0],
                    if (day == null) "Ouvre Bim" else if (all == null || all.length() == 0) "Rien de fixe" else "Plus rien de fixe"
                )
                views.setViewVisibility(agendaIds[0], View.VISIBLE)
            }
            return views
        }
    }
}
