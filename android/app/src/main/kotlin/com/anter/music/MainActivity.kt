package com.anter.music

import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "anter.music/scan").setMethodCallHandler { call, result ->
            if (call.method == "scanSongs") {
                try {
                    result.success(scanSongs())
                } catch (e: Exception) {
                    result.success(emptyList<Map<String, Any>>())
                }
            } else {
                result.notImplemented()
            }
        }
    }

    private fun scanSongs(): List<Map<String, Any>> {
        val list = mutableListOf<Map<String, Any>>()
        val uri = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        val projection = arrayOf(MediaStore.Audio.Media.DATA, MediaStore.Audio.Media.TITLE, MediaStore.Audio.Media.DURATION)
        val selection = MediaStore.Audio.Media.IS_MUSIC + " != 0"
        contentResolver.query(uri, projection, selection, null, MediaStore.Audio.Media.TITLE + " ASC")?.use { c ->
            val iData = c.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA)
            val iTitle = c.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
            val iDur = c.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
            while (c.moveToNext()) {
                val path = c.getString(iData) ?: continue
                val title = c.getString(iTitle) ?: path.substringAfterLast('/')
                val dur = c.getLong(iDur)
                list.add(mapOf("path" to path, "title" to title, "duration" to dur))
            }
        }
        return list
    }
}
