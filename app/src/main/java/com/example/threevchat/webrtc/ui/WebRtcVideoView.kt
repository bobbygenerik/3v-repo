package com.example.threevchat.webrtc.ui

import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import org.webrtc.EglBase
import org.webrtc.RendererCommon
import org.webrtc.SurfaceViewRenderer
import org.webrtc.VideoTrack

@Composable
fun WebRtcVideoView(
    modifier: Modifier = Modifier,
    eglContext: EglBase.Context?,
    videoTrack: VideoTrack?,
    mirror: Boolean = false,
    scalingType: RendererCommon.ScalingType = RendererCommon.ScalingType.SCALE_ASPECT_FILL
) {
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    var lastTrack by remember { mutableStateOf<VideoTrack?>(null) }
    AndroidView(
        modifier = modifier,
        factory = { ctx ->
            val view = SurfaceViewRenderer(ctx).apply {
                setZOrderMediaOverlay(true)
            }
            if (eglContext != null) {
                try { view.init(eglContext, null) } catch (_: Throwable) {}
            }
            view.setMirror(mirror)
            view.setScalingType(scalingType)
            if (videoTrack != null) {
                try { videoTrack.addSink(view); lastTrack = videoTrack } catch (_: Throwable) {}
            }
            // Manage release on lifecycle destroy
            val observer = object : DefaultLifecycleObserver {
                override fun onDestroy(owner: LifecycleOwner) {
                    try { if (lastTrack != null) lastTrack?.removeSink(view) } catch (_: Throwable) {}
                    try { view.release() } catch (_: Throwable) {}
                }
            }
            lifecycle.addObserver(observer)
            view
        },
        update = { view ->
            view.setMirror(mirror)
            view.setScalingType(scalingType)
            if (lastTrack !== videoTrack) {
                try { lastTrack?.removeSink(view) } catch (_: Throwable) {}
                try { videoTrack?.addSink(view) } catch (_: Throwable) {}
                lastTrack = videoTrack
            }
        }
    )
}
