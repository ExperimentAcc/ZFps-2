package com.zsdev.fpsmonitor

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import java.io.File
import java.io.FileNotFoundException

/**
 * Tiny read-only content provider that lets other apps (Gmail, Drive, Files,
 * WhatsApp...) read the CSV / PNG files we hand to the share sheet.
 * Serves only files inside cacheDir/exports. No extra library needed.
 */
class ExportProvider : ContentProvider() {

    override fun onCreate(): Boolean = true

    private fun resolve(uri: Uri): File? {
        val name = uri.lastPathSegment ?: return null
        val base = File(context?.cacheDir ?: return null, "exports")
        return try {
            val file = File(base, name)
            // Block path tricks like ../
            if (file.canonicalPath.startsWith(base.canonicalPath + File.separator) && file.isFile) file else null
        } catch (_: Exception) {
            null
        }
    }

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor? {
        val file = resolve(uri) ?: throw FileNotFoundException(uri.toString())
        return ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
    }

    override fun query(
        uri: Uri,
        projection: Array<String>?,
        selection: String?,
        selectionArgs: Array<String>?,
        sortOrder: String?
    ): Cursor? {
        val file = resolve(uri) ?: return null
        val columns = projection ?: arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
        val row = arrayOfNulls<Any>(columns.size)
        columns.forEachIndexed { i, column ->
            row[i] = when (column) {
                OpenableColumns.DISPLAY_NAME -> file.name
                OpenableColumns.SIZE -> file.length()
                else -> null
            }
        }
        return MatrixCursor(columns).apply { addRow(row) }
    }

    override fun getType(uri: Uri): String? {
        val name = uri.lastPathSegment?.lowercase() ?: return null
        return when {
            name.endsWith(".csv") -> "text/csv"
            name.endsWith(".png") -> "image/png"
            else -> "application/octet-stream"
        }
    }

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<String>?): Int = 0

    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<String>?
    ): Int = 0
}
