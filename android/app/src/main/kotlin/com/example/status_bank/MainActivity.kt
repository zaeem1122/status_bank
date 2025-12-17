package com.example.status_bank

import android.content.Intent
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
import androidx.annotation.NonNull
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream


class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.yourapp/status_access"
    private val PICK_FOLDER_REQUEST = 123 // For Regular WhatsApp
    private val PICK_BUSINESS_FOLDER_REQUEST = 124 // For Business WhatsApp
    private var pendingResult: MethodChannel.Result? = null
    private var currentRequestType: String = "" // Track which WhatsApp type

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getAndroidVersion" -> {
                    result.success(Build.VERSION.SDK_INT)
                }
                // REGULAR WHATSAPP
                "openStatusFolderPicker" -> {
                    pendingResult = result
                    currentRequestType = "REGULAR"
                    openRegularWhatsAppFolderPicker()
                }
                // BUSINESS WHATSAPP
                "openBusinessStatusFolderPicker" -> {
                    pendingResult = result
                    currentRequestType = "BUSINESS"
                    openBusinessWhatsAppFolderPicker()
                }
                "getFilesFromUri" -> {
                    val uriString = call.argument<String>("uri")
                    val isBusinessStr = call.argument<String>("isBusiness") ?: "false"
                    val isBusiness = isBusinessStr == "true"

                    if (uriString != null) {
                        val files = getStatusFilesFromTreeUri(uriString, isBusiness)
                        result.success(files)
                    } else {
                        result.error("ERROR", "URI is null", null)
                    }
                }
                "takePersistablePermission" -> {
                    val uriString = call.argument<String>("uri")
                    if (uriString != null) {
                        takePersistableUriPermission(uriString)
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                "readFileBytes" -> {
                    val uriString = call.argument<String>("uri")
                    if (uriString != null) {
                        val bytes = readFileBytesFromUri(uriString)
                        result.success(bytes)
                    } else {
                        result.error("ERROR", "URI is null", null)
                    }
                }
                "getVideoThumbnail" -> {
                    val uriString = call.argument<String>("uri")
                    if (uriString != null) {
                        val thumbnail = getVideoThumbnailFromUri(uriString)
                        result.success(thumbnail)
                    } else {
                        result.error("ERROR", "URI is null", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    // For Regular WhatsApp (com.whatsapp)
    private fun openRegularWhatsAppFolderPicker() {
        try {
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                // Use 'document' instead of 'tree' - this opens the Media folder directly on all versions
                val initialUri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    // Android 11+: Open Android/media folder
                    Uri.parse("content://com.android.externalstorage.documents/document/primary%3AAndroid%2Fmedia")
                } else {
                    // Android 10 and below: Open root storage
                    Uri.parse("content://com.android.externalstorage.documents/document/primary%3A")
                }
                intent.putExtra(DocumentsContract.EXTRA_INITIAL_URI, initialUri)
            }

            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            intent.addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            intent.addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
            intent.addFlags(Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)

            startActivityForResult(intent, PICK_FOLDER_REQUEST)
        } catch (e: Exception) {
            e.printStackTrace()
            pendingResult?.error("ERROR", "Failed to open: ${e.message}", null)
            pendingResult = null
        }
    }

    // For Business WhatsApp (com.whatsapp.w4b)
    private fun openBusinessWhatsAppFolderPicker() {
        try {
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                // Use 'document' instead of 'tree' - this opens the Media folder directly on all versions
                val initialUri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    // Android 11+: Open Android/media folder
                    Uri.parse("content://com.android.externalstorage.documents/document/primary%3AAndroid%2Fmedia")
                } else {
                    // Android 10 and below: Open root storage
                    Uri.parse("content://com.android.externalstorage.documents/document/primary%3A")
                }
                intent.putExtra(DocumentsContract.EXTRA_INITIAL_URI, initialUri)
            }

            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            intent.addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            intent.addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
            intent.addFlags(Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)

            startActivityForResult(intent, PICK_BUSINESS_FOLDER_REQUEST)
        } catch (e: Exception) {
            e.printStackTrace()
            pendingResult?.error("ERROR", "Failed to open: ${e.message}", null)
            pendingResult = null
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        if (requestCode == PICK_FOLDER_REQUEST || requestCode == PICK_BUSINESS_FOLDER_REQUEST) {
            if (resultCode == RESULT_OK) {
                data?.data?.let { uri ->
                    try {
                        val takeFlags = Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                        contentResolver.takePersistableUriPermission(uri, takeFlags)

                        pendingResult?.success(uri.toString())
                    } catch (e: Exception) {
                        e.printStackTrace()
                        pendingResult?.error("ERROR", "Permission failed: ${e.message}", null)
                    }
                } ?: run {
                    pendingResult?.error("ERROR", "No folder selected", null)
                }
            } else {
                pendingResult?.error("CANCELLED", "User cancelled", null)
            }
            pendingResult = null
        }
    }

    private fun takePersistableUriPermission(uriString: String) {
        try {
            val uri = Uri.parse(uriString)
            val takeFlags = Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            contentResolver.takePersistableUriPermission(uri, takeFlags)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun readFileBytesFromUri(uriString: String): ByteArray? {
        return try {
            val uri = Uri.parse(uriString)
            contentResolver.openInputStream(uri)?.use { inputStream ->
                val buffer = ByteArrayOutputStream()
                val data = ByteArray(16384)
                var count: Int
                while (inputStream.read(data, 0, data.size).also { count = it } != -1) {
                    buffer.write(data, 0, count)
                }
                buffer.toByteArray()
            }
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }

    private fun getVideoThumbnailFromUri(uriString: String): ByteArray? {
        var retriever: MediaMetadataRetriever? = null
        return try {
            retriever = MediaMetadataRetriever()
            val uri = Uri.parse(uriString)
            retriever.setDataSource(context, uri)

            val bitmap = retriever.getFrameAtTime(1000000, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)

            bitmap?.let {
                val stream = ByteArrayOutputStream()
                it.compress(Bitmap.CompressFormat.JPEG, 85, stream)
                val byteArray = stream.toByteArray()
                it.recycle()
                byteArray
            }
        } catch (e: Exception) {
            e.printStackTrace()
            null
        } finally {
            try {
                retriever?.release()
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    // NOW ACCEPTS isBusiness PARAMETER
    private fun getStatusFilesFromTreeUri(uriString: String, isBusiness: Boolean): List<Map<String, Any>> {
        val files = mutableListOf<Map<String, Any>>()

        try {
            val treeUri = Uri.parse(uriString)
            val rootDocumentFile = DocumentFile.fromTreeUri(this, treeUri) ?: return files

            // Check if root is already .Statuses folder
            val statusFolder = if (rootDocumentFile.name == ".Statuses" ||
                rootDocumentFile.uri.toString().contains(".Statuses")) {
                rootDocumentFile
            } else {
                // Use appropriate function based on WhatsApp type
                if (isBusiness) {
                    findBusinessStatusFolder(rootDocumentFile)
                } else {
                    findRegularStatusFolder(rootDocumentFile)
                }
            }

            statusFolder?.listFiles()?.forEach { file ->
                if (file.isFile && file.name != ".nomedia" && !file.name.isNullOrEmpty() &&
                    !file.name!!.startsWith(".")) {
                    files.add(mapOf(
                        "name" to file.name!!,
                        "uri" to file.uri.toString(),
                        "type" to (file.type ?: getMimeTypeFromName(file.name!!)),
                        "size" to file.length(),
                        "lastModified" to file.lastModified()
                    ))
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }

        return files
    }

    private fun getMimeTypeFromName(fileName: String): String {
        return when {
            fileName.endsWith(".jpg", ignoreCase = true) ||
                    fileName.endsWith(".jpeg", ignoreCase = true) -> "image/jpeg"
            fileName.endsWith(".png", ignoreCase = true) -> "image/png"
            fileName.endsWith(".gif", ignoreCase = true) -> "image/gif"
            fileName.endsWith(".webp", ignoreCase = true) -> "image/webp"
            fileName.endsWith(".mp4", ignoreCase = true) -> "video/mp4"
            fileName.endsWith(".3gp", ignoreCase = true) -> "video/3gp"
            fileName.endsWith(".mkv", ignoreCase = true) -> "video/mkv"
            else -> "application/octet-stream"
        }
    }

    // SEPARATE FUNCTION FOR REGULAR WHATSAPP (com.whatsapp)
    private fun findRegularStatusFolder(rootFolder: DocumentFile): DocumentFile? {
        try {
            // Case 1: Root is already .Statuses folder
            if (rootFolder.name == ".Statuses") {
                return rootFolder
            }

            // Case 2: Root is Media folder, look for .Statuses
            if (rootFolder.name == "Media") {
                val statusFolder = rootFolder.findFile(".Statuses")
                if (statusFolder != null) return statusFolder
            }

            // Case 3: Root is com.whatsapp folder (Android 11+)
            if (rootFolder.name == "com.whatsapp") {
                // Look for WhatsApp/Media/.Statuses
                val whatsappFolder = rootFolder.findFile("WhatsApp")
                val mediaFolder = whatsappFolder?.findFile("Media")
                val statusFolder = mediaFolder?.findFile(".Statuses")
                if (statusFolder != null) return statusFolder
            }

            // Case 4: Root is WhatsApp folder (Android 10 and below)
            if (rootFolder.name == "WhatsApp") {
                val mediaFolder = rootFolder.findFile("Media")
                val statusFolder = mediaFolder?.findFile(".Statuses")
                if (statusFolder != null) return statusFolder
            }

            // Case 5: Search for WhatsApp folder in root
            var whatsappFolder = rootFolder.findFile("WhatsApp")
            if (whatsappFolder != null) {
                val mediaFolder = whatsappFolder.findFile("Media")
                val statusFolder = mediaFolder?.findFile(".Statuses")
                if (statusFolder != null) return statusFolder
            }

            // Case 6: Check if root has com.whatsapp folder
            val comWhatsapp = rootFolder.findFile("com.whatsapp")
            if (comWhatsapp != null) {
                whatsappFolder = comWhatsapp.findFile("WhatsApp")
                val mediaFolder = whatsappFolder?.findFile("Media")
                val statusFolder = mediaFolder?.findFile(".Statuses")
                if (statusFolder != null) return statusFolder
            }

            return null

        } catch (e: Exception) {
            e.printStackTrace()
            return null
        }
    }

    // SEPARATE FUNCTION FOR BUSINESS WHATSAPP (com.whatsapp.w4b)
    private fun findBusinessStatusFolder(rootFolder: DocumentFile): DocumentFile? {
        try {
            // Case 1: Root is already .Statuses folder
            if (rootFolder.name == ".Statuses") {
                return rootFolder
            }

            // Case 2: Root is Media folder, look for .Statuses
            if (rootFolder.name == "Media") {
                val statusFolder = rootFolder.findFile(".Statuses")
                if (statusFolder != null) return statusFolder
            }

            // Case 3: Root is com.whatsapp.w4b folder (Android 11+)
            if (rootFolder.name == "com.whatsapp.w4b") {
                // Try both "WhatsApp Business" and "WhatsApp" folder names
                var whatsappFolder = rootFolder.findFile("WhatsApp Business")
                if (whatsappFolder == null) {
                    whatsappFolder = rootFolder.findFile("WhatsApp")
                }
                val mediaFolder = whatsappFolder?.findFile("Media")
                val statusFolder = mediaFolder?.findFile(".Statuses")
                if (statusFolder != null) return statusFolder
            }

            // Case 4: Root is WhatsApp Business folder (Android 10 and below)
            if (rootFolder.name == "WhatsApp Business") {
                val mediaFolder = rootFolder.findFile("Media")
                val statusFolder = mediaFolder?.findFile(".Statuses")
                if (statusFolder != null) return statusFolder
            }

            // Case 5: Search for WhatsApp Business folder in root
            var whatsappFolder = rootFolder.findFile("WhatsApp Business")
            if (whatsappFolder != null) {
                val mediaFolder = whatsappFolder.findFile("Media")
                val statusFolder = mediaFolder?.findFile(".Statuses")
                if (statusFolder != null) return statusFolder
            }

            // Case 6: Check if root has com.whatsapp.w4b folder
            val comWhatsappBusiness = rootFolder.findFile("com.whatsapp.w4b")
            if (comWhatsappBusiness != null) {
                whatsappFolder = comWhatsappBusiness.findFile("WhatsApp Business")
                    ?: comWhatsappBusiness.findFile("WhatsApp")
                val mediaFolder = whatsappFolder?.findFile("Media")
                val statusFolder = mediaFolder?.findFile(".Statuses")
                if (statusFolder != null) return statusFolder
            }

            return null

        } catch (e: Exception) {
            e.printStackTrace()
            return null
        }
    }
}
