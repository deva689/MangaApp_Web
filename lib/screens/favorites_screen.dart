import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  int selectedTab = 0; // 0 = Book, 1 = Author, 2 = Narrator

  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> favoriteBooks = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        setState(() => loading = false);
        return;
      }

      print("user id is : ${user.id}");

      final pref = await supabase
          .from('user_preferences')
          .select('favourites')
          .eq('user_id', user.id)
          .maybeSingle();

      print("pref is : $pref");

      final favIds = pref?['favourites'] != null
          ? List<String>.from(pref?['favourites'])
          : <String>[];

      if (favIds.isEmpty) {
        print("No favorites yet");
        setState(() => loading = false);
        return;
      }

      print("Favorite IDs: $favIds");

      final stories = await supabase
          .from('stories')
          .select('*')
          .inFilter('id', favIds);

      print("Fetched stories: $stories");

      setState(() {
        favoriteBooks = List<Map<String, dynamic>>.from(stories);
        loading = false;
      });
    } catch (e) {
      debugPrint("❌ Error loading favorites: $e");
      setState(() => loading = false);
    }
  }

  Future<void> _removeFavorite(int id) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      await supabase.rpc(
        'remove_favourite',
        params: {"uid": user.id, "story_id": id},
      );

      favoriteBooks.removeWhere((item) => item["id"] == id);
      setState(() {});
    } catch (e) {
      debugPrint("⚠ Error removing favorite: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,

      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ✅ Title
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                "Favorites",
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
              ),
            ),

            // ✅ Tabs
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _tabButton("Book", 0),
                  const SizedBox(width: 16),
                  _tabButton("Author", 1),
                  const SizedBox(width: 16),
                  _tabButton("Narrator", 2),
                ],
              ),
            ),

            const SizedBox(height: 10),

            Expanded(
              child: selectedTab == 0 ? _buildBookList() : _buildEmptyTab(),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- TAB BUTTON ----------------
  Widget _tabButton(String text, int index) {
    bool selected = selectedTab == index;

    return GestureDetector(
      onTap: () => setState(() => selectedTab = index),
      child: Column(
        children: [
          Text(
            text,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: selected ? Colors.black : Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 3),
          if (selected) Container(height: 2, width: 40, color: Colors.black),
        ],
      ),
    );
  }

  // ---------------- BOOK LIST ----------------
  Widget _buildBookList() {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (favoriteBooks.isEmpty) {
      return _buildEmptyTab(showForBooks: true);
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        const SizedBox(height: 10),

        ...favoriteBooks.map((item) {
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: CachedNetworkImage(
                    imageUrl: item["image_url"] ?? "",
                    width: 55,
                    height: 55,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 12),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item["title"] ?? "",
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item["author"] ?? "",
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),

                PopupMenuButton(
                  icon: const Icon(Icons.more_vert, size: 22),
                  onSelected: (value) {
                    if (value == "remove") {
                      _removeFavorite(item["id"]);
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: "remove", child: Text("Remove")),
                  ],
                ),
              ],
            ),
          );
        }).toList(),

        const SizedBox(height: 15),

        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Row(
            children: [
              const Icon(Icons.add_circle_outline, size: 20),
              const SizedBox(width: 8),
              const Text(
                "Explore discover",
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),
      ],
    );
  }

  // ---------------- EMPTY TAB ----------------
  Widget _buildEmptyTab({bool showForBooks = false}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            showForBooks
                ? "Your favorite books will appear here"
                : selectedTab == 1
                ? "Your Author will appear here"
                : "Your Narrator will appear here",
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "Explore and save your favorites",
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 15),
          ElevatedButton(
            onPressed: () => Placeholder(),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: Colors.black),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
            ),
            child: const Text("Explore discover"),
          ),
        ],
      ),
    );
  }
}
