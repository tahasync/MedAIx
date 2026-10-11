package com.tahasync.medaix

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import androidx.core.content.ContextCompat

class MainActivity : FlutterActivity() {
    private val cameraPermissionRequestCode = 9217
    private var cameraPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CAMERA_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestCameraPermission" -> requestCameraPermission(result)
                    "openAppSettings" -> {
                        val intent = Intent(
                            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.fromParts("package", packageName, null),
                        )
                        startActivity(intent)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun requestCameraPermission(result: MethodChannel.Result) {
        if (cameraPermissionResult != null) {
            result.error("permission_request_in_progress", "Camera permission is already being requested.", null)
            return
        }
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
            result.success(mapOf("granted" to true, "permanentlyDenied" to false))
            return
        }

        val preferences = getSharedPreferences("medaix_camera_permission", MODE_PRIVATE)
        val requestedBefore = preferences.getBoolean("requested", false)
        preferences.edit().putBoolean("requested", true).apply()
        cameraPermissionResult = result
        requestPermissions(arrayOf(Manifest.permission.CAMERA), cameraPermissionRequestCode)
        pendingCameraPermissionWasRequestedBefore = requestedBefore
    }

    private var pendingCameraPermissionWasRequestedBefore = false

    @Suppress("DEPRECATION")
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != cameraPermissionRequestCode) return

        val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
        val permanentlyDenied = !granted && pendingCameraPermissionWasRequestedBefore &&
            !shouldShowRequestPermissionRationale(Manifest.permission.CAMERA)
        pendingCameraPermissionWasRequestedBefore = false
        cameraPermissionResult?.success(
            mapOf("granted" to granted, "permanentlyDenied" to permanentlyDenied),
        )
        cameraPermissionResult = null
    }

    private companion object {
        const val CAMERA_CHANNEL = "com.tahasync.medaix/camera_permission"
    }
}
