package com.hypr.hyprar_engine

import android.annotation.SuppressLint
import android.app.Activity
import android.content.ContentValues
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import android.os.Build
import android.provider.MediaStore
import android.view.Surface
import androidx.annotation.NonNull
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.video.MediaStoreOutputOptions
import androidx.camera.video.Quality
import androidx.camera.video.QualitySelector
import androidx.camera.video.Recorder
import androidx.camera.video.Recording
import androidx.camera.video.VideoCapture
import androidx.camera.video.VideoRecordEvent
import androidx.core.content.ContextCompat
import androidx.core.util.Consumer
import androidx.lifecycle.LifecycleOwner
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetectorOptions
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.view.TextureRegistry
import java.io.File
import java.util.concurrent.Executors

class HyprarEnginePlugin: FlutterPlugin, MethodCallHandler, ActivityAware, EventChannel.StreamHandler {
    private lateinit var channel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private lateinit var textureRegistry: TextureRegistry
    private var activity: Activity? = null
    private var eventSink: EventChannel.EventSink? = null

    // ── Executors reutilizables ────────────────────────────────────────
    private val analysisExecutor  = Executors.newSingleThreadExecutor()
    private val recordingExecutor = Executors.newSingleThreadExecutor()

    // ── Video recording (CameraX — para audio) ────────────────────────
    private var videoCapture: VideoCapture<Recorder>? = null
    private var activeRecording: Recording? = null
    private var stopRecordingResult: Result? = null

    private val faceDetector = FaceDetection.getClient(
        FaceDetectorOptions.Builder()
            .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
            .setLandmarkMode(FaceDetectorOptions.LANDMARK_MODE_ALL)
            .setClassificationMode(FaceDetectorOptions.CLASSIFICATION_MODE_NONE)
            .build()
    )

    override fun onAttachedToEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "hyprar_engine")
        channel.setMethodCallHandler(this)
        eventChannel = EventChannel(binding.binaryMessenger, "hyprar_engine/faces")
        eventChannel.setStreamHandler(this)
        textureRegistry = binding.textureRegistry
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        when (call.method) {
            "initializeCamera"   -> iniciarCamaraNativa(result)
            "startRecording"     -> startRecording(result)
            "stopRecording"      -> stopRecording(result)
            "encodeVideoFrames"  -> encodeVideoFrames(call, result)
            else                 -> result.notImplemented()
        }
    }

    @SuppressLint("UnsafeOptInUsageError")
    private fun iniciarCamaraNativa(result: Result) {
        if (activity == null) return result.error("SIN_ACTIVIDAD", "No activity", null)

        val cameraProviderFuture = ProcessCameraProvider.getInstance(activity!!)

        cameraProviderFuture.addListener({
            val cameraProvider = cameraProviderFuture.get()
            val textureEntry = textureRegistry.createSurfaceTexture()
            val surfaceTexture = textureEntry.surfaceTexture()

            val preview = Preview.Builder().build()
            preview.setSurfaceProvider { request ->
                val resolution = request.resolution
                surfaceTexture.setDefaultBufferSize(resolution.width, resolution.height)
                val surface = Surface(surfaceTexture)
                request.provideSurface(surface, ContextCompat.getMainExecutor(activity!!)) {
                    surface.release()
                }
            }

            val imageAnalyzer = ImageAnalysis.Builder()
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .build()

            imageAnalyzer.setAnalyzer(analysisExecutor) { imageProxy ->
                val mediaImage = imageProxy.image
                if (mediaImage != null) {
                    val image = InputImage.fromMediaImage(mediaImage, imageProxy.imageInfo.rotationDegrees)
                    faceDetector.process(image)
                        .addOnSuccessListener { faces ->
                            if (faces.isNotEmpty()) {
                                val face = faces[0]
                                val bounds = face.boundingBox
                                val leftEye  = face.getLandmark(com.google.mlkit.vision.face.FaceLandmark.LEFT_EYE)?.position
                                val rightEye = face.getLandmark(com.google.mlkit.vision.face.FaceLandmark.RIGHT_EYE)?.position
                                val nose     = face.getLandmark(com.google.mlkit.vision.face.FaceLandmark.NOSE_BASE)?.position
                                val faceData = mapOf(
                                    "x"          to bounds.left.toDouble(),
                                    "y"          to bounds.top.toDouble(),
                                    "width"      to bounds.width().toDouble(),
                                    "height"     to bounds.height().toDouble(),
                                    "imgWidth"   to image.width.toDouble(),
                                    "imgHeight"  to image.height.toDouble(),
                                    "leftEyeX"   to (leftEye?.x  ?: 0f).toDouble(),
                                    "leftEyeY"   to (leftEye?.y  ?: 0f).toDouble(),
                                    "rightEyeX"  to (rightEye?.x ?: 0f).toDouble(),
                                    "rightEyeY"  to (rightEye?.y ?: 0f).toDouble(),
                                    "noseX"      to (nose?.x     ?: 0f).toDouble(),
                                    "noseY"      to (nose?.y     ?: 0f).toDouble(),
                                    "angleZ"     to face.headEulerAngleZ.toDouble()
                                )
                                activity?.runOnUiThread { eventSink?.success(faceData) }
                            } else {
                                activity?.runOnUiThread { eventSink?.success(null) }
                            }
                        }
                        .addOnCompleteListener { imageProxy.close() }
                } else {
                    imageProxy.close()
                }
            }

            val recorder = Recorder.Builder()
                .setQualitySelector(QualitySelector.from(Quality.HD))
                .build()
            videoCapture = VideoCapture.withOutput(recorder)

            val cameraSelector = CameraSelector.DEFAULT_FRONT_CAMERA

            try {
                cameraProvider.unbindAll()
                cameraProvider.bindToLifecycle(
                    activity as LifecycleOwner,
                    cameraSelector,
                    preview,
                    imageAnalyzer,
                    videoCapture!!
                )
                result.success(textureEntry.id())
            } catch (exc: Exception) {
                result.error("ERROR", exc.message, null)
            }

        }, ContextCompat.getMainExecutor(activity!!))
    }

    @SuppressLint("MissingPermission")
    private fun startRecording(result: Result) {
        val ctx = activity ?: return result.error("SIN_ACTIVIDAD", "No activity", null)
        val vc  = videoCapture ?: return result.error("NO_CAMERA", "Camera not initialized", null)

        val contentValues = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, "HYPR_VIDEO_${System.currentTimeMillis()}")
            put(MediaStore.MediaColumns.MIME_TYPE, "video/mp4")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.Video.Media.RELATIVE_PATH, "Movies/HYPR AR")
            }
        }

        val mediaStoreOutput = MediaStoreOutputOptions.Builder(
            ctx.contentResolver,
            MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        ).setContentValues(contentValues).build()

        val recordingListener = Consumer<VideoRecordEvent> { event ->
            if (event is VideoRecordEvent.Finalize) {
                val pending = stopRecordingResult
                stopRecordingResult = null
                activity?.runOnUiThread {
                    if (event.hasError()) {
                        pending?.error("RECORDING_ERROR", event.cause?.message, null)
                    } else {
                        pending?.success(event.outputResults.outputUri.toString())
                    }
                }
            }
        }

        recordingExecutor.execute {
            try {
                val recording = vc.output
                    .prepareRecording(ctx, mediaStoreOutput)
                    .withAudioEnabled()
                    .start(recordingExecutor, recordingListener)
                activity?.runOnUiThread {
                    activeRecording = recording
                    result.success(true)
                }
            } catch (e: Exception) {
                activity?.runOnUiThread {
                    result.error("RECORDING_START_ERROR", e.message, null)
                }
            }
        }
    }

    private fun stopRecording(result: Result) {
        val recording = activeRecording
        if (recording == null) {
            result.success(null)
            return
        }
        stopRecordingResult = result
        activeRecording = null
        recordingExecutor.execute {
            try {
                recording.mute(true)
                Thread.sleep(80)
                recording.stop()
            } catch (e: Exception) {
                activity?.runOnUiThread {
                    stopRecordingResult = null
                    result.error("RECORDING_STOP_ERROR", e.message, null)
                }
            }
        }
    }

    // ── encodeVideoFrames: toma PNGs de tempDir y los codifica como MP4 ──
    private fun encodeVideoFrames(call: MethodCall, result: Result) {
        val tempDir    = call.argument<String>("tempDir")  ?: return result.error("NO_DIR", "No tempDir", null)
        val fps        = call.argument<Int>("fps")         ?: 15
        val reqWidth   = call.argument<Int>("width")       ?: 0
        val reqHeight  = call.argument<Int>("height")      ?: 0
        val tsRaw      = call.argument<List<*>>("timestamps")
        val timestamps = tsRaw?.map { (it as Number).toLong() } ?: emptyList()
        val ctx        = activity ?: return result.error("NO_ACTIVITY", "No activity", null)

        recordingExecutor.execute {
            try {
                val dir = File(tempDir)
                val frameFiles = dir.listFiles { f -> f.name.endsWith(".png") }
                    ?.sortedBy { it.name }
                    ?: emptyList()

                if (frameFiles.isEmpty()) {
                    dir.deleteRecursively()
                    activity?.runOnUiThread { result.success(null) }
                    return@execute
                }

                // Dimensiones: usa las del primer frame si no se indicaron
                val firstBmp = BitmapFactory.decodeFile(frameFiles[0].absolutePath)
                val rawW = if (reqWidth  > 0) reqWidth  else firstBmp.width
                val rawH = if (reqHeight > 0) reqHeight else firstBmp.height
                firstBmp.recycle()
                // MediaCodec requiere dimensiones pares
                val videoW = rawW and -2
                val videoH = rawH and -2

                // Configura el encoder H.264
                val mime   = MediaFormat.MIMETYPE_VIDEO_AVC
                val format = MediaFormat.createVideoFormat(mime, videoW, videoH).apply {
                    setInteger(MediaFormat.KEY_BIT_RATE, 6_000_000)
                    setInteger(MediaFormat.KEY_FRAME_RATE, fps)
                    setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
                    setInteger(MediaFormat.KEY_COLOR_FORMAT,
                        MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420SemiPlanar)
                }

                val encoder = MediaCodec.createEncoderByType(mime)
                encoder.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
                encoder.start()

                val outFile = File(ctx.cacheDir, "hypr_${System.currentTimeMillis()}.mp4")
                val muxer   = MediaMuxer(outFile.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
                var videoTrack   = -1
                var muxerStarted = false
                val bufInfo      = MediaCodec.BufferInfo()
                val usPerFrame   = 1_000_000L / fps   // fallback si no hay timestamps

                fun drain(eos: Boolean) {
                    while (true) {
                        val outIdx = encoder.dequeueOutputBuffer(bufInfo, if (eos) 10_000L else 0L)
                        when {
                            outIdx == MediaCodec.INFO_TRY_AGAIN_LATER -> break
                            outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                                videoTrack = muxer.addTrack(encoder.outputFormat)
                                muxer.start()
                                muxerStarted = true
                            }
                            outIdx >= 0 -> {
                                val isConfig = bufInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0
                                if (!isConfig && muxerStarted) {
                                    muxer.writeSampleData(videoTrack,
                                        encoder.getOutputBuffer(outIdx)!!, bufInfo)
                                }
                                encoder.releaseOutputBuffer(outIdx, false)
                                if (bufInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) return
                            }
                        }
                    }
                }

                for ((idx, file) in frameFiles.withIndex()) {
                    val bmp = BitmapFactory.decodeFile(file.absolutePath) ?: continue
                    val scaled = if (bmp.width != videoW || bmp.height != videoH)
                        Bitmap.createScaledBitmap(bmp, videoW, videoH, true).also { bmp.recycle() }
                    else bmp

                    val yuv = argbToNV12(scaled)
                    scaled.recycle()

                    val pts = idx.toLong() * usPerFrame
                    val inIdx = encoder.dequeueInputBuffer(10_000L)
                    if (inIdx >= 0) {
                        encoder.getInputBuffer(inIdx)!!.apply { clear(); put(yuv) }
                        encoder.queueInputBuffer(inIdx, 0, yuv.size, pts, 0)
                    }
                    drain(false)
                }

                // Señal de fin de stream
                val lastPts = frameFiles.size.toLong() * usPerFrame
                val inIdx = encoder.dequeueInputBuffer(10_000L)
                if (inIdx >= 0) {
                    encoder.queueInputBuffer(inIdx, 0, 0,
                        lastPts, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                }
                drain(true)

                encoder.stop()
                encoder.release()
                muxer.stop()
                muxer.release()

                // Guarda en MediaStore → álbum Movies/HYPR AR
                val cv = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME,
                        "HYPR_VIDEO_${System.currentTimeMillis()}")
                    put(MediaStore.MediaColumns.MIME_TYPE, "video/mp4")
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        put(MediaStore.Video.Media.RELATIVE_PATH, "Movies/HYPR AR")
                    }
                }
                val uri = ctx.contentResolver.insert(
                    MediaStore.Video.Media.EXTERNAL_CONTENT_URI, cv)
                if (uri != null) {
                    ctx.contentResolver.openOutputStream(uri)?.use { os ->
                        outFile.inputStream().copyTo(os)
                    }
                }
                outFile.delete()
                dir.deleteRecursively()

                activity?.runOnUiThread { result.success(uri?.toString()) }

            } catch (e: Exception) {
                activity?.runOnUiThread {
                    result.error("ENCODE_ERROR", e.message, null)
                }
            }
        }
    }

    // Convierte Bitmap ARGB_8888 → NV12 (YUV420SemiPlanar)
    private fun argbToNV12(bmp: Bitmap): ByteArray {
        val w = bmp.width
        val h = bmp.height
        val argb = IntArray(w * h)
        bmp.getPixels(argb, 0, w, 0, 0, w, h)
        val nv12 = ByteArray(w * h * 3 / 2)
        var yOff  = 0
        var uvOff = w * h
        for (j in 0 until h) {
            for (i in 0 until w) {
                val px = argb[j * w + i]
                val r  = (px shr 16) and 0xFF
                val g  = (px shr  8) and 0xFF
                val b  =  px         and 0xFF
                nv12[yOff++] = (((66 * r + 129 * g + 25 * b + 128) shr 8) + 16).toByte()
                if (j and 1 == 0 && i and 1 == 0) {
                    nv12[uvOff++] = (((-38 * r -  74 * g + 112 * b + 128) shr 8) + 128).toByte()
                    nv12[uvOff++] = (((112 * r -  94 * g -  18 * b + 128) shr 8) + 128).toByte()
                }
            }
        }
        return nv12
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { eventSink = events }
    override fun onCancel(arguments: Any?) { eventSink = null }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) { activity = binding.activity }
    override fun onDetachedFromActivityForConfigChanges() { activity = null }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) { activity = binding.activity }
    override fun onDetachedFromActivity() { activity = null }
    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        analysisExecutor.shutdown()
        recordingExecutor.shutdown()
    }
}
