package com.wavebreak.wavebreak

import android.content.ClipData
import android.content.Context
import android.content.Intent
import androidx.core.content.FileProvider
import java.io.File

/**
 * Shares a file (the diagnostic log) through the system share sheet so
 * that the receiving app opens as ITSELF. share_plus starts the share from
 * our activity (for its result), which puts the target — Telegram, say —
 * inside WAVEBREAK's task: in Recents it looked like Telegram running
 * inside our app. FLAG_ACTIVITY_NEW_TASK makes the target start in its own
 * task instead.
 */
object FileSharer {
    fun share(context: Context, path: String, mimeType: String, text: String?): Boolean {
        val source = File(path)
        if (!source.isFile) return false
        // Only cacheDir/shared/ is exposed through the FileProvider (see
        // res/xml/file_paths.xml), so the file is copied there first.
        val dir = File(context.cacheDir, "shared").apply { mkdirs() }
        val copy = File(dir, source.name)
        source.copyTo(copy, overwrite = true)
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", copy)
        val send = Intent(Intent.ACTION_SEND).apply {
            type = mimeType
            putExtra(Intent.EXTRA_STREAM, uri)
            if (text != null) putExtra(Intent.EXTRA_TEXT, text)
            clipData = ClipData.newRawUri(null, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        val chooser = Intent.createChooser(send, null).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(chooser)
        return true
    }
}
