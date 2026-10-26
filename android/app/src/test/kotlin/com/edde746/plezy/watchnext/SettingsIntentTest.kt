package com.edde746.plezy.watchnext

import android.content.Intent
import android.net.Uri
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class SettingsIntentTest {
  @Test
  fun settingsAndExistingHostsReachDart() {
    for (uri in listOf(
      "plezytv://settings/export",
      "plezytv://settings/import",
      "plezytv://screen/settings",
      "plezytv://live?channel=4.1"
    )) {
      assertEquals(uri, WatchNextPlugin.handleIntent(Intent(Intent.ACTION_VIEW, Uri.parse(uri))))
    }
    assertEquals("plezy_a_1", WatchNextPlugin.handleIntent(
      Intent(Intent.ACTION_VIEW, Uri.parse("plezytv://play?content_id=plezy_a_1"))
    ))
  }
}
