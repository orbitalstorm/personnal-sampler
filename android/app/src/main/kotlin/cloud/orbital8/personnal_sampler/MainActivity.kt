package cloud.orbital8.personnal_sampler

import android.Manifest
import android.app.Activity
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.database.Cursor
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.media.PlaybackParams
import android.media.SoundPool
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.ConcurrentHashMap
import kotlin.math.abs

class MainActivity : FlutterActivity() {
    private val channelName = "cloud.orbital8.personnal_sampler/audio"
    private val reqRecordAudio = 4001
    private val reqPickAudioFile = 4002

    private var soundPool: SoundPool? = null
    private val padSoundIdMap = ConcurrentHashMap<Int, Int>()
    private val padFilePathMap = ConcurrentHashMap<Int, String>()
    private val loadedSoundIds = ConcurrentHashMap.newKeySet<Int>()
    private val activeStreamIds = ConcurrentHashMap<Int, MutableList<Int>>()
    private val activePlayers = ConcurrentHashMap<Int, MutableList<MediaPlayer>>()
    private val loopingPads = ConcurrentHashMap.newKeySet<Int>()
    private val padChokeGroups = ConcurrentHashMap<Int, Int>()

    @Volatile
    private var isRecordingMic = false
    @Volatile
    private var currentMicPeak = 0.0
    private var audioRecord: AudioRecord? = null
    private var recordingThread: Thread? = null
    private var recordedPcmBuffer: ByteArrayOutputStream? = null
    private var recordingPadId: Int = 0
    private val sampleRate = 44100

    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingPermissionPadId: Int = 0

    private var pendingPickResult: MethodChannel.Result? = null
    private var pendingPickPadId: Int = 0

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        initSoundPool()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getStorageDir" -> {
                        val samplesDir = File(applicationContext.filesDir, "samples")
                        if (!samplesDir.exists()) {
                            samplesDir.mkdirs()
                        }
                        result.success(applicationContext.filesDir.absolutePath)
                    }

                    "preloadPadSound" -> {
                        val padId = call.argument<Int>("padId") ?: 0
                        val filePath = call.argument<String>("filePath") ?: ""
                        if (filePath.isEmpty() || !File(filePath).exists()) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        preloadPad(padId, filePath)
                        result.success(true)
                    }

                    "triggerPad" -> {
                        val padId = call.argument<Int>("padId") ?: 0
                        val filePath = call.argument<String>("filePath") ?: ""
                        val volume = (call.argument<Double>("volume") ?: 1.0).toFloat().coerceIn(0f, 1.5f)
                        val pitch = (call.argument<Double>("pitch") ?: 1.0).toFloat().coerceIn(0.5f, 2.0f)
                        val mode = call.argument<String>("mode") ?: "retrigger"
                        val chokeGroup = call.argument<Int>("chokeGroup") ?: 0

                        if (filePath.isEmpty() || !File(filePath).exists()) {
                            result.success(mapOf("playing" to false, "error" to "FILE_NOT_FOUND"))
                            return@setMethodCallHandler
                        }

                        val outcome = triggerPadInternal(padId, filePath, volume, pitch, mode, chokeGroup)
                        result.success(outcome)
                    }

                    "stopPad" -> {
                        val padId = call.argument<Int>("padId") ?: 0
                        stopPadStreams(padId)
                        result.success(true)
                    }

                    "stopAllPads" -> {
                        stopAllActiveSounds()
                        result.success(true)
                    }

                    "startMicRecording" -> {
                        val padId = call.argument<Int>("padId") ?: 0
                        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                            pendingPermissionResult = result
                            pendingPermissionPadId = padId
                            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), reqRecordAudio)
                        } else {
                            val started = startMicRecordingInternal(padId)
                            if (started) {
                                result.success(mapOf("started" to true))
                            } else {
                                result.error("MIC_INIT_FAILED", "Impossible d'initialiser le microphone.", null)
                            }
                        }
                    }

                    "getMicAmplitude" -> {
                        result.success(currentMicPeak)
                    }

                    "stopMicRecording" -> {
                        try {
                            val recorded = stopMicRecordingInternal()
                            result.success(recorded)
                        } catch (e: Exception) {
                            result.error("MIC_STOP_FAILED", e.message, null)
                        }
                    }

                    "pickAudioFile" -> {
                        val padId = call.argument<Int>("padId") ?: 0
                        if (pendingPickResult != null) {
                            result.error("ALREADY_PICKING", "Sélecteur de fichier déjà ouvert.", null)
                            return@setMethodCallHandler
                        }
                        pendingPickResult = result
                        pendingPickPadId = padId
                        try {
                            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = "audio/*"
                                putExtra(
                                    Intent.EXTRA_MIME_TYPES,
                                    arrayOf(
                                        "audio/*",
                                        "audio/wav",
                                        "audio/x-wav",
                                        "audio/wave",
                                        "audio/mpeg",
                                        "audio/mp4",
                                        "audio/aac",
                                        "audio/ogg",
                                        "application/ogg"
                                    )
                                )
                            }
                            startActivityForResult(intent, reqPickAudioFile)
                        } catch (e: Exception) {
                            pendingPickResult = null
                            result.error("PICKER_FAILED", e.message, null)
                        }
                    }

                    "exportPadWav" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        val fileName = call.argument<String>("fileName") ?: "sample_pad.wav"
                        if (bytes == null) {
                            result.error("INVALID_ARGS", "Octets WAV manquants", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val savedPath = saveWavToMediaStore(bytes, fileName)
                            result.success(savedPath)
                        } catch (e: Exception) {
                            result.error("EXPORT_FAILED", e.message, null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun initSoundPool() {
        val attrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_GAME)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()

        soundPool = SoundPool.Builder()
            .setMaxStreams(32)
            .setAudioAttributes(attrs)
            .build()
            .apply {
                setOnLoadCompleteListener { _, sampleId, status ->
                    if (status == 0) {
                        loadedSoundIds.add(sampleId)
                    }
                }
            }
    }

    private fun preloadPad(padId: Int, filePath: String) {
        val pool = soundPool ?: return
        val existingPath = padFilePathMap[padId]
        val existingSoundId = padSoundIdMap[padId]
        if (existingPath == filePath && existingSoundId != null && loadedSoundIds.contains(existingSoundId)) {
            return
        }
        if (existingSoundId != null) {
            pool.unload(existingSoundId)
            loadedSoundIds.remove(existingSoundId)
        }
        val f = File(filePath)
        // SoundPool excels at short/medium uncompressed samples (< 2 MB)
        if (f.exists() && f.length() <= 2_000_000L) {
            val newSoundId = pool.load(filePath, 1)
            padSoundIdMap[padId] = newSoundId
            padFilePathMap[padId] = filePath
        } else {
            padSoundIdMap.remove(padId)
            padFilePathMap[padId] = filePath
        }
    }

    private fun triggerPadInternal(
        padId: Int,
        filePath: String,
        volume: Float,
        pitch: Float,
        mode: String,
        chokeGroup: Int
    ): Map<String, Any> {
        if (chokeGroup > 0) {
            padChokeGroups[padId] = chokeGroup
            for ((otherPadId, group) in padChokeGroups.entries) {
                if (group == chokeGroup && otherPadId != padId) {
                    stopPadStreams(otherPadId)
                }
            }
        } else {
            padChokeGroups.remove(padId)
        }

        if (mode == "loop") {
            if (loopingPads.contains(padId)) {
                stopPadStreams(padId)
                return mapOf("playing" to false, "looping" to false)
            }
            stopPadStreams(padId)
            loopingPads.add(padId)
            playSample(padId, filePath, volume, pitch, isLoop = true)
            return mapOf("playing" to true, "looping" to true)
        }

        if (mode == "retrigger") {
            stopPadStreams(padId)
        }

        playSample(padId, filePath, volume, pitch, isLoop = false)
        return mapOf("playing" to true, "looping" to false)
    }

    private fun playSample(
        padId: Int,
        filePath: String,
        volume: Float,
        pitch: Float,
        isLoop: Boolean
    ) {
        val clampedVol = volume.coerceIn(0f, 1.0f)
        val clampedRate = pitch.coerceIn(0.5f, 2.0f)
        val pool = soundPool
        val cachedPath = padFilePathMap[padId]
        val soundId = padSoundIdMap[padId]

        if (pool != null && cachedPath == filePath && soundId != null && loadedSoundIds.contains(soundId)) {
            val loopFlag = if (isLoop) -1 else 0
            val streamId = pool.play(soundId, clampedVol, clampedVol, 1, loopFlag, clampedRate)
            if (streamId != 0) {
                val list = activeStreamIds.getOrPut(padId) { mutableListOf() }
                synchronized(list) {
                    list.add(streamId)
                }
                return
            }
        }

        // Preload for subsequent ultra-fast hits and use MediaPlayer immediately for this hit
        preloadPad(padId, filePath)

        try {
            val mp = MediaPlayer()
            val attrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_GAME)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                .build()
            mp.setAudioAttributes(attrs)
            mp.setDataSource(filePath)
            mp.prepare()
            mp.setVolume(clampedVol, clampedVol)
            mp.isLooping = isLoop
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && clampedRate != 1.0f) {
                try {
                    val params = PlaybackParams().setSpeed(clampedRate).setPitch(clampedRate)
                    mp.playbackParams = params
                } catch (_: Exception) {
                }
            }
            val playerList = activePlayers.getOrPut(padId) { mutableListOf() }
            synchronized(playerList) {
                playerList.add(mp)
            }
            mp.setOnCompletionListener { completed ->
                synchronized(playerList) {
                    playerList.remove(completed)
                }
                if (!isLoop) {
                    loopingPads.remove(padId)
                }
                try {
                    completed.release()
                } catch (_: Exception) {
                }
            }
            mp.start()
        } catch (_: Exception) {
        }
    }

    private fun stopPadStreams(padId: Int) {
        loopingPads.remove(padId)
        val pool = soundPool
        val streamList = activeStreamIds.remove(padId)
        if (pool != null && streamList != null) {
            synchronized(streamList) {
                for (streamId in streamList) {
                    try {
                        pool.stop(streamId)
                    } catch (_: Exception) {
                    }
                }
                streamList.clear()
            }
        }

        val playerList = activePlayers.remove(padId)
        if (playerList != null) {
            synchronized(playerList) {
                for (mp in playerList) {
                    try {
                        if (mp.isPlaying) {
                            mp.stop()
                        }
                    } catch (_: Exception) {
                    }
                    try {
                        mp.release()
                    } catch (_: Exception) {
                    }
                }
                playerList.clear()
            }
        }
    }

    private fun stopAllActiveSounds() {
        loopingPads.clear()
        val padIds = HashSet<Int>()
        padIds.addAll(activeStreamIds.keys)
        padIds.addAll(activePlayers.keys)
        for (id in padIds) {
            stopPadStreams(id)
        }
    }

    private fun startMicRecordingInternal(padId: Int): Boolean {
        if (isRecordingMic) {
            stopMicRecordingInternal()
        }
        val minBufSize = AudioRecord.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )
        if (minBufSize <= 0) {
            return false
        }
        val bufferSize = maxOf(minBufSize * 2, 4096)
        return try {
            val recorder = AudioRecord(
                MediaRecorder.AudioSource.MIC,
                sampleRate,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                bufferSize
            )
            if (recorder.state != AudioRecord.STATE_INITIALIZED) {
                recorder.release()
                return false
            }
            val pcmStream = ByteArrayOutputStream()
            recordedPcmBuffer = pcmStream
            recordingPadId = padId
            audioRecord = recorder
            currentMicPeak = 0.0
            isRecordingMic = true

            recorder.startRecording()

            recordingThread = Thread {
                val shortBuf = ShortArray(1024)
                val byteBuf = ByteBuffer.allocate(2048).order(ByteOrder.LITTLE_ENDIAN)
                while (isRecordingMic) {
                    val readCount = recorder.read(shortBuf, 0, shortBuf.size)
                    if (readCount > 0) {
                        var maxSample = 0
                        byteBuf.clear()
                        for (i in 0 until readCount) {
                            val s = shortBuf[i]
                            val absVal = abs(s.toInt())
                            if (absVal > maxSample) {
                                maxSample = absVal
                            }
                            byteBuf.putShort(s)
                        }
                        currentMicPeak = (maxSample.toDouble() / 32768.0).coerceIn(0.0, 1.0)
                        synchronized(pcmStream) {
                            pcmStream.write(byteBuf.array(), 0, readCount * 2)
                        }
                    }
                }
            }.apply {
                priority = Thread.MAX_PRIORITY
                start()
            }
            true
        } catch (_: SecurityException) {
            false
        } catch (_: Exception) {
            false
        }
    }

    private fun stopMicRecordingInternal(): Map<String, Any> {
        isRecordingMic = false
        currentMicPeak = 0.0
        try {
            recordingThread?.join(800)
        } catch (_: Exception) {
        }
        recordingThread = null

        try {
            audioRecord?.stop()
        } catch (_: Exception) {
        }
        try {
            audioRecord?.release()
        } catch (_: Exception) {
        }
        audioRecord = null

        val pcmBytes = recordedPcmBuffer?.toByteArray() ?: ByteArray(0)
        recordedPcmBuffer = null

        val samplesDir = File(applicationContext.filesDir, "samples")
        if (!samplesDir.exists()) {
            samplesDir.mkdirs()
        }

        val wavBytes = buildWavBytesFromPcm16Mono(pcmBytes, sampleRate)
        val outFile = File(samplesDir, "mic_pad_${recordingPadId}_${System.currentTimeMillis()}.wav")
        FileOutputStream(outFile).use { fos ->
            fos.write(wavBytes)
            fos.flush()
        }

        val totalSamples = pcmBytes.size / 2
        val durationMs = ((totalSamples.toDouble() / sampleRate.toDouble()) * 1000.0).toInt()

        preloadPad(recordingPadId, outFile.absolutePath)

        return mapOf(
            "path" to outFile.absolutePath,
            "bytes" to wavBytes,
            "durationMs" to durationMs,
            "sampleRate" to sampleRate
        )
    }

    private fun buildWavBytesFromPcm16Mono(pcmBytes: ByteArray, sampleRate: Int): ByteArray {
        val totalDataLen = pcmBytes.size + 36
        val byteRate = sampleRate * 2
        val header = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN)
        header.put("RIFF".toByteArray(Charsets.US_ASCII))
        header.putInt(totalDataLen)
        header.put("WAVE".toByteArray(Charsets.US_ASCII))
        header.put("fmt ".toByteArray(Charsets.US_ASCII))
        header.putInt(16) // PCM chunk size
        header.putShort(1) // AudioFormat = 1 (PCM)
        header.putShort(1) // NumChannels = 1 (Mono)
        header.putInt(sampleRate)
        header.putInt(byteRate)
        header.putShort(2) // BlockAlign = 2 bytes
        header.putShort(16) // BitsPerSample = 16
        header.put("data".toByteArray(Charsets.US_ASCII))
        header.putInt(pcmBytes.size)

        val out = ByteArray(44 + pcmBytes.size)
        System.arraycopy(header.array(), 0, out, 0, 44)
        System.arraycopy(pcmBytes, 0, out, 44, pcmBytes.size)
        return out
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == reqRecordAudio) {
            val res = pendingPermissionResult
            pendingPermissionResult = null
            if (res != null) {
                if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                    val started = startMicRecordingInternal(pendingPermissionPadId)
                    if (started) {
                        res.success(mapOf("started" to true))
                    } else {
                        res.error("MIC_INIT_FAILED", "Impossible d'initialiser le microphone.", null)
                    }
                } else {
                    res.error("PERMISSION_DENIED", "Permission microphone refusée par l'utilisateur.", null)
                }
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == reqPickAudioFile) {
            val res = pendingPickResult
            pendingPickResult = null
            if (res == null) return

            if (resultCode != Activity.RESULT_OK || data?.data == null) {
                res.success(null)
                return
            }

            val uri: Uri = data.data!!
            try {
                val displayName = resolveDisplayName(uri) ?: "sample_import.wav"
                val safeName = displayName.replace(Regex("[^a-zA-Z0-9._-]"), "_")
                val samplesDir = File(applicationContext.filesDir, "samples")
                if (!samplesDir.exists()) {
                    samplesDir.mkdirs()
                }
                val outFile = File(
                    samplesDir,
                    "import_pad_${pendingPickPadId}_${System.currentTimeMillis()}_$safeName"
                )
                val fileBytes = applicationContext.contentResolver.openInputStream(uri)?.use { input ->
                    input.readBytes()
                } ?: throw IllegalStateException("Impossible de lire le fichier sélectionné")

                FileOutputStream(outFile).use { fos ->
                    fos.write(fileBytes)
                    fos.flush()
                }

                preloadPad(pendingPickPadId, outFile.absolutePath)

                res.success(
                    mapOf(
                        "path" to outFile.absolutePath,
                        "fileName" to displayName,
                        "bytes" to fileBytes,
                        "sizeBytes" to fileBytes.size
                    )
                )
            } catch (e: Exception) {
                res.error("IMPORT_FAILED", e.message, null)
            }
        }
    }

    private fun resolveDisplayName(uri: Uri): String? {
        var cursor: Cursor? = null
        return try {
            cursor = applicationContext.contentResolver.query(uri, null, null, null, null)
            if (cursor != null && cursor.moveToFirst()) {
                val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (idx >= 0) cursor.getString(idx) else null
            } else {
                uri.lastPathSegment
            }
        } catch (_: Exception) {
            uri.lastPathSegment
        } finally {
            cursor?.close()
        }
    }

    private fun saveWavToMediaStore(bytes: ByteArray, fileName: String): String {
        val cleanName = if (fileName.lowercase().endsWith(".wav")) fileName else "$fileName.wav"
        val resolver = applicationContext.contentResolver
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Audio.Media.DISPLAY_NAME, cleanName)
                put(MediaStore.Audio.Media.MIME_TYPE, "audio/wav")
                put(
                    MediaStore.Audio.Media.RELATIVE_PATH,
                    Environment.DIRECTORY_MUSIC + "/LifeSampler"
                )
                put(MediaStore.Audio.Media.IS_PENDING, 1)
            }
            val uri = resolver.insert(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("Impossible de créer l'entrée MediaStore")
            resolver.openOutputStream(uri)?.use { stream ->
                stream.write(bytes)
                stream.flush()
            } ?: throw IllegalStateException("Impossible d'ouvrir le flux MediaStore")
            values.clear()
            values.put(MediaStore.Audio.Media.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            return "Music/LifeSampler/$cleanName"
        } else {
            val dir = File(
                applicationContext.getExternalFilesDir(Environment.DIRECTORY_MUSIC),
                "LifeSampler"
            )
            if (!dir.exists()) {
                dir.mkdirs()
            }
            val outFile = File(dir, cleanName)
            FileOutputStream(outFile).use { stream ->
                stream.write(bytes)
                stream.flush()
            }
            return outFile.absolutePath
        }
    }

    override fun onDestroy() {
        stopAllActiveSounds()
        soundPool?.release()
        soundPool = null
        super.onDestroy()
    }
}
