package com.example.adirstat

import android.content.Intent
import android.net.Uri
import android.os.StrictMode
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader

class MainActivity : FlutterActivity() {
    private val SHELL_CHANNEL = "com.example.adirstat/shell"
    private val FILE_MANAGER_CHANNEL = "com.example.adirstat/filemanager"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHELL_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "runCommand") {
                val command = call.argument<String>("command") ?: ""
                val output = runShellCommand(command)
                result.success(output)
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FILE_MANAGER_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "openInFileManager") {
                val path = call.argument<String>("path") ?: "/"
                openInFileManager(path)
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }

    private fun runShellCommand(command: String): String {
        return try {
            val process = Runtime.getRuntime().exec(arrayOf("su", "-c", command))
            val reader = BufferedReader(InputStreamReader(process.inputStream))
            val output = StringBuilder()
            var line: String?

            while (reader.readLine().also { line = it } != null) {
                output.append(line).append("\n")
            }

            reader.close()
            process.waitFor()
            output.toString()
        } catch (e: Exception) {
            "Error: ${e.message}"
        }
    }

    private fun openInFileManager(path: String) {
        StrictMode.setVmPolicy(StrictMode.VmPolicy.Builder().build())

        val file = File(path)
        val uri = Uri.fromFile(file)

        val intent = Intent(Intent.ACTION_VIEW)
        intent.setDataAndType(uri, "*/*")
        intent.addCategory(Intent.CATEGORY_DEFAULT)
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)

        val chooser = Intent.createChooser(intent, "Open with File Manager")

        try {
            startActivity(chooser)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
}
