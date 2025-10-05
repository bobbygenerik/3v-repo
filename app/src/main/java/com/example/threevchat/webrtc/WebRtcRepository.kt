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
    private val peers = mutableMapOf<String, PeerConnection>() // remoteId -> PC
    private val peerPendingCandidates = mutableMapOf<String, MutableList<IceCandidate>>()
    private var videoCapturer: VideoCapturer? = null
    private var videoSource: VideoSource? = null
    private var audioSource: AudioSource? = null
    private var videoTrack: VideoTrack? = null
    private var audioTrack: AudioTrack? = null
    private var videoSender: RtpSender? = null
    private var statsJob: Job? = null
    private var isRelayed = false
    private val pendingRemoteCandidates = mutableListOf<IceCandidate>()

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

    fun eglContext(): EglBase.Context = eglBase.eglBaseContext

    fun createPeerConnection(observer: PeerConnection.Observer): PeerConnection {
        val rtcConfig = PeerConnection.RTCConfiguration(WebRtcConfig.iceServers()).apply {
            sdpSemantics = PeerConnection.SdpSemantics.UNIFIED_PLAN
            tcpCandidatePolicy = PeerConnection.TcpCandidatePolicy.ENABLED
            continualGatheringPolicy = PeerConnection.ContinualGatheringPolicy.GATHER_CONTINUALLY
            if (com.example.threevchat.BuildConfig.TURN_FORCE_RELAY) {
                iceTransportsType = PeerConnection.IceTransportsType.RELAY
            }
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
        val pc = requireNotNull(peerConnection)
        if (pc.remoteDescription == null) {
            // Queue until remote description is set to avoid "AddIceCandidate failed" issues
            pendingRemoteCandidates += c
            Log.d("ICE", "Queued remote ICE candidate (no remoteDescription yet)")
        } else {
            pc.addIceCandidate(c)
        }
    }

    // ---- Multi-peer helpers ----
    fun ensurePeer(remoteId: String, observer: PeerConnection.Observer): PeerConnection {
        return peers.getOrPut(remoteId) {
            val rtcConfig = PeerConnection.RTCConfiguration(WebRtcConfig.iceServers()).apply {
                sdpSemantics = PeerConnection.SdpSemantics.UNIFIED_PLAN
                tcpCandidatePolicy = PeerConnection.TcpCandidatePolicy.ENABLED
                continualGatheringPolicy = PeerConnection.ContinualGatheringPolicy.GATHER_CONTINUALLY
                if (com.example.threevchat.BuildConfig.TURN_FORCE_RELAY) {
                    iceTransportsType = PeerConnection.IceTransportsType.RELAY
                }
            }
            val pc = pcFactory.createPeerConnection(rtcConfig, observer)!!
            videoTrack?.let { pc.addTrack(it) }
            audioTrack?.let { pc.addTrack(it) }
            peerPendingCandidates[remoteId] = mutableListOf()
            pc
        }
    }

    fun addIceCandidate(remoteId: String, c: IceCandidate) {
        val pc = peers[remoteId] ?: run {
            // If peer not created yet, save in list and return
            val list = peerPendingCandidates.getOrPut(remoteId) { mutableListOf() }
            list += c
            Log.d("ICE", "Queued candidate for $remoteId (peer not ready)")
            return
        }
        if (pc.remoteDescription == null) {
            peerPendingCandidates.getOrPut(remoteId) { mutableListOf() }.add(c)
            Log.d("ICE", "Queued candidate for $remoteId (no remoteDescription)")
        } else {
            pc.addIceCandidate(c)
        }
    }

    private fun drainPeerCandidates(remoteId: String) {
        val pc = peers[remoteId] ?: return
        val list = peerPendingCandidates[remoteId] ?: return
        list.forEach { pc.addIceCandidate(it) }
        list.clear()
        Log.d("ICE", "Drained candidates for $remoteId")
    }

    suspend fun createAndSetOffer(remoteId: String, observer: PeerConnection.Observer, onLocalSdp: (SessionDescription) -> Unit, iceRestart: Boolean = false) {
        val pc = ensurePeer(remoteId, observer)
        val offer = suspendCancellableCoroutine<SessionDescription> { cont ->
            val constraints = MediaConstraints().apply {
                if (iceRestart) {
                    mandatory.add(MediaConstraints.KeyValuePair("IceRestart", "true"))
                }
            }
            pc.createOffer(object : SdpObserver {
                override fun onCreateSuccess(sdp: SessionDescription) { if (cont.isActive) cont.resume(sdp) {} }
                override fun onCreateFailure(error: String) { cont.cancel(Throwable(error)) }
                override fun onSetSuccess() {}
                override fun onSetFailure(p0: String) {}
            }, constraints)
        }
        pc.setLocalDescription(SdpObserverStub(), offer)
        onLocalSdp(offer)
    }

    fun setRemoteOffer(remoteId: String, offer: SessionDescription, onAnswerReady: (SessionDescription) -> Unit, observer: PeerConnection.Observer) {
        val pc = ensurePeer(remoteId, observer)
        pc.setRemoteDescription(object : SdpObserver {
            override fun onSetSuccess() {
                drainPeerCandidates(remoteId)
                pc.createAnswer(object : SdpObserver {
                    override fun onCreateSuccess(sdp: SessionDescription) {
                        pc.setLocalDescription(SdpObserverStub(), sdp)
                        onAnswerReady(sdp)
                    }
                    override fun onCreateFailure(error: String) { Log.e("SDP", "createAnswer($remoteId) failed: $error") }
                    override fun onSetSuccess() {}
                    override fun onSetFailure(p0: String) {}
                }, MediaConstraints())
            }
            override fun onSetFailure(error: String) { Log.e("SDP", "setRemoteOffer($remoteId) failed: $error") }
            override fun onCreateSuccess(p0: SessionDescription) {}
            override fun onCreateFailure(p0: String) {}
        }, offer)
    }

    fun setRemoteAnswer(remoteId: String, answer: SessionDescription) {
        val pc = peers[remoteId] ?: return
        pc.setRemoteDescription(object : SdpObserver {
            override fun onSetSuccess() { drainPeerCandidates(remoteId) }
            override fun onSetFailure(error: String) { Log.e("SDP", "setRemoteAnswer($remoteId) failed: $error") }
            override fun onCreateSuccess(p0: SessionDescription) {}
            override fun onCreateFailure(p0: String) {}
        }, answer)
    }

    fun setRemoteAnswer(answer: SessionDescription) {
        val pc = requireNotNull(peerConnection)
        pc.setRemoteDescription(object : SdpObserver {
            override fun onSetSuccess() {
                drainPendingCandidates()
                startRelayMonitor()
            }
            override fun onSetFailure(p0: String) { Log.e("SDP", "setRemoteAnswer failed: $p0") }
            override fun onCreateSuccess(p0: SessionDescription) {}
            override fun onCreateFailure(p0: String) {}
        }, answer)
    }

    fun setRemoteOffer(offer: SessionDescription, onAnswerReady: (SessionDescription) -> Unit) {
        val pc = requireNotNull(peerConnection)
        pc.setRemoteDescription(object : SdpObserver {
            override fun onSetSuccess() {
                drainPendingCandidates()
                pc.createAnswer(object : SdpObserver {
                    override fun onCreateSuccess(sdp: SessionDescription) {
                        pc.setLocalDescription(SdpObserverStub(), sdp)
                        onAnswerReady(sdp)
                    }
                    override fun onCreateFailure(error: String) { Log.e("SDP", "createAnswer failed: $error") }
                    override fun onSetSuccess() {}
                    override fun onSetFailure(p0: String) {}
                }, MediaConstraints())
            }
            override fun onSetFailure(error: String) { Log.e("SDP", "setRemoteOffer failed: $error") }
            override fun onCreateSuccess(p0: SessionDescription) {}
            override fun onCreateFailure(p0: String) {}
        }, offer)
    }

    suspend fun createAndSetOffer(onLocalSdp: (SessionDescription) -> Unit, iceRestart: Boolean = false) {
        val pc = requireNotNull(peerConnection)
        val offer = suspendCancellableCoroutine<SessionDescription> { cont ->
            val constraints = MediaConstraints().apply {
                if (iceRestart) {
                    mandatory.add(MediaConstraints.KeyValuePair("IceRestart", "true"))
                }
            }
            pc.createOffer(object : SdpObserver {
                override fun onCreateSuccess(sdp: SessionDescription) {
                    if (cont.isActive) cont.resume(sdp) {}
                }
                override fun onCreateFailure(error: String) { cont.cancel(Throwable(error)) }
                override fun onSetSuccess() {}
                override fun onSetFailure(p0: String) {}
            }, constraints)
        }
        pc.setLocalDescription(SdpObserverStub(), offer)
        onLocalSdp(offer)
    }

    fun restartIceFor(remoteId: String, observer: PeerConnection.Observer, onLocalSdp: (SessionDescription) -> Unit) {
        scope.launch {
            try {
                createAndSetOffer(remoteId, observer, onLocalSdp, iceRestart = true)
            } catch (t: Throwable) {
                Log.e("ICE", "restartIceFor($remoteId) failed: ${t.message}")
            }
        }
    }

    fun restartIceForAll(observerProvider: (String) -> PeerConnection.Observer, onLocalSdp: (String, SessionDescription) -> Unit) {
        peers.keys.forEach { id ->
            scope.launch {
                try {
                    createAndSetOffer(id, observerProvider(id), { sdp -> onLocalSdp(id, sdp) }, iceRestart = true)
                } catch (t: Throwable) {
                    Log.e("ICE", "restartIceForAll($id) failed: ${t.message}")
                }
            }
        }
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
        if (params.encodings.isEmpty()) {
            Log.w("BITRATE", "No encodings present; skipping maxBitrate update")
            return
        }
        // Note: In newer WebRTC, RtpParameters.encodings may be immutable/final.
        // Update entries in-place without reassigning the encodings list.
        params.encodings.forEach { it.maxBitrateBps = bps }
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
        peers.values.forEach { it.dispose() }
        eglBase.release()
    }

    private fun drainPendingCandidates() {
        val pc = peerConnection ?: return
        if (pendingRemoteCandidates.isEmpty()) return
        pendingRemoteCandidates.forEach { pc.addIceCandidate(it) }
        pendingRemoteCandidates.clear()
        Log.d("ICE", "Drained queued remote ICE candidates")
    }

    private fun buildCameraCapturer(): VideoCapturer? {
        val enumerator = Camera2Enumerator(context)
        enumerator.deviceNames.firstOrNull { enumerator.isFrontFacing(it) }?.let {
            return enumerator.createCapturer(it, null)
        }
        enumerator.deviceNames.firstOrNull()?.let { return enumerator.createCapturer(it, null) }
        return null
    }

    // ---- Media controls ----
    fun setMicEnabled(enabled: Boolean) {
        audioTrack?.setEnabled(enabled)
    }
    fun setVideoEnabled(enabled: Boolean) {
        videoTrack?.setEnabled(enabled)
    }
    fun switchCamera() {
        val cap = videoCapturer
        if (cap is CameraVideoCapturer) {
            try { cap.switchCamera(null) } catch (_: Throwable) {}
        }
    }

    private class SdpObserverStub : SdpObserver {
        override fun onCreateSuccess(p0: SessionDescription) {}
        override fun onSetSuccess() {}
        override fun onCreateFailure(p0: String) {}
        override fun onSetFailure(p0: String) {}
    }
}
