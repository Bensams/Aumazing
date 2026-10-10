package app.aumazing

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Native half of the in-app APK update (see `AppUpdateService` in Dart).
 *
 * Dart downloads and checks the APK. This side does what only Android can
 * do: report the installed versionCode, check and open the "install unknown
 * apps" permission, and pass the file to the system package installer. The
 * installer still asks the parent to confirm, and Android rejects any APK
 * that is not signed with the same key as the installed app.
 */
class AppUpdateChannel(private val activity: Activity, messenger: BinaryMessenger) {
    init {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "installedVersion" -> result.success(installedVersion())
                "canInstallPackages" -> result.success(canInstallPackages())
                "openInstallPermissionSettings" -> result.success(openInstallPermissionSettings())
                "installApk" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("bad_args", "path is required", null)
                    } else {
                        result.success(installApk(File(path)))
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun installedVersion(): Map<String, Any?> {
        val info = activity.packageManager.getPackageInfo(activity.packageName, 0)
        val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            info.versionCode.toLong()
        }
        return mapOf("code" to code, "name" to info.versionName)
    }

    /**
     * Before Android 8 the permission was one global setting that apps cannot
     * read; the installer explains it itself, so report true there.
     */
    private fun canInstallPackages(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            activity.packageManager.canRequestPackageInstalls()

    private fun openInstallPermissionSettings(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        return try {
            activity.startActivity(
                Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:${activity.packageName}"),
                ),
            )
            true
        } catch (e: ActivityNotFoundException) {
            false
        }
    }

    private fun installApk(file: File): Boolean {
        if (!file.isFile) return false
        val uri = FileProvider.getUriForFile(
            activity,
            "${activity.packageName}.appupdate",
            file,
        )
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, APK_MIME_TYPE)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        return try {
            activity.startActivity(intent)
            true
        } catch (e: ActivityNotFoundException) {
            false
        }
    }

    private companion object {
        const val CHANNEL = "aumazing/app_update"
        const val APK_MIME_TYPE = "application/vnd.android.package-archive"
    }
}
