package com.edde746.plezy.plezytv

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.net.Uri
import android.os.Binder
import android.os.ParcelFileDescriptor
import java.io.File
import java.io.FileNotFoundException

/** adb transport for the same fixed file used by Dart's SettingsTransferService. */
class SettingsFileProvider : ContentProvider() {
  override fun onCreate(): Boolean = context != null

  private fun enforceCaller() {
    val uid = Binder.getCallingUid()
    if (uid != 2000 && uid != 0) throw SecurityException("Settings transport requires shell or root")
  }

  override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
    enforceCaller()
    val appContext = context ?: throw FileNotFoundException("Provider unavailable")
    if (uri.scheme != "content" || uri.authority != appContext.packageName + ".settings" ||
      uri.encodedPath != "/settings.json" || uri.query != null || uri.fragment != null) {
      throw FileNotFoundException("Unknown settings URI")
    }
    val flags = when (mode) {
      "r" -> ParcelFileDescriptor.MODE_READ_ONLY
      "w", "wt" -> ParcelFileDescriptor.MODE_WRITE_ONLY or
        ParcelFileDescriptor.MODE_CREATE or ParcelFileDescriptor.MODE_TRUNCATE
      else -> throw FileNotFoundException("Unsupported settings mode")
    }
    val directory = appContext.getExternalFilesDir(null)
      ?: throw FileNotFoundException("External storage unavailable")
    return ParcelFileDescriptor.open(File(directory, "plezytv-settings.json"), flags)
  }

  override fun getType(uri: Uri): String {
    enforceCaller()
    throw UnsupportedOperationException("Only file reads and writes are supported")
  }

  override fun query(uri: Uri, projection: Array<out String>?, selection: String?,
    selectionArgs: Array<out String>?, sortOrder: String?): Cursor? {
    enforceCaller()
    throw UnsupportedOperationException("Query is not supported")
  }

  override fun insert(uri: Uri, values: ContentValues?): Uri? {
    enforceCaller()
    throw UnsupportedOperationException("Insert is not supported")
  }

  override fun update(uri: Uri, values: ContentValues?, selection: String?,
    selectionArgs: Array<out String>?): Int {
    enforceCaller()
    throw UnsupportedOperationException("Update is not supported")
  }

  override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int {
    enforceCaller()
    throw UnsupportedOperationException("Delete is not supported")
  }
}
