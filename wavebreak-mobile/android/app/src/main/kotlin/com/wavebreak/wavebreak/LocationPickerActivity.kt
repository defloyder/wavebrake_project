package com.wavebreak.wavebreak

import android.app.Activity
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.TextView

/**
 * The server list over whatever is on screen, opened from the VPN
 * notification's "Server" button — pick one and the tunnel switches to it
 * (ConnectionManager.selectLocation via [QuickActions]) without opening
 * the app. A tiny native dialog on purpose: it has to appear instantly,
 * even when the Flutter side is still starting in the background. The
 * list comes from the snapshot the Dart side keeps in filesDir.
 */
class LocationPickerActivity : Activity() {

    private lateinit var list: LinearLayout
    private lateinit var progress: View

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setFinishOnTouchOutside(true)
        val snapshot = QuickTileService.readSnapshot(this)
        val items = snapshot?.optJSONArray("items")
        val currentId = snapshot?.optString("currentId").orEmpty()

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(18), dp(18), dp(18), dp(12))
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#F20C0709"))
                cornerRadius = dp(20).toFloat()
            }
        }
        root.addView(TextView(this).apply {
            text = snapshot?.optString("title")?.ifEmpty { null } ?: "WAVEBREAK"
            setTextColor(Color.parseColor("#F5F2F0"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 18f)
            setPadding(dp(4), 0, 0, dp(10))
        })
        progress = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            visibility = View.GONE
            setPadding(dp(4), dp(6), 0, dp(10))
            addView(ProgressBar(context).apply { layoutParams = LinearLayout.LayoutParams(dp(20), dp(20)) })
            addView(TextView(context).apply {
                text = snapshot?.optString("connecting")?.ifEmpty { null } ?: "…"
                setTextColor(Color.parseColor("#A6F5F2F0"))
                setPadding(dp(10), 0, 0, 0)
            })
        }
        root.addView(progress)
        list = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        if (items != null) {
            for (i in 0 until items.length()) {
                val item = items.optJSONObject(i) ?: continue
                list.addView(row(
                    id = item.optString("id"),
                    flag = item.optString("flag"),
                    title = item.optString("title"),
                    subtitle = item.optString("subtitle"),
                    current = item.optString("id") == currentId,
                ))
            }
        }
        root.addView(ScrollView(this).apply {
            addView(list)
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                (resources.displayMetrics.heightPixels * 0.6).toInt().coerceAtMost(dp(64) * (items?.length() ?: 1) + dp(8)),
            )
        })
        setContentView(root)
        window.setLayout(
            (resources.displayMetrics.widthPixels * 0.9).toInt(),
            ViewGroup.LayoutParams.WRAP_CONTENT,
        )
        window.setBackgroundDrawableResource(android.R.color.transparent)
    }

    private fun row(id: String, flag: String, title: String, subtitle: String, current: Boolean): View {
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            minimumHeight = dp(56)
            setPadding(dp(10), dp(6), dp(10), dp(6))
            background = GradientDrawable().apply {
                setColor(if (current) Color.parseColor("#33FF344E") else Color.TRANSPARENT)
                cornerRadius = dp(12).toFloat()
            }
            addView(TextView(context).apply {
                text = flag
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 22f)
                setPadding(0, 0, dp(12), 0)
            })
            addView(LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
                addView(TextView(context).apply {
                    text = title
                    setTextColor(Color.parseColor("#F5F2F0"))
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
                    maxLines = 1
                })
                if (subtitle.isNotEmpty()) addView(TextView(context).apply {
                    text = subtitle
                    setTextColor(Color.parseColor("#A6F5F2F0"))
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
                    maxLines = 1
                })
            })
            if (current) addView(TextView(context).apply {
                text = "✓"
                setTextColor(Color.parseColor("#7CEEE8"))
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 18f)
            })
            isClickable = true
            setOnClickListener { if (current) finish() else pick(id) }
        }
    }

    private fun pick(id: String) {
        for (i in 0 until list.childCount) list.getChildAt(i).isEnabled = false
        progress.visibility = View.VISIBLE
        QuickActions.dispatch(applicationContext, "location", id) { outcome ->
            if (outcome.openApp) startActivity(QuickActions.launchIntent(this))
            finish()
        }
    }

    private fun dp(v: Int): Int = (v * resources.displayMetrics.density).toInt()
}
