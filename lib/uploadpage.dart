import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

class UploadStoryPage extends StatefulWidget {
  const UploadStoryPage({super.key});

  @override
  State<UploadStoryPage> createState() => _UploadStoryPageState();
}

class _UploadStoryPageState extends State<UploadStoryPage> {
  File? imageFile;
  File? audioFile;
  bool uploading = false;
  String? uploadedImageUrl;
  String? uploadedAudioUrl;

  Future<void> pickImage() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result != null) {
      setState(() => imageFile = File(result.files.single.path!));
    }
  }

  Future<void> pickAudio() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.audio);
    if (result != null) {
      setState(() => audioFile = File(result.files.single.path!));
    }
  }

  String getMime(File file, String type) {
    String ext = file.path.split('.').last.toLowerCase();
    if (type == "image") {
      if (ext == "png") return "image/png";
      return "image/jpeg";
    } else {
      if (ext == "wav") return "audio/wav";
      if (ext == "aac") return "audio/aac";
      return "audio/mpeg";
    }
  }

  Future<void> uploadFile(File file, String type) async {
    setState(() => uploading = true);

    // ✅ Request Pre-signed URL from backend
    final resp = await http.post(
      Uri.parse("http://192.168.1.8:5000/get-presigned-url"),
      body: {"file_type": type},
    );

    if (resp.statusCode != 200) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Failed to get upload URL")));
      setState(() => uploading = false);
      return;
    }

    final data = jsonDecode(resp.body);
    final uploadUrl = data["upload_url"];
    final publicUrl = data["public_url"];

    final contentType = getMime(file, type);

    // ✅ Upload File to AWS S3
    final uploadResp = await http.put(
      Uri.parse(uploadUrl),
      body: file.readAsBytesSync(),
      headers: {"Content-Type": "application/octet-stream"},
    );

    print("UPLOAD STATUS: ${uploadResp.statusCode}");
    print("UPLOAD BODY: ${uploadResp.body}");
    print("UPLOAD HEADERS: ${uploadResp.headers}");

    setState(() => uploading = false);

    if (uploadResp.statusCode == 200) {
      setState(() {
        if (type == "image") uploadedImageUrl = publicUrl;
        if (type == "audio") uploadedAudioUrl = publicUrl;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("$type uploaded successfully ✅")));
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Failed to upload $type ❌")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Upload Story")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ElevatedButton(
              onPressed: pickImage,
              child: const Text("Pick Image"),
            ),
            if (imageFile != null) Text(imageFile!.path.split('/').last),

            ElevatedButton(
              onPressed: pickAudio,
              child: const Text("Pick Audio"),
            ),
            if (audioFile != null) Text(audioFile!.path.split('/').last),

            const SizedBox(height: 20),

            uploading
                ? const CircularProgressIndicator()
                : Column(
                    children: [
                      if (imageFile != null)
                        ElevatedButton(
                          onPressed: () => uploadFile(imageFile!, "image"),
                          child: const Text("Upload Image"),
                        ),
                      if (audioFile != null)
                        ElevatedButton(
                          onPressed: () => uploadFile(audioFile!, "audio"),
                          child: const Text("Upload Audio"),
                        ),
                    ],
                  ),

            const SizedBox(height: 20),

            // ✅ Show uploaded file URLs
            if (uploadedImageUrl != null) Text("Image URL: $uploadedImageUrl"),
            if (uploadedAudioUrl != null) Text("Audio URL: $uploadedAudioUrl"),
          ],
        ),
      ),
    );
  }
}
