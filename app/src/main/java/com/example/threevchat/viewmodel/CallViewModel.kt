package com.example.threevchat.viewmodel

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import org.webrtc.*

data class CallState(
    val isConnected: Boolean = false,
    val isMicMuted: Boolean = false,
    val isCameraOn: Boolean = true,
    val isFrontCamera: Boolean = true,
    val participants: List<String> = emptyList()
)

class CallViewModel : ViewModel() {
    
    private val _callState = MutableStateFlow(CallState())
    val callState: StateFlow<CallState> = _callState
    
    // WebRTC components
    private var peerConnectionFactory: PeerConnectionFactory? = null
    private var peerConnection: PeerConnection? = null
    private var localAudioTrack: AudioTrack? = null
    private var localVideoTrack: VideoTrack? = null
    private var videoCapturer: CameraVideoCapturer? = null
    
    fun initializeWebRTC(context: Context, eglBase: EglBase) {
        // Initialize PeerConnectionFactory
        val options = PeerConnectionFactory.InitializationOptions.builder(context)
            .setEnableInternalTracer(true)
            .createInitializationOptions()
        PeerConnectionFactory.initialize(options)
        
        peerConnectionFactory = PeerConnectionFactory.builder()
            .setVideoEncoderFactory(DefaultVideoEncoderFactory(
                eglBase.eglBaseContext, 
                true, 
                true
            ))
            .setVideoDecoderFactory(DefaultVideoDecoderFactory(eglBase.eglBaseContext))
            .createPeerConnectionFactory()
        
        // Create local media tracks
        createLocalMediaTracks(context, eglBase)
    }
    
    private fun createLocalMediaTracks(context: Context, eglBase: EglBase) {
        // Audio track
        val audioConstraints = MediaConstraints()
        val audioSource = peerConnectionFactory?.createAudioSource(audioConstraints)
        localAudioTrack = peerConnectionFactory?.createAudioTrack("local_audio", audioSource)
        
        // Video track
        val videoSource = peerConnectionFactory?.createVideoSource(false)
        localVideoTrack = peerConnectionFactory?.createVideoTrack("local_video", videoSource)
        
        // Camera capturer
        val enumerator = Camera2Enumerator(context)
        val deviceNames = enumerator.deviceNames
        
        val frontCameraName = deviceNames.firstOrNull { enumerator.isFrontFacing(it) }
        
        videoCapturer = frontCameraName?.let {
            enumerator.createCapturer(it, null)
        }
        
        // Start capturing
        videoCapturer?.initialize(
            SurfaceTextureHelper.create("CaptureThread", eglBase.eglBaseContext),
            context,
            videoSource?.capturerObserver
        )
        
        videoCapturer?.startCapture(1280, 720, 30)
    }
    
    fun toggleMicrophone() {
        viewModelScope.launch {
            val newMutedState = !_callState.value.isMicMuted
            localAudioTrack?.setEnabled(!newMutedState)
            _callState.value = _callState.value.copy(isMicMuted = newMutedState)
        }
    }
    
    fun switchCamera() {
        viewModelScope.launch {
            videoCapturer?.switchCamera(object : CameraVideoCapturer.CameraSwitchHandler {
                override fun onCameraSwitchDone(isFrontCamera: Boolean) {
                    _callState.value = _callState.value.copy(isFrontCamera = isFrontCamera)
                }
                
                override fun onCameraSwitchError(errorDescription: String?) {
                    // Handle error - maybe show a toast
                }
            })
        }
    }
    
    fun toggleCamera() {
        viewModelScope.launch {
            val newCameraState = !_callState.value.isCameraOn
            localVideoTrack?.setEnabled(newCameraState)
            _callState.value = _callState.value.copy(isCameraOn = newCameraState)
        }
    }
    
    fun endCall() {
        viewModelScope.launch {
            // Stop capturing
            try {
                videoCapturer?.stopCapture()
                videoCapturer?.dispose()
            } catch (e: InterruptedException) {
                e.printStackTrace()
            }
            
            // Dispose tracks
            localVideoTrack?.dispose()
            localAudioTrack?.dispose()
            
            // Close peer connection
            peerConnection?.close()
            peerConnection?.dispose()
            
            // Dispose factory
            peerConnectionFactory?.dispose()
        }
    }
    
    fun addLocalVideoRenderer(renderer: SurfaceViewRenderer) {
        localVideoTrack?.addSink(renderer)
    }
    
    fun removeLocalVideoRenderer(renderer: SurfaceViewRenderer) {
        localVideoTrack?.removeSink(renderer)
    }
    
    fun addParticipant(participantId: String) {
        viewModelScope.launch {
            val currentParticipants = _callState.value.participants.toMutableList()
            currentParticipants.add(participantId)
            _callState.value = _callState.value.copy(participants = currentParticipants)
            
            // Here you would:
            // 1. Create a new peer connection for the participant
            // 2. Send an offer/invitation through your signaling server
            // 3. Handle the WebRTC negotiation
        }
    }
    
    override fun onCleared() {
        super.onCleared()
        endCall()
    }
}