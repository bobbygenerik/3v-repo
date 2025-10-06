package com.example.threevchat.ui

import android.Manifest
import android.content.pm.PackageManager
import android.os.Bundle
import android.widget.Toast
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import com.example.threevchat.R
import com.example.threevchat.signaling.CallSignalingRepository
import com.example.threevchat.signaling.IceCandidateDTO
import com.example.threevchat.webrtc.WebRtcRepository
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.collectLatest
import org.webrtc.*
import com.google.firebase.auth.FirebaseAuth

class CallActivity : ComponentActivity(), PeerConnection.Observer {
    private var repo: WebRtcRepository? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val signaling = CallSignalingRepository()

    private lateinit var localView: SurfaceViewRenderer
    private lateinit var remoteView: SurfaceViewRenderer
    private val extraRenderers = mutableMapOf<String, SurfaceViewRenderer>() // remoteId -> view
    private val offersStarted = mutableSetOf<String>()
    private var mainRemoteId: String? = null
    private val gapDp = 8
    private val sideMarginDp = 12
    private val tileMinHeightDp = 120
    private val tileMaxHeightDp = 220

    private lateinit var role: String   // "caller" or "callee"
    private lateinit var sessionId: String
    private lateinit var selfId: String
    private var useMesh = com.example.threevchat.BuildConfig.CALL_USE_MESH
    private var speakerOn = false
    private var micOn = true
    private var camOn = true
    private var debugVisible = false
    private var debugText: android.widget.TextView? = null
    private val listenerRegs = mutableListOf<com.google.firebase.firestore.ListenerRegistration>()

    private val requestPermissions = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { result ->
        val cameraOk = result[Manifest.permission.CAMERA] == true
        val micOk = result[Manifest.permission.RECORD_AUDIO] == true
        if (cameraOk && micOk) {
            startWebRtc()
        } else {
            Toast.makeText(this, "Camera and microphone are required", Toast.LENGTH_LONG).show()
            finish()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_call)

        localView = findViewById(R.id.localView)
        remoteView = findViewById(R.id.remoteView)
    debugText = findViewById(R.id.debugOverlay)
        findViewById<android.widget.ImageButton>(R.id.btnEndCall)?.setOnClickListener {
            scope.launch { signaling.end(sessionId) }
            if (useMesh) {
                scope.launch {
                    try { signaling.leaveSession(sessionId, selfId) } catch (_: Throwable) {}
                }
            }
            finish()
        }
        findViewById<android.widget.ImageButton>(R.id.btnAddPerson)?.setOnClickListener { showAddPersonDialog() }
        findViewById<android.widget.ImageButton>(R.id.btnReconnect)?.setOnClickListener { reconnectAll() }
        findViewById<android.widget.ImageButton>(R.id.btnMenu)?.setOnClickListener {
            showSettingsDialog()
        }

        role = intent.getStringExtra("role") ?: "caller"
        sessionId = intent.getStringExtra("sessionId") ?: ""

        if (sessionId.isBlank()) {
            Toast.makeText(this, "Missing call session. Try again.", Toast.LENGTH_LONG).show()
            finish()
            return
        }

        if (hasMediaPermissions()) {
            startWebRtc()
        } else {
            requestPermissions.launch(arrayOf(Manifest.permission.CAMERA, Manifest.permission.RECORD_AUDIO))
        }
    }

    private fun hasMediaPermissions(): Boolean {
        val cam = ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED
        val mic = ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
        return cam && mic
    }

    private fun startWebRtc() {
        try {
            val r = WebRtcRepository(this, scope)
            repo = r
            // For mesh mode, don't create the single legacy PeerConnection; we'll create per-peer PCs later
            if (!useMesh) {
                r.createPeerConnection(this)
                r.attachRemoteRenderer(remoteView)
            } else {
                // Initialize the remote renderer for first remote; additional remotes will add overlays
                remoteView.init(r.eglContext(), null)
            }
            r.startLocalMedia(localView)
            if (!useMesh) r.addLocalTracks()

            // Legacy 1:1 flow kept for reference; use mesh for 3-way
            if (useMesh) startMeshFlow() else if (role == "caller") startAsCaller() else startAsCallee()
        } catch (t: Throwable) {
            Toast.makeText(this, "Failed to start call: ${t.message ?: "unknown error"}", Toast.LENGTH_LONG).show()
            finish()
        }
    }

    private fun startAsCaller() {
        val r = repo ?: return
        scope.launch {
            r.createAndSetOffer(onLocalSdp = { offer: SessionDescription ->
                scope.launch { signaling.setOffer(sessionId, offer.description) }
            })
            signaling.listenSession(sessionId).collectLatest { sess ->
                val answer = sess.answerSdp ?: return@collectLatest
                r.setRemoteAnswer(SessionDescription(SessionDescription.Type.ANSWER, answer))
            }
        }
        scope.launch {
            signaling.listenCandidates(sessionId, fromOtherSide = "caller").collectLatest { dto ->
                r.addIceCandidate(IceCandidate(dto.sdpMid, dto.sdpMLineIndex, dto.candidate))
            }
        }
    }

    private fun startAsCallee() {
        val r = repo ?: return
        scope.launch {
            signaling.listenSession(sessionId).collectLatest { sess ->
                val offer = sess.offerSdp ?: return@collectLatest
                r.setRemoteOffer(SessionDescription(SessionDescription.Type.OFFER, offer)) { answer: SessionDescription ->
                    scope.launch { signaling.setAnswer(sessionId, answer.description) }
                }
            }
        }
        scope.launch {
            signaling.listenCandidates(sessionId, fromOtherSide = "callee").collectLatest { dto ->
                r.addIceCandidate(IceCandidate(dto.sdpMid, dto.sdpMLineIndex, dto.candidate))
            }
        }
    }

    override fun onIceCandidate(candidate: IceCandidate) {
        if (useMesh) return // Per-peer observers handle ICE in mesh mode
        val from = if (role == "caller") "caller" else "callee"
        signaling.addCandidate(sessionId, IceCandidateDTO(candidate.sdpMid, candidate.sdpMLineIndex, candidate.sdp, from))
    }

    override fun onAddTrack(receiver: RtpReceiver?, streams: Array<out MediaStream>?) {
        (receiver?.track() as? VideoTrack)?.addSink(remoteView)
    }

    override fun onAddStream(stream: MediaStream?) {
        stream?.videoTracks?.firstOrNull()?.addSink(remoteView)
    }

    override fun onRemoveStream(stream: MediaStream?) {
        // No-op for now
    }

    override fun onDestroy() {
        super.onDestroy()
        scope.cancel()
        repo?.dispose()
        // Release dynamically created renderers
        extraRenderers.values.forEach { v -> try { v.release() } catch (_: Throwable) {} }
    }

    // Unused/no-op
    override fun onConnectionChange(newState: PeerConnection.PeerConnectionState) {
        android.util.Log.i("PC", "Connection: $newState")
        runOnUiThread {
            Toast.makeText(this, "Connection: $newState", Toast.LENGTH_SHORT).show()
            appendDebugLine("Conn=$newState")
        }
    }
    override fun onIceConnectionChange(newState: PeerConnection.IceConnectionState) {
        android.util.Log.i("ICE", "State: $newState")
        runOnUiThread {
            Toast.makeText(this, "ICE: $newState", Toast.LENGTH_SHORT).show()
            appendDebugLine("ICE=$newState")
        }
    }
    override fun onIceConnectionReceivingChange(p0: Boolean) {
        android.util.Log.d("ICE", "Receiving change: $p0")
    }
    override fun onIceGatheringChange(p0: PeerConnection.IceGatheringState) {
        android.util.Log.d("ICE", "Gathering: $p0")
    }
    override fun onSignalingChange(p0: PeerConnection.SignalingState) {}
    override fun onIceCandidatesRemoved(p0: Array<out IceCandidate>?) {}
    override fun onDataChannel(p0: DataChannel?) {}
    override fun onRenegotiationNeeded() {}
    override fun onStandardizedIceConnectionChange(p0: PeerConnection.IceConnectionState?) {}
    override fun onSelectedCandidatePairChanged(p0: CandidatePairChangeEvent?) {}

    // ----- Mesh (multi-peer) support -----
    private fun startMeshFlow() {
        val user = com.google.firebase.auth.FirebaseAuth.getInstance().currentUser
        selfId = user?.phoneNumber ?: user?.uid ?: run {
            Toast.makeText(this, "Not signed in", Toast.LENGTH_LONG).show(); finish(); return
        }

        scope.launch { signaling.joinSession(sessionId, selfId) }

        // Lifecycle-aware listeners: collect while STARTED, cancel onStop
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                // Participants
                launch {
                    signaling.listenParticipants(sessionId).collectLatest { list ->
                        val others = list.map { it.id }.filter { it.isNotBlank() && it != selfId }
                        others.forEach { remoteId ->
                            if (shouldInitiate(selfId, remoteId) && offersStarted.add(remoteId)) {
                                ensureOfferTo(remoteId)
                            }
                        }
                    }
                }
                // Directed signals to me
                launch {
                    signaling.listenSignals(sessionId, selfId).collectLatest { sig ->
                        val r = repo ?: return@collectLatest
                        when (sig.type) {
                            "offer" -> {
                                val sdp = SessionDescription(SessionDescription.Type.OFFER, sig.sdp ?: return@collectLatest)
                                val renderer = getOrCreateRendererFor(sig.from)
                                r.setRemoteOffer(sig.from, sdp, onAnswerReady = { answer ->
                                    scope.launch { signaling.sendSignal(sessionId, com.example.threevchat.signaling.SignalDTO(
                                        type = "answer", from = selfId, to = sig.from, sdp = answer.description, sdpType = "ANSWER"
                                    )) }
                                }, observer = perPeerObserver(sig.from, renderer))
                            }
                            "answer" -> {
                                val sdp = SessionDescription(SessionDescription.Type.ANSWER, sig.sdp ?: return@collectLatest)
                                r.setRemoteAnswer(sig.from, sdp)
                            }
                            "ice" -> {
                                val c = IceCandidate(sig.sdpMid, sig.sdpMLineIndex ?: 0, sig.candidate ?: return@collectLatest)
                                r.addIceCandidate(sig.from, c)
                            }
                        }
                    }
                }
            }
        }
    }

    private fun ensureOfferTo(remoteId: String) {
        val r = repo ?: return
        val renderer = getOrCreateRendererFor(remoteId)
        scope.launch {
            r.createAndSetOffer(remoteId, observer = perPeerObserver(remoteId, renderer), onLocalSdp = { offer: SessionDescription ->
                scope.launch { signaling.sendSignal(sessionId, com.example.threevchat.signaling.SignalDTO(
                    type = "offer", from = selfId, to = remoteId, sdp = offer.description, sdpType = "OFFER"
                )) }
            })
        }
    }

    private fun shouldInitiate(a: String, b: String): Boolean {
        // Simple order: lower lexicographic id initiates offer to the other
        return a < b
    }

    private fun perPeerObserver(remoteId: String, renderer: SurfaceViewRenderer): PeerConnection.Observer = object : PeerConnection.Observer {
        override fun onIceCandidate(c: IceCandidate) {
            scope.launch {
                signaling.sendSignal(sessionId, com.example.threevchat.signaling.SignalDTO(
                    type = "ice", from = selfId, to = remoteId, sdpMid = c.sdpMid, sdpMLineIndex = c.sdpMLineIndex, candidate = c.sdp
                ))
            }
        }
        override fun onAddTrack(receiver: RtpReceiver?, streams: Array<out MediaStream>?) {
            (receiver?.track() as? VideoTrack)?.addSink(renderer)
        }
        override fun onAddStream(stream: MediaStream?) {
            stream?.videoTracks?.firstOrNull()?.addSink(renderer)
        }
        override fun onRemoveStream(stream: MediaStream?) {
            // No-op for now; renderer will be reused or updated by future tracks
        }
        // Unused in per-peer observer
        override fun onSignalingChange(p0: PeerConnection.SignalingState) {}
        override fun onIceConnectionChange(p0: PeerConnection.IceConnectionState) {}
        override fun onIceConnectionReceivingChange(p0: Boolean) {}
        override fun onIceGatheringChange(p0: PeerConnection.IceGatheringState) {}
        override fun onIceCandidatesRemoved(p0: Array<out IceCandidate>?) {}
        override fun onDataChannel(p0: DataChannel?) {}
        override fun onRenegotiationNeeded() {}
        override fun onConnectionChange(p0: PeerConnection.PeerConnectionState) {}
        override fun onStandardizedIceConnectionChange(p0: PeerConnection.IceConnectionState?) {}
        override fun onSelectedCandidatePairChanged(p0: CandidatePairChangeEvent?) {}
    }

    private fun getOrCreateRendererFor(remoteId: String): SurfaceViewRenderer {
        if (extraRenderers.containsKey(remoteId)) return extraRenderers[remoteId]!!
        // First remote can use the main remoteView if it's free
        if (extraRenderers.isEmpty()) {
            extraRenderers[remoteId] = remoteView
            mainRemoteId = remoteId
            layoutRemotes()
            return remoteView
        }
        val root = findViewById<android.view.ViewGroup>(R.id.root)
        val v = SurfaceViewRenderer(this)
        // Proper init using existing EGL context from repository
        (repo?.eglContext())?.let { ctx -> v.init(ctx, null) }
        v.setZOrderMediaOverlay(true)
        v.setOnClickListener { promoteToMain(remoteId) }
        v.setOnLongClickListener {
            reconnectPeer(remoteId)
            true
        }
        root.addView(v)
        extraRenderers[remoteId] = v
        layoutRemotes()
        return v
    }

    private fun dp(x: Int): Int = (x * resources.displayMetrics.density).toInt()

    private fun layoutRemotes() {
        // Stack small tiles along the right edge, main fills the rest.
        val ids = extraRenderers.keys.toList()
        val root = findViewById<android.view.ViewGroup>(R.id.root)
        fun setParams(v: android.view.View, w: Int, h: Int, gravity: Int, marginEndDp: Int = 12, bottomDp: Int = 12, topDp: Int = 0) {
            val lp = android.widget.FrameLayout.LayoutParams(w, h)
            lp.gravity = gravity
            lp.marginEnd = dp(marginEndDp)
            lp.bottomMargin = dp(bottomDp)
            lp.topMargin = dp(topDp)
            v.layoutParams = lp
        }
        val sideIds = ids.toMutableList()
        // Compute main first
        val mainId = mainRemoteId ?: ids.firstOrNull()
        if (mainId != null) {
            extraRenderers[mainId]?.let { v ->
                setParams(
                    v,
                    android.view.ViewGroup.LayoutParams.MATCH_PARENT,
                    android.view.ViewGroup.LayoutParams.MATCH_PARENT,
                    android.view.Gravity.FILL,
                    marginEndDp = 0, bottomDp = 0, topDp = 0
                )
            }
            // Do not include main in side tiles
            sideIds.remove(mainId)
        }
        // Side tiles as a diagonal cascade with adaptive size (distinct from sidebar grids)
        val sideCount = sideIds.size
        val (tileWdp, tileHdp) = computeTileSizeDp(sideCount)
        var stackIndex = 0
        sideIds.forEach { id ->
            val v = extraRenderers[id] ?: return@forEach
            val stepX = (tileWdp * 0.35f).toInt()
            val stepY = (tileHdp * 0.65f).toInt()
            val marginEnd = sideMarginDp + stackIndex * stepX
            val bottom = sideMarginDp + stackIndex * stepY
            setParams(v, dp(tileWdp), dp(tileHdp), android.view.Gravity.END or android.view.Gravity.BOTTOM, marginEndDp = marginEnd, bottomDp = bottom)
            v.bringToFront()
            stackIndex++
        }
        root.requestLayout()
    }

    private fun computeTileSizeDp(sideCount: Int): Pair<Int, Int> {
        if (sideCount <= 0) return Pair(0, 0)
        val dm = resources.displayMetrics
        val screenHdp = (dm.heightPixels / dm.density).toInt()
        // Reserve space for controls area (~120dp) and top margins
        val usableHdp = (screenHdp - 120 - sideMarginDp * 2).coerceAtLeast(tileMinHeightDp)
        val totalGaps = (sideCount - 1) * gapDp
        val perH = ((usableHdp - totalGaps) / sideCount).coerceIn(tileMinHeightDp, tileMaxHeightDp)
        val perW = (perH * 0.64f).toInt().coerceAtLeast(100)
        return Pair(perW, perH)
    }

    // Outline removed intentionally to avoid a Zoom-like look

    private fun reconnectPeer(remoteId: String) {
        val r = repo ?: return
        val renderer = getOrCreateRendererFor(remoteId)
        r.restartIceFor(remoteId, perPeerObserver(remoteId, renderer)) { offer ->
            scope.launch {
                signaling.sendSignal(sessionId, com.example.threevchat.signaling.SignalDTO(
                    type = "offer", from = selfId, to = remoteId, sdp = offer.description, sdpType = "OFFER"
                ))
            }
        }
        Toast.makeText(this, "Reconnecting $remoteId...", Toast.LENGTH_SHORT).show()
    }

    private fun promoteToMain(remoteId: String) {
        if (mainRemoteId == remoteId) return
        // Swap mapping so selected becomes main.
        mainRemoteId = remoteId
        layoutRemotes()
    }

    private fun reconnectAll() {
        val r = repo ?: return
        if (useMesh) {
            r.restartIceForAll(observerProvider = { id -> perPeerObserver(id, getOrCreateRendererFor(id)) }) { id, sdp ->
                scope.launch {
                    signaling.sendSignal(sessionId, com.example.threevchat.signaling.SignalDTO(
                        type = "offer", from = selfId, to = id, sdp = sdp.description, sdpType = "OFFER"
                    ))
                }
            }
        } else {
            scope.launch {
                try {
                    r.createAndSetOffer(onLocalSdp = { offer: SessionDescription ->
                        scope.launch { signaling.setOffer(sessionId, offer.description) }
                    }, iceRestart = true)
                } catch (_: Throwable) {}
            }
        }
        Toast.makeText(this, "Reconnecting...", Toast.LENGTH_SHORT).show()
    }

    private fun showSettingsDialog() {
        val r = repo ?: return
        val items = arrayOf(
            if (micOn) "Mute microphone" else "Unmute microphone",
            if (camOn) "Turn camera off" else "Turn camera on",
            if (speakerOn) "Speaker off" else "Speaker on",
            "Participants",
            if (debugVisible) "Hide debug" else "Show debug"
        )
        androidx.appcompat.app.AlertDialog.Builder(this)
            .setTitle("Call settings")
            .setItems(items) { _, which ->
                when (which) {
                    0 -> { micOn = !micOn; r.setMicEnabled(micOn) }
                    1 -> { camOn = !camOn; r.setVideoEnabled(camOn) }
                    2 -> toggleSpeaker()
                    3 -> showParticipantsDialog()
                    4 -> toggleDebug()
                }
            }
            .setNegativeButton(android.R.string.cancel, null)
            .setNeutralButton("Switch camera") { _, _ -> r.switchCamera() }
            .show()
    }

    private fun toggleSpeaker() {
        val am = getSystemService(android.content.Context.AUDIO_SERVICE) as android.media.AudioManager
        speakerOn = !speakerOn
        am.isSpeakerphoneOn = speakerOn
        android.widget.Toast.makeText(this, if (speakerOn) "Speaker ON" else "Speaker OFF", android.widget.Toast.LENGTH_SHORT).show()
    }

    private fun showParticipantsDialog() {
        scope.launch {
            // Take a single snapshot of participants
            val participants = kotlinx.coroutines.withContext(Dispatchers.IO) {
                var latest: List<com.example.threevchat.signaling.Participant> = emptyList()
                val latch = java.util.concurrent.CountDownLatch(1)
                val reg = signaling.listenParticipants(sessionId)
                val job = launch {
                    reg.collectLatest { list ->
                        latest = list
                        latch.countDown()
                        cancel()
                    }
                }
                latch.await()
                latest
            }
            val items = participants.map { it.id + if (it.active) " (active)" else " (inactive)" }.toTypedArray()
            androidx.appcompat.app.AlertDialog.Builder(this@CallActivity)
                .setTitle("Participants")
                .setItems(items) { _, which ->
                    val p = participants.getOrNull(which) ?: return@setItems
                    if (p.id == selfId) return@setItems
                    androidx.appcompat.app.AlertDialog.Builder(this@CallActivity)
                        .setMessage("Remove ${p.id} from call?")
                        .setPositiveButton("Remove") { _, _ ->
                            scope.launch { try { signaling.leaveSession(sessionId, p.id) } catch (_: Throwable) {} }
                        }
                        .setNegativeButton(android.R.string.cancel, null)
                        .show()
                }
                .setNegativeButton(android.R.string.cancel, null)
                .show()
        }
    }

    // ----- Add Person helpers -----
    private fun showAddPersonDialog() {
        val options = arrayOf("Invite in-app user", "Invite via SMS")
        androidx.appcompat.app.AlertDialog.Builder(this)
            .setTitle("Add person")
            .setItems(options) { dlg, which ->
                when (which) {
                    0 -> promptInAppInvite()
                    1 -> promptSmsInvite()
                }
            }
            .setNegativeButton(android.R.string.cancel, null)
            .show()
    }

    private fun promptInAppInvite() {
        val input = android.widget.EditText(this).apply {
            hint = "Enter user's phone (+15551234567) or UID"
            setSingleLine(true)
        }
        androidx.appcompat.app.AlertDialog.Builder(this)
            .setTitle("Invite in-app user")
            .setView(input)
            .setPositiveButton("Invite") { _, _ ->
                val callee = input.text?.toString()?.trim().orEmpty()
                if (callee.isNotEmpty()) inviteInApp(callee) else android.widget.Toast.makeText(this, "Enter a phone or UID", android.widget.Toast.LENGTH_SHORT).show()
            }
            .setNegativeButton(android.R.string.cancel, null)
            .show()
    }

    private fun promptSmsInvite() {
        val input = android.widget.EditText(this).apply {
            hint = "Optional phone number"
            setSingleLine(true)
        }
        androidx.appcompat.app.AlertDialog.Builder(this)
            .setTitle("Invite via SMS")
            .setView(input)
            .setPositiveButton("Send") { _, _ ->
                val phone = input.text?.toString()?.trim().takeIf { !it.isNullOrBlank() }
                inviteViaSms(phone)
            }
            .setNegativeButton(android.R.string.cancel, null)
            .show()
    }

    private fun currentUserIdOrPhone(): String {
        val user = FirebaseAuth.getInstance().currentUser
        return user?.phoneNumber ?: user?.uid ?: ""
    }

    private fun inviteInApp(callee: String) {
        val caller = currentUserIdOrPhone()
        if (caller.isBlank()) {
            android.widget.Toast.makeText(this, "Not signed in", android.widget.Toast.LENGTH_LONG).show()
            return
        }
        // Add the callee as a participant to the current session; their app listens for invites and will join
        scope.launch {
            try {
                signaling.joinSession(sessionId, callee)
                withContext(Dispatchers.Main) {
                    android.widget.Toast.makeText(this@CallActivity, "Invited $callee to current call", android.widget.Toast.LENGTH_SHORT).show()
                }
            } catch (t: Throwable) {
                withContext(Dispatchers.Main) {
                    android.widget.Toast.makeText(this@CallActivity, "Failed to invite: ${t.message}", android.widget.Toast.LENGTH_LONG).show()
                }
            }
        }
    }

    private fun inviteViaSms(phone: String?) {
        // Reuse current sessionId if available; otherwise create one with empty callee
        var id = sessionId
        if (id.isBlank()) {
            val caller = currentUserIdOrPhone()
            id = signaling.createSession(caller = caller, callee = phone ?: "")
        }
        val body = "Join my call: p2pvideo://call/$id"
        val uri = if (!phone.isNullOrBlank()) android.net.Uri.parse("smsto:$phone") else android.net.Uri.parse("smsto:")
        val intent = android.content.Intent(android.content.Intent.ACTION_SENDTO, uri).apply {
            putExtra("sms_body", body)
        }
        startActivity(intent)
    }

    private fun toggleDebug() {
        debugVisible = !debugVisible
        debugText?.visibility = if (debugVisible) android.view.View.VISIBLE else android.view.View.GONE
    }
    private fun appendDebugLine(line: String) {
        if (!debugVisible) return
        val tv = debugText ?: return
        val now = java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.US).format(java.util.Date())
        val newText = (tv.text?.toString() ?: "")
            .split('\n')
            .takeLast(9) // keep recent ~9 lines
            .plus("[$now] $line")
            .joinToString("\n")
        tv.text = newText
    }

    override fun onStop() {
        super.onStop()
        // Explicitly remove any Firestore listener registrations we created outside Flows
        listenerRegs.forEach { runCatching { it.remove() } }
        listenerRegs.clear()
    }
}
 
