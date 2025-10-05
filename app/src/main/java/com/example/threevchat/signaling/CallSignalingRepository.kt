package com.example.threevchat.signaling

import com.google.firebase.firestore.DocumentReference
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.ListenerRegistration
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
                    dc.document.toObject(IceCandidateDTO::class.java).also { trySend(it).isSuccess }
                }
            }
        awaitClose { reg?.remove() }
    }

    suspend fun end(id: String) {
        sessionRef(id).update("status", "ended")
    }
}
