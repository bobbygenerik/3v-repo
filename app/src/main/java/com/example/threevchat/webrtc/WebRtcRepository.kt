package com.example.threevchat.webrtc

import android.content.Context
import android.util.Log
import kotlinx.coroutines.*
import org.webrtc.*

class WebRtcRepository(
    private val context: Context,
    private val scope: CoroutineScope
) {
    private val eglBase = EglBase.create()
    private val pcFactory: PeerConnectionFactory
    private var peerConnection: PeerConnection? = null
    private var videoCapturer: VideoCapturer? = null
    private var videoSource: VideoSource? = null
    private var audioSource: AudioSource? = null
    private var videoTrack: VideoTrack? = null
    private var audioTrack: AudioTrack? = null
    private var videoSender: RtpSender? = null
    private var statsJob: Job? = null
    private var isRelayed = false

    init {
        PeerConnectionFactory.initialize(
            PeerConnectionFactory.InitializationOptions.builder(context).createInitializationOptions()
        )
        val enc = DefaultVideoEncoderFactory(eglBase.eglBaseContext, true, true)
        val dec = DefaultVideoDecoderFactory(eglBase.eglBaseContext)
        pcFactory = PeerConnectionFactory.builder()
            .setVideoEncoderFactory(enc)
            .setVideoDecoderFactory(dec)
            .createPeerConnectionFactory()
    }

    fun createPeerConnection(observer: PeerConnection.Observer): PeerConnection {
        val rtcConfig = PeerConnection.RTCConfiguration(WebRtcConfig.iceServers).apply {
            sdpSemantics = PeerConnection.SdpSemantics.UNIFIED_PLAN
            tcpCandidatePolicy = PeerConnection.TcpCandidatePolicy.ENABLED
            enableDtlsSrtp = true
            continualGatheringPolicy = PeerConnection.ContinualGatheringPolicy.GATHER_CONTINUALLY
        }
        peerConnection = pcFactory.createPeerConnection(rtcConfig, observer)
        return requireNotNull(peerConnection)
    }

    fun startLocalMedia(localRenderer: SurfaceViewRenderer) {
        localRenderer.init(eglBase.eglBaseContext, null)
        localRenderer.setMirror(true)
        val capturer = buildCameraCapturer() ?: error("No camera capturer")
        videoCapturer = capturer
        val helper = SurfaceTextureHelper.create("CaptureThread", eglBase.eglBaseContext)
        videoSource = pcFactory.createVideoSource(false)
        capturer.initialize(helper, context, videoSource!!.capturerObserver)
        capturer.startCapture(WebRtcConfig.TARGET_WIDTH, WebRtcConfig.TARGET_HEIGHT, WebRtcConfig.TARGET_FPS)
        videoTrack = pcFactory.createVideoTrack("v0", videoSource).apply { addSink(localRenderer) }
        audioSource = pcFactory.createAudioSource(MediaConstraints())
        audioTrack = pcFactory.createAudioTrack("a0", audioSource)
    }

    fun addLocalTracks() {
        val pc = requireNotNull(peerConnection)
        videoSender = pc.addTrack(requireNotNull(videoTrack))
        pc.addTrack(requireNotNull(audioTrack))
        setMaxBitrate(WebRtcConfig.BITRATE_DIRECT_BPS)
    }

    fun attachRemoteRenderer(remote: SurfaceViewRenderer) {
        remote.init(eglBase.eglBaseContext, null)
    }

    fun addIceCandidate(c: IceCandidate) {
        requireNotNull(peerConnection).addIceCandidate(c)
    }

    fun setRemoteAnswer(answer: SessionDescription) {
        requireNotNull(peerConnection).setRemoteDescription(SdpObserverStub(), answer)
        startRelayMonitor()
    }

    fun setRemoteOffer(offer: SessionDescription, onAnswerReady: (SessionDescription) -> Unit) {
        val pc = requireNotNull(peerConnection)
        pc.setRemoteDescription(SdpObserverStub(), offer)
        pc.createAnswer(object : SdpObserver {
            override fun onCreateSuccess(sdp: SessionDescription) {
                pc.setLocalDescription(SdpObserverStub(), sdp)
                onAnswerReady(sdp)
            }
            override fun onCreateFailure(p0: String?) {}
            override fun onSetSuccess() {}
            override fun onSetFailure(p0: String?) {}
        }, MediaConstraints())
    }

    suspend fun createAndSetOffer(onLocalSdp: (SessionDescription) -> Unit) {
        val pc = requireNotNull(peerConnection)
        val offer = suspendCancellableCoroutine<SessionDescription> { cont ->
            pc.createOffer(object : SdpObserver {
                override fun onCreateSuccess(sdp: SessionDescription) {
                    if (cont.isActive) cont.resume(sdp) {}
                }
                override fun onCreateFailure(error: String) = cont.cancel(Throwable(error))
                override fun onSetSuccess() {}
                override fun onSetFailure(p0: String?) {}
            }, MediaConstraints())
        }
        pc.setLocalDescription(SdpObserverStub(), offer)
        onLocalSdp(offer)
    }

    private fun startRelayMonitor() {
        statsJob?.cancel()
        statsJob = scope.launch(Dispatchers.Default) {
            while (isActive) {
                delay(3000)
                val pc = peerConnection ?: continue
                pc.getStats { report ->
                    try {
                        val t = report.statsMap.values.firstOrNull { it.type == "transport" }
                        val selId = t?.members?.get("selectedCandidatePairId") as? String ?: return@getStats
                        val pair = report.statsMap[selId] ?: return@getStats
                        val localId = pair.members["localCandidateId"] as? String ?: return@getStats
                        val remoteId = pair.members["remoteCandidateId"] as? String ?: return@getStats
                        val localType = report.statsMap[localId]?.members?.get("candidateType")
                        val remoteType = report.statsMap[remoteId]?.members?.get("candidateType")
                        val relayed = (localType == "relay") || (remoteType == "relay")
                        if (relayed != isRelayed) {
                            isRelayed = relayed
                            Log.i("ICE", "Relay=$isRelayed (local=$localType remote=$remoteType)")
                            setMaxBitrate(if (isRelayed) WebRtcConfig.BITRATE_RELAY_BPS else WebRtcConfig.BITRATE_DIRECT_BPS)
                        }
                    } catch (_: Throwable) {}
                }
            }
        }
    }

    private fun setMaxBitrate(bps: Int) {
        val sender = videoSender ?: return
        val params = sender.parameters
        val encs = if (params.encodings.isNotEmpty()) params.encodings else listOf(RtpParameters.Encoding(null, true, null, null, null, null))
        encs.forEach { it.maxBitrateBps = bps }
        params.encodings = encs
        sender.parameters = params
        Log.i("BITRATE", "maxBitrate=${bps / 1000} kbps")
    }

    fun dispose() {
        statsJob?.cancel()
        try { videoCapturer?.stopCapture() } catch (_: Throwable) {}
        videoCapturer?.dispose()
        videoSource?.dispose()
        audioSource?.dispose()
        peerConnection?.dispose()
        eglBase.release()
    }

    private fun buildCameraCapturer(): VideoCapturer? {
        val enumerator = Camera2Enumerator(context)
        enumerator.deviceNames.firstOrNull { enumerator.isFrontFacing(it) }?.let {
            return enumerator.createCapturer(it, null)
        }
        enumerator.deviceNames.firstOrNull()?.let { return enumerator.createCapturer(it, null) }
        return null
    }

    private class SdpObserverStub : SdpObserver {
        override fun onCreateSuccess(p0: SessionDescription?) {}
        override fun onSetSuccess() {}
        override fun onCreateFailure(p0: String?) {}
        override fun onSetFailure(p0: String?) {}
    }
}
