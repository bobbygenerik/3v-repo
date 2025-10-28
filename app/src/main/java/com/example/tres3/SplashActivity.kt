package com.example.tres3

import android.content.Intent
import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.animation.core.*
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.graphics.graphicsLayer
import kotlinx.coroutines.delay

class SplashActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            SplashScreen()
        }
    }

    @Composable
    fun SplashScreen() {
        var alpha by remember { mutableStateOf(0.0f) }
        
        LaunchedEffect(Unit) {
            alpha = 1.0f
        }
        
        val animatedAlpha by animateFloatAsState(
            targetValue = alpha,
            animationSpec = tween(durationMillis = 3000, easing = EaseInOutCubic),
            label = "logoFadeIn"
        )

        LaunchedEffect(Unit) {
            delay(2500)
            startActivity(Intent(this@SplashActivity, SignInActivity::class.java))
            finish()
        }

        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(AppColors.BackgroundDark),
            contentAlignment = Alignment.Center
        ) {
            Image(
                painter = painterResource(id = R.drawable.newlogo3),
                contentDescription = "Splash Logo",
                modifier = Modifier
                    .size(300.dp)
                    .graphicsLayer(alpha = animatedAlpha)
            )
        }
    }
}