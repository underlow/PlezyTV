package com.edde746.plezy.deeplink

import android.content.Intent
import android.net.Uri
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** PlezyTV: fork links (settings transfer, screen) reach Dart like any other plezytv:// link. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class SettingsIntentTest {
  @Test
  fun forkLinksReachDartUnchanged() {
    for (uri in listOf(
      "plezytv://settings/export",
      "plezytv://settings/import",
      "plezytv://screen/settings",
      "plezytv://live?channel=4.1",
      "plezytv://play?content_id=plezy_a_1"
    )) {
      assertEquals(uri, DeepLinkPlugin.linkFrom(Intent(Intent.ACTION_VIEW, Uri.parse(uri))))
    }
  }

  @Test
  fun originalPlezyLinksAreNotOurs() {
    assertNull(DeepLinkPlugin.linkFrom(Intent(Intent.ACTION_VIEW, Uri.parse("plezy://open"))))
  }
}
