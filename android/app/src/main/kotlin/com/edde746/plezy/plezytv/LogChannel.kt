package com.edde746.plezy.plezytv

import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec

/** Ordered, bounded Dart batches; each message is already redacted and chunked. */
class LogChannel(messenger: BinaryMessenger) {
  init {
    MethodChannel(messenger, "com.underlow.plezytv/logs", StandardMethodCodec.INSTANCE,
      messenger.makeBackgroundTaskQueue()).setMethodCallHandler { call, result ->
      if (call.method != "write") {
        result.notImplemented()
      } else {
        val lines = call.arguments as? List<*>
        if (lines == null || lines.size > 64) {
          result.error("invalid_batch", "Expected at most 64 log chunks", null)
        } else {
          for (entry in lines) {
            val line = entry as? Map<*, *> ?: continue
            val priority = (line["priority"] as? Number)?.toInt() ?: continue
            val message = line["message"] as? String ?: continue
            if (priority in Log.DEBUG..Log.ERROR) Log.println(priority, "PlezyTV", message)
          }
          result.success(null)
        }
      }
    }
  }
}
