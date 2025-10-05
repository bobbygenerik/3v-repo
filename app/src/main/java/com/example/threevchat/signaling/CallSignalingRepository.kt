package com.example.threevchat.signaling

import com.google.firebase.firestore.DocumentReference
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.ListenerRegistration
import com.google.firebase.firestore.Query
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import java.util.UUID

class CallSignalingRepository(
    private val db: FirebaseFirestore = FirebaseFirestore.getInstance()
) {
    fun createSession(caller: String, callee: String): String {
        val id = UUID.randomUUID().toString()
        val doc = db.collection("calls").document(id)
        val session = CallSession(id = id, caller = caller, callee = callee, status = "ringing")
        doc.set(session)
        return id
    }

    fun sessionRef(id: String): DocumentReference = db.collection("calls").document(id)

    suspend fun setOffer(id: String, sdp: String) {
        sessionRef(id).update(mapOf("offerSdp" to sdp, "status" to "ringing"))
    }

    suspend fun setAnswer(id: String, sdp: String) {
        sessionRef(id).update(mapOf("answerSdp" to sdp, "status" to "connected"))
    }

    fun listenSession(id: String): Flow<CallSession> = callbackFlow {
        val reg = sessionRef(id).addSnapshotListener { snap, _ ->
            snap?.toObject(CallSession::class.java)?.let { trySend(it).isSuccess }
        }
        awaitClose { reg.remove() }
    }

    fun addCandidate(id: String, dto: IceCandidateDTO) {
        sessionRef(id).collection("candidates").add(dto)
    }

    fun listenCandidates(id: String, fromOtherSide: String): Flow<IceCandidateDTO> = callbackFlow {
        var reg: ListenerRegistration? = null
        reg = sessionRef(id).collection("candidates")
            .whereNotEqualTo("from", fromOtherSide)
            .addSnapshotListener { qs, _ ->
                qs?.documentChanges?.forEach { dc ->
                    if (dc.type == com.google.firebase.firestore.DocumentChange.Type.ADDED) {
                        dc.document.toObject(IceCandidateDTO::class.java).also { trySend(it).isSuccess }
                    }
                }
            }
        awaitClose { reg?.remove() }
    }

    suspend fun end(id: String) {
        sessionRef(id).update("status", "ended")
    }

    fun listenIncoming(calleePhone: String?, calleeUid: String?): Flow<CallSession> = callbackFlow {
        val seen = mutableSetOf<String>()
        val regs = mutableListOf<ListenerRegistration>()
        fun listenFor(value: String) {
            val reg = db.collection("calls")
                .whereEqualTo("callee", value)
                .whereEqualTo("status", "ringing")
                .addSnapshotListener { qs, _ ->
                    qs?.documentChanges?.forEach { dc ->
                        if (dc.type == com.google.firebase.firestore.DocumentChange.Type.ADDED) {
                            val session = dc.document.toObject(CallSession::class.java)
                            if (seen.add(session.id)) {
                                trySend(session).isSuccess
                            }
                        }
                    }
                }
            regs += reg
        }
        if (!calleePhone.isNullOrBlank()) listenFor(calleePhone)
        if (!calleeUid.isNullOrBlank() && calleeUid != calleePhone) listenFor(calleeUid)
        awaitClose { regs.forEach { it.remove() } }
    }

    // -------- Multi-party signaling (mesh) --------
    fun participantsRef(id: String) = sessionRef(id).collection("participants")
    fun signalsRef(id: String) = sessionRef(id).collection("signals")

    suspend fun joinSession(id: String, userId: String) {
        participantsRef(id).document(userId).set(Participant(id = userId, active = true))
    }
    suspend fun leaveSession(id: String, userId: String) {
        participantsRef(id).document(userId).update("active", false)
    }
    fun listenParticipants(id: String): Flow<List<Participant>> = callbackFlow {
        val reg = participantsRef(id).addSnapshotListener { qs, _ ->
            val list = qs?.documents?.mapNotNull { it.toObject(Participant::class.java) } ?: emptyList()
            trySend(list).isSuccess
        }
        awaitClose { reg.remove() }
    }
    fun listenIncomingParticipantInvites(userId: String): Flow<String> = callbackFlow {
        // Listen across all calls for participant docs addressed to userId
        val reg = db.collectionGroup("participants")
            .whereEqualTo("id", userId)
            .whereEqualTo("active", true)
            .addSnapshotListener { qs, _ ->
                qs?.documentChanges?.forEach { dc ->
                    if (dc.type == com.google.firebase.firestore.DocumentChange.Type.ADDED) {
                        val sessionRef = dc.document.reference.parent.parent
                        val sid = sessionRef?.id
                        if (!sid.isNullOrBlank()) trySend(sid).isSuccess
                    }
                }
            }
        awaitClose { reg.remove() }
    }
    suspend fun sendSignal(id: String, signal: SignalDTO) {
        signalsRef(id).add(signal)
    }
    fun listenSignals(id: String, toUser: String): Flow<SignalDTO> = callbackFlow {
        val reg = signalsRef(id)
            .whereEqualTo("to", toUser)
            .addSnapshotListener { qs, _ ->
                qs?.documentChanges?.forEach { dc ->
                    if (dc.type == com.google.firebase.firestore.DocumentChange.Type.ADDED) {
                        dc.document.toObject(SignalDTO::class.java).also { trySend(it).isSuccess }
                    }
                }
            }
        awaitClose { reg.remove() }
    }
}
