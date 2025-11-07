import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class Uploader {
  final _supabase = Supabase.instance.client;

  Future<Map<String, dynamic>> _getPresignedUrl({
    required String folder,
    required String fileName,
    required String contentType,
  }) async {
    final res = await _supabase.functions.invoke(
      'sign-s3',
      body: {
        'folder': folder,
        'fileName': fileName,
        'contentType': contentType,
      },
    );
    return res.data as Map<String, dynamic>;
  }

  Future<String> uploadImageToS3(File file, {required String folder}) async {
    final fileName = file.path.split('/').last;
    final contentType = 'image/${fileName.toLowerCase().endsWith('png') ? 'png' : 'jpeg'}';

    final sig = await _getPresignedUrl(
      folder: folder,
      fileName: fileName,
      contentType: contentType,
    );

    final uploadUrl = sig['uploadUrl'] as String;
    final publicUrl = sig['publicUrl'] as String;

    final bytes = await file.readAsBytes();
    final put = await http.put(Uri.parse(uploadUrl),
        headers: {'Content-Type': contentType},
        body: bytes);

    if (put.statusCode == 200) {
      return publicUrl; // ✅ S3 public image URL
    } else {
      throw Exception('S3 Upload failed: ${put.statusCode} ${put.body}');
    }
  }

  Future<String> uploadAudioToS3(File file, {required String folder}) async {
  final fileName = file.path.split('/').last;
  final ext = fileName.split('.').last.toLowerCase();

  final contentType = "audio/$ext";

  final sig = await _getPresignedUrl(
    folder: folder,
    fileName: fileName,
    contentType: contentType,
  );

  final uploadUrl = sig['uploadUrl'] as String;
  final publicUrl = sig['publicUrl'] as String;

  final bytes = await file.readAsBytes();
  final put = await http.put(Uri.parse(uploadUrl),
      headers: {'Content-Type': contentType},
      body: bytes);

  if (put.statusCode == 200) {
    return publicUrl;
  } else {
    throw Exception("Audio Upload failed: ${put.body}");
  }
}


  Future<void> createStory({
    required String title,
    String? subtitle,
    required String category,
    int? ranking,
    required String imageUrl,
  }) async {
    await _supabase.from('stories').insert({
      'title': title,
      'subtitle': subtitle,
      'category': category,
      'ranking': ranking,
      'image_url': imageUrl,
    });
  }
}

class UploadStoryButton extends StatefulWidget {
  const UploadStoryButton({super.key});

  @override
  State<UploadStoryButton> createState() => _UploadStoryButtonState();
}

class _UploadStoryButtonState extends State<UploadStoryButton> {
  final _uploader = Uploader();
  bool _loading = false;

  Future<void> _pickAndUpload(String category, {int? ranking}) async {
    try {
      setState(() => _loading = true);
      final picker = ImagePicker();
      final x = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (x == null) return;

      final file = File(x.path);
      final imageUrl = await _uploader.uploadImageToS3(file, folder: category);

      await _uploader.createStory(
        title: "Lorem Ipsum",
        subtitle: "dolor sit amet",
        category: category,
        ranking: ranking,
        imageUrl: imageUrl,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Uploaded & saved ✅')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: _loading ? null : () => _pickAndUpload('daily_recommended'),
      icon: const Icon(Icons.cloud_upload),
      label: Text(_loading ? 'Uploading...' : 'Upload Daily Recommended'),
    );
  }
}
