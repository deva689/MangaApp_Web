import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:manga/services/stories_repo.dart';

class BrowseGenrePage extends StatefulWidget {
  final String genre;

  const BrowseGenrePage({super.key, required this.genre});

  @override
  State<BrowseGenrePage> createState() => _GenreStoriesPageState();
}

class _GenreStoriesPageState extends State<BrowseGenrePage> {
  final repo = StoriesRepo();
  late Future<List<Map<String, dynamic>>> genreStoriesF;

  @override
  void initState() {
    super.initState();
    genreStoriesF = repo.byGenre(widget.genre);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.genre),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: FutureBuilder(
        future: genreStoriesF,
        builder: (_, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final items = snap.data!;
          if (items.isEmpty) {
            return const Center(child: Text("No stories available 🥺"));
          }

          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (_, i) {
              final it = items[i];
              return ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: it['image_url'],
                    width: 60,
                    height: 60,
                    fit: BoxFit.cover,
                  ),
                ),
                title: Text(it['title']),
                subtitle: Text(it['author'] ?? ""),
              );
            },
          );
        },
      ),
    );
  }
}
