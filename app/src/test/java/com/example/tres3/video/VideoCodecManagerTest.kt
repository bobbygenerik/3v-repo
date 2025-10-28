package com.example.tres3.video

import org.junit.Test
import org.junit.Assert.*

/**
 * Unit tests for VideoCodecManager
 * 
 * These tests validate the codec enumeration and string conversion logic
 * Device-specific codec detection cannot be tested in unit tests (requires Android runtime)
 */
class VideoCodecManagerTest {
    
    @Test
    fun testCodecEnumValues() {
        // Verify all expected codecs are defined
        val codecs = VideoCodecManager.PreferredCodec.values()
        assertEquals(4, codecs.size)
        
        // Verify codec names
        assertTrue(codecs.any { it.name == "H264" })
        assertTrue(codecs.any { it.name == "H265_HEVC" })
        assertTrue(codecs.any { it.name == "VP9" })
        assertTrue(codecs.any { it.name == "VP8" })
    }
    
    @Test
    fun testCodecDisplayNames() {
        // Verify display names are human-readable
        assertEquals("H.264 (AVC)", VideoCodecManager.PreferredCodec.H264.displayName)
        assertEquals("H.265 (HEVC)", VideoCodecManager.PreferredCodec.H265_HEVC.displayName)
        assertEquals("VP9", VideoCodecManager.PreferredCodec.VP9.displayName)
        assertEquals("VP8", VideoCodecManager.PreferredCodec.VP8.displayName)
    }
    
    @Test
    fun testCodecMimeTypes() {
        // Verify MIME types are correct for Android MediaCodec
        assertEquals("video/avc", VideoCodecManager.PreferredCodec.H264.mimeType)
        assertEquals("video/hevc", VideoCodecManager.PreferredCodec.H265_HEVC.mimeType)
        assertEquals("video/x-vnd.on2.vp9", VideoCodecManager.PreferredCodec.VP9.mimeType)
        assertEquals("video/x-vnd.on2.vp8", VideoCodecManager.PreferredCodec.VP8.mimeType)
    }
    
    @Test
    fun testCodecFromString() {
        // Test valid codec names
        assertEquals(
            VideoCodecManager.PreferredCodec.H264,
            VideoCodecManager.PreferredCodec.fromString("H264")
        )
        assertEquals(
            VideoCodecManager.PreferredCodec.H265_HEVC,
            VideoCodecManager.PreferredCodec.fromString("H265_HEVC")
        )
        assertEquals(
            VideoCodecManager.PreferredCodec.VP9,
            VideoCodecManager.PreferredCodec.fromString("VP9")
        )
        
        // Test case insensitivity
        assertEquals(
            VideoCodecManager.PreferredCodec.H264,
            VideoCodecManager.PreferredCodec.fromString("h264")
        )
        assertEquals(
            VideoCodecManager.PreferredCodec.VP9,
            VideoCodecManager.PreferredCodec.fromString("vp9")
        )
    }
    
    @Test
    fun testCodecFromString_InvalidInput() {
        // Invalid input should default to H.264
        assertEquals(
            VideoCodecManager.PreferredCodec.H264,
            VideoCodecManager.PreferredCodec.fromString("invalid")
        )
        assertEquals(
            VideoCodecManager.PreferredCodec.H264,
            VideoCodecManager.PreferredCodec.fromString("")
        )
    }
    
    @Test
    fun testCodecInfoStructure() {
        // Verify CodecInfo data class can be instantiated
        val codecInfo = VideoCodecManager.CodecInfo(
            codec = VideoCodecManager.PreferredCodec.H264,
            isSupported = true,
            hasHardwareEncoder = true,
            hasSoftwareEncoder = true,
            encoderName = "test.encoder",
            supportedResolutions = listOf(
                VideoCodecManager.Resolution(1280, 720),
                VideoCodecManager.Resolution(640, 360)
            ),
            recommendedBitrate = 1500
        )
        
        assertEquals(VideoCodecManager.PreferredCodec.H264, codecInfo.codec)
        assertTrue(codecInfo.isSupported)
        assertTrue(codecInfo.hasHardwareEncoder)
        assertEquals("test.encoder", codecInfo.encoderName)
        assertEquals(2, codecInfo.supportedResolutions.size)
        assertEquals(1500, codecInfo.recommendedBitrate)
    }
    
    @Test
    fun testResolutionToString() {
        val resolution = VideoCodecManager.Resolution(1920, 1080)
        assertEquals("1920x1080", resolution.toString())
        
        val resolution2 = VideoCodecManager.Resolution(640, 480)
        assertEquals("640x480", resolution2.toString())
    }
    
    @Test
    fun testBestCodecLogic() {
        // Test that getBestCodec returns H.264 when preferQuality=false
        val compatCodec = VideoCodecManager.getBestCodec(preferQuality = false)
        assertEquals(VideoCodecManager.PreferredCodec.H264, compatCodec)
        
        // When preferQuality=true, it attempts H.265 or VP9 but may fall back to H.264
        // depending on device support (which we can't test in unit tests)
        val qualityCodec = VideoCodecManager.getBestCodec(preferQuality = true)
        assertNotNull(qualityCodec)
        // Should be one of the supported codecs
        assertTrue(
            qualityCodec in VideoCodecManager.PreferredCodec.values()
        )
    }
}
