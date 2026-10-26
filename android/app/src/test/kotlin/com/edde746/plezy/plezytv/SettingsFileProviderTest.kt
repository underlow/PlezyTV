package com.edde746.plezy.plezytv

import android.content.Context
import android.net.Uri
import android.os.ParcelFileDescriptor
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowBinder
import java.io.File
import java.io.FileNotFoundException

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28, 30], manifest = Config.NONE)
class SettingsFileProviderTest {
  private lateinit var provider: SettingsFileProvider
  private lateinit var file: File
  private lateinit var uri: Uri

  @Before fun setUp() {
    val context: Context = RuntimeEnvironment.getApplication()
    provider = Robolectric.buildContentProvider(SettingsFileProvider::class.java).create().get()
    uri = Uri.parse("content://${context.packageName}.settings/settings.json")
    file = File(context.getExternalFilesDir(null), "plezytv-settings.json")
    file.delete()
    ShadowBinder.setCallingUid(2000)
  }

  private fun read(): String = ParcelFileDescriptor.AutoCloseInputStream(
    provider.openFile(uri, "r")
  ).bufferedReader().use { it.readText() }

  private fun write(mode: String, value: String) {
    ParcelFileDescriptor.AutoCloseOutputStream(provider.openFile(uri, mode)).use {
      it.write(value.toByteArray())
    }
  }

  @Test fun shellReadsDartFileAndWritesSameFileWithTruncation() {
    file.writeText("settings exported by Dart")
    assertEquals("settings exported by Dart", read())
    for (mode in listOf("w", "wt")) {
      file.writeText("a much longer previous export")
      write(mode, "{}")
      assertEquals("{}", file.readText())
      assertEquals("{}", read())
    }
  }

  @Test fun shellCanCreateFileAndRootCanReadAndWrite() {
    write("w", "shell")
    assertEquals("shell", file.readText())
    ShadowBinder.setCallingUid(0)
    assertEquals("shell", read())
    write("wt", "root")
    assertEquals("root", file.readText())
  }

  @Test fun otherUidCannotReadWriteOrCreateFile() {
    file.writeText("unchanged")
    ShadowBinder.setCallingUid(10001)
    for (mode in listOf("r", "w", "wt")) {
      assertThrows(SecurityException::class.java) { provider.openFile(uri, mode) }
      assertEquals("unchanged", file.readText())
    }
    file.delete()
    assertThrows(SecurityException::class.java) { provider.openFile(uri, "w") }
    assertFalse(file.exists())
  }

  @Test fun unknownUrisAndModesAreRejectedWithoutChangingFile() {
    file.writeText("unchanged")
    for (suffix in listOf("other.json", "settings.json/extra", "../settings.json",
      "settings.json?query=1", "settings.json#fragment")) {
      assertThrows(FileNotFoundException::class.java) {
        provider.openFile(Uri.parse("content://${uri.authority}/$suffix"), "w")
      }
    }
    for (mode in listOf("rw", "rwt", "wa", "", "invalid")) {
      assertThrows(FileNotFoundException::class.java) { provider.openFile(uri, mode) }
    }
    assertEquals("unchanged", file.readText())
  }

  @Test fun missingFileCannotBeRead() {
    assertThrows(FileNotFoundException::class.java) { provider.openFile(uri, "r") }
    assertFalse(file.exists())
  }

  @Test fun nonFileOperationsAreRejected() {
    val operations = listOf<() -> Any?>(
      { provider.query(uri, null, null, null, null) },
      { provider.insert(uri, null) },
      { provider.update(uri, null, null, null) },
      { provider.delete(uri, null, null) },
      { provider.getType(uri) }
    )
    for (operation in operations) {
      assertThrows(UnsupportedOperationException::class.java) { operation() }
    }
    ShadowBinder.setCallingUid(10001)
    for (operation in operations) {
      assertThrows(SecurityException::class.java) { operation() }
    }
  }
}
