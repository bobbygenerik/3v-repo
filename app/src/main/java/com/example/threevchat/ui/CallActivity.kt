package com.example.threevchat.ui

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import com.example.threevchat.R
import com.example.threevchat.signaling.CallSignalingRepository
import com.example.threevchat.signaling.IceCandidateDTO
import com.example.threevchat.webrtc.WebRtcRepository
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.collectLatest
import org.webrtc.*

class CallActivity : AppCompatActivity(), PeerConnection.Observer {
    private lateinit var repo: WebRtcRepository
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val signaling = CallSignalingRepository()

    private lateinit var localView: SurfaceViewRenderer
    private lateinit var remoteView: SurfaceViewRenderer

    private lateinit var role: String   // "caller" or "callee"
    private lateinit var sessionId: String

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_call)

        localView = findViewById(R.id.localView)
        remoteView = findViewById(R.id.remoteView)

        role = intent.getStringExtra("role") ?: "caller"
        sessionId = intent.getStringExtra("sessionId") ?: ""

        repo = WebRtcRepository(this, scope)
        val pc = repo.createPeerConnection(this)
        repo.attachRemoteRenderer(remoteView)
        repo.startLocalMedia(localView)
        repo.addLocalTracks()

        if (role == "caller") startAsCaller() else startAsCallee()
    }

    private fun startAsCaller() {
        scope.launch {
            repo.createAndSetOffer { offer ->
                scope.launch { signaling.setOffer(sessionId, offer.description) }
            }
            signaling.listenSession(sessionId).collectLatest { sess ->
                val answer = sess.answerSdp ?: return@collectLatest
                repo.setRemoteAnswer(SessionDescription(SessionDescription.Type.ANSWER, answer))
            }
        }
        scope.launch {
            signaling.listenCandidates(sessionId, fromOtherSide = "caller").collectLatest { dto ->
                repo.addIceCandidate(IceCandidate(dto.sdpMid, dto.sdpMLineIndex, dto.candidate))
            }
        }
    }

    private fun startAsCallee() {
        scope.launch {
            signaling.listenSession(sessionId).collectLatest { sess ->
                val offer = sess.offerSdp ?: return@collectLatest
                repo.setRemoteOffer(SessionDescription(SessionDescription.Type.OFFER, offer)) { answer ->
                    scope.launch { signaling.setAnswer(sessionId, answer.description) }
                }
            }
        }
        scope.launch {
            signaling.listenCandidates(sessionId, fromOtherSide = "callee").collectLatest { dto ->
                repo.addIceCandidate(IceCandidate(dto.sdpMid, dto.sdpMLineIndex, dto.candidate))
            }
        }
    }

    override fun onIceCandidate(candidate: IceCandidate) {
        val from = if (role == "caller") "caller" else "callee"
        signaling.addCandidate(sessionId, IceCandidateDTO(candidate.sdpMid, candidate.sdpMLineIndex, candidate.sdp, from))
    }

    override fun onAddTrack(receiver: RtpReceiver?, streams: Array<out MediaStream>?) {
        (receiver?.track() as? VideoTrack)?.addSink(remoteView)
    }

    override fun onAddStream(stream: MediaStream?) {
        stream?.videoTracks?.firstOrNull()?.addSink(remoteView)
    }

    override fun onDestroy() {
        super.onDestroy()
        scope.cancel()
        repo.dispose()
    }

    // Unused/no-op
    override fun onConnectionChange(newState: PeerConnection.PeerConnectionState) {}
    override fun onIceConnectionChange(newState: PeerConnection.IceConnectionState) {}
    override fun onIceConnectionReceivingChange(p0: Boolean) {}
    override fun onIceGatheringChange(p0: PeerConnection.IceGatheringState) {}
    override fun onSignalingChange(p0: PeerConnection.SignalingState) {}
    override fun onIceCandidatesRemoved(p0: Array<out IceCandidate>?) {}
    override fun onDataChannel(p0: DataChannel?) {}
    override fun onRenegotiationNeeded() {}
    override fun onStandardizedIceConnectionChange(p0: PeerConnection.IceConnectionState?) {}
    override fun onSelectedCandidatePairChanged(p0: CandidatePairChangeEvent?) {}
}
