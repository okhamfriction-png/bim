package com.okhamfriction.bim

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.view.ViewGroup
import android.widget.Button
import android.widget.CheckBox
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.SeekBar
import android.widget.TextView

/** Réglages du widget, gardés côté Android pour être lus par le widget comme par l'appli. */
object WidgetPrefs {
    private fun prefs(c: Context) = c.getSharedPreferences("bim_widget", Context.MODE_PRIVATE)
    fun isSet(c: Context) = prefs(c).contains("alpha")
    fun alpha(c: Context) = prefs(c).getInt("alpha", 100).coerceIn(0, 100)
    fun prios(c: Context): List<Int> =
        (prefs(c).getString("prios", null) ?: "0,1,2,3,4").split(",").mapNotNull { it.trim().toIntOrNull() }
            .filter { it in 0..4 }.ifEmpty { listOf(0, 1, 2, 3, 4) }
    fun save(c: Context, alpha: Int, prios: List<Int>) {
        prefs(c).edit().putInt("alpha", alpha.coerceIn(0, 100))
            .putString("prios", prios.sorted().joinToString(",")).apply()
        BimWidget.refresh(c)
    }
}

/** Écran « Paramètres » ouvert par un appui long sur le widget. */
class WidgetConfigActivity : Activity() {
    private val names = arrayOf(
        "P0 · Non négociable", "P1 · Important", "P2 · Si le temps", "P3 · Petite tâche", "P4 · Parking"
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val id = intent?.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
            ?: AppWidgetManager.INVALID_APPWIDGET_ID
        val ok = Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
        setResult(RESULT_OK, ok)
        title = "Widget Bim"

        val d = resources.displayMetrics.density
        fun dp(v: Int) = (v * d).toInt()
        val col = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(24), dp(24), dp(24), dp(24))
        }
        fun label(text: String, size: Float, top: Int) = TextView(this).apply {
            this.text = text
            textSize = size
            setPadding(0, dp(top), 0, dp(8))
        }

        val alphaLabel = label("", 17f, 16)
        val seek = SeekBar(this).apply {
            max = 20
            progress = WidgetPrefs.alpha(this@WidgetConfigActivity) / 5
        }
        fun showAlpha() { alphaLabel.text = "Opacité du fond : ${seek.progress * 5} %" }
        showAlpha()
        col.addView(alphaLabel)
        col.addView(seek)

        col.addView(label("Priorités affichées", 17f, 24))
        val current = WidgetPrefs.prios(this)
        val boxes = names.mapIndexed { i, n ->
            CheckBox(this).apply {
                text = n
                textSize = 17f
                isChecked = i in current
                setPadding(dp(8), dp(10), 0, dp(10))
            }
        }
        boxes.forEach { col.addView(it) }

        fun save() {
            val chosen = boxes.indices.filter { boxes[it].isChecked }.ifEmpty { listOf(0, 1, 2, 3, 4) }
            WidgetPrefs.save(this, seek.progress * 5, chosen)
        }
        // Chaque réglage s'applique tout de suite : le widget change pendant qu'on règle.
        seek.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(s: SeekBar?, p: Int, fromUser: Boolean) { showAlpha() }
            override fun onStartTrackingTouch(s: SeekBar?) {}
            override fun onStopTrackingTouch(s: SeekBar?) { save() }
        })
        boxes.forEach { b -> b.setOnCheckedChangeListener { _, _ -> save() } }

        col.addView(Button(this).apply {
            text = "Terminé"
            textSize = 17f
            setOnClickListener { save(); finish() }
        }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
            topMargin = dp(24)
        })
        setContentView(ScrollView(this).apply {
            fitsSystemWindows = true
            addView(col)
        })
    }
}
