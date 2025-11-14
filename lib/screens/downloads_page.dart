import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../audio/audio_player_page.dart';

class DownloadsPage extends StatefulWidget {
  const DownloadsPage({super.key});

  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> {
  List<Map<String, dynamic>> downloads = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDownloads();
  }

  Future<void> _loadDownloads() async {
    setState(() => isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList("downloads") ?? [];

      downloads = list.map((e) => jsonDecode(e) as Map<String, dynamic>).where((
        item,
      ) {
        final path = item["local_path"] ?? '';
        return path.isNotEmpty && File(path).existsSync();
      }).toList();

      // Clean invalid
      final valid = downloads.map((e) => jsonEncode(e)).toList();
      await prefs.setStringList("downloads", valid);
    } catch (_) {}

    if (mounted) setState(() => isLoading = false);
  }

  Future<void> _deleteDownload(String id, String path) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> list = prefs.getStringList("downloads") ?? [];

    list.removeWhere((e) => jsonDecode(e)["id"].toString() == id.toString());
    await prefs.setStringList("downloads", list);

    final file = File(path);
    if (file.existsSync()) await file.delete();

    _loadDownloads();
  }

  Future<void> _deleteAllDownloads() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove("downloads");

    for (var item in downloads) {
      final f = File(item["local_path"]);
      if (f.existsSync()) await f.delete();
    }

    _loadDownloads();
  }

  String _fileSize(String path) {
    try {
      final b = File(path).lengthSync();
      return "${(b / (1024 * 1024)).toStringAsFixed(1)} MB";
    } catch (_) {
      return "0 MB";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff8f8f8),

      appBar: AppBar(
        title: const Text(
          "Downloads",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          if (downloads.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: _deleteAllDownloads,
            ),
        ],
      ),

      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : downloads.isEmpty
          ? _emptyView()
          : _downloadsList(),
    );
  }

  // -------------------- EMPTY UI --------------------
  Widget _emptyView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.06),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.download_for_offline_outlined,
              size: 80,
              color: Colors.black45,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            "No Downloads Yet",
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            "Download stories for offline listening",
            style: TextStyle(fontSize: 14, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  // -------------------- LIST UI --------------------
  Widget _downloadsList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      itemCount: downloads.length,
      itemBuilder: (context, index) {
        final item = downloads[index];
        final title = item["title"];
        final imageUrl = item["image_url"];
        final path = item["local_path"];
        final size = _fileSize(path);

        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            contentPadding: const EdgeInsets.symmetric(
              vertical: 12,
              horizontal: 12,
            ),

            leading: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                width: 60,
                height: 60,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(
                  width: 60,
                  height: 60,
                  color: Colors.grey.shade300,
                  child: const Icon(Icons.music_note, color: Colors.black45),
                ),
              ),
            ),

            title: Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
                color: Colors.black87,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),

            subtitle: Text(
              "Downloaded • $size",
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),

            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: () => _deleteDownload(item["id"].toString(), path),
            ),

            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AudioPlayerPage(
                    story: {
                      "id": item["id"],
                      "title": item["title"],
                      "image_url": item["image_url"],
                      "audio_url": item["local_path"],
                      "author": item["author"] ?? "Unknown",
                      "genre": item["genre"] ?? "Story",
                    },
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
