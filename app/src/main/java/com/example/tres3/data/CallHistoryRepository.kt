package com.example.tres3.data

import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.Query
import kotlinx.coroutines.tasks.await

class CallHistoryRepository {
    private val firestore = FirebaseFirestore.getInstance()
    private val auth = FirebaseAuth.getInstance()

    suspend fun saveCallHistory(callHistory: CallHistory) {
        val currentUser = auth.currentUser ?: return

        try {
            firestore.collection("users")
                .document(currentUser.uid)
                .collection("callHistory")
                .add(callHistory)
                .await()
        } catch (e: Exception) {
            // Handle error
            e.printStackTrace()
        }
    }

    fun getCallHistory(callback: (List<CallHistory>) -> Unit) {
        val currentUser = auth.currentUser ?: return

        firestore.collection("users")
            .document(currentUser.uid)
            .collection("callHistory")
            .orderBy("timestamp", Query.Direction.DESCENDING)
            .addSnapshotListener { snapshot, e ->
                if (e != null) {
                    callback(emptyList())
                    return@addSnapshotListener
                }

                val callHistory = snapshot?.documents?.mapNotNull { doc ->
                    doc.toObject(CallHistory::class.java)?.copy(id = doc.id)
                } ?: emptyList()

                callback(callHistory)
            }
    }
}