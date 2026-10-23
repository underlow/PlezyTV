package com.edde746.plezy.plezytv

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

class UpdateChannel(private val activity: Activity, messenger: BinaryMessenger) {
  init {
    MethodChannel(messenger, "com.underlow.plezytv/update").setMethodCallHandler { call, result ->
      try {
        when (call.method) {
          // The process bitness describes the installed APK, unlike SUPPORTED_ABIS.
          "abi" -> result.success(if (android.os.Process.is64Bit()) "arm64-v8a" else "armeabi-v7a")
          "canInstall" -> result.success(Build.VERSION.SDK_INT < 26 || activity.packageManager.canRequestPackageInstalls())
          "openPermission" -> {
            activity.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${activity.packageName}")))
            result.success(null)
          }
          "install" -> {
            val file = File(call.arguments as String).canonicalFile
            require(file.parentFile == activity.cacheDir.canonicalFile && file.name.startsWith("plezytv-update-") && file.extension == "apk" && file.isFile)
            val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.fileprovider", file)
            activity.startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive")
              .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
            result.success(null)
          }
          else -> result.notImplemented()
        }
      } catch (error: Exception) {
        result.error("update_failed", error.message, null)
      }
    }
  }
}
