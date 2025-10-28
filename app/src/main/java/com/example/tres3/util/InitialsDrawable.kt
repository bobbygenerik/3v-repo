package com.example.tres3.util

import android.graphics.*
import android.graphics.drawable.Drawable

class InitialsDrawable(private val initials: String) : Drawable() {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#00C853") // Mint green
        style = Paint.Style.FILL
        textAlign = Paint.Align.CENTER
        textSize = 36f
        typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
    }
    override fun draw(canvas: Canvas) {
        val bounds = bounds
        val radius = Math.min(bounds.width(), bounds.height()) / 2f
        canvas.drawCircle(bounds.centerX().toFloat(), bounds.centerY().toFloat(), radius, paint)
        paint.color = Color.WHITE
        paint.textSize = radius
        val xPos = bounds.centerX().toFloat()
        val yPos = bounds.centerY() - ((paint.descent() + paint.ascent()) / 2)
        canvas.drawText(initials, xPos, yPos, paint)
    }
    override fun setAlpha(alpha: Int) { paint.alpha = alpha }
    override fun setColorFilter(colorFilter: ColorFilter?) { paint.colorFilter = colorFilter }
    override fun getOpacity(): Int = PixelFormat.TRANSLUCENT
}
