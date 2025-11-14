import 'dart:async';
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:manga/screens/book_detail_page.dart';
import 'package:manga/services/stories_repo.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:supabase_flutter/supabase_flutter.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final repo = StoriesRepo();
  bool isSearching = false;

  List<Map<String, dynamic>> searchResults = [];
  List<Map<String, dynamic>> recentStories = [];
  List<Map<String, dynamic>> smartSuggestions = [];
  List<Map<String, dynamic>> genreTopics = [];
  List<Map<String, dynamic>> newReleases = [];
  List<Map<String, dynamic>> curatedBooks = [];

  bool loadingGenres = true;
  bool loadingNewReleases = true;
  bool loadingCurated = true;
  bool isLoading = false;

  Timer? _debounce;
  bool showAllRecent = false;

  late stt.SpeechToText _speech;
  bool _speechAvailable = false;
  bool _isListening = false;

  @override
  void initState() {
    super.initState();
    _initPrefs();
    _initSpeech();
    _initSmartSuggestions();
    _getGenres();
    _getNewReleases();
    _getCuratedBooks();
  }

  // ------------------ DATA LOADERS ------------------

  Future<void> _initPrefs() async {
    final sp = await SharedPreferences.getInstance();
    final saved = sp.getStringList('recent_stories') ?? [];
    setState(() {
      recentStories = saved
          .map((e) => jsonDecode(e) as Map<String, dynamic>)
          .toList();
    });
  }

  Future<void> _saveRecents() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setStringList(
      'recent_stories',
      recentStories.map((e) => jsonEncode(e)).toList(),
    );
  }

  Future<void> _initSmartSuggestions() async {
    try {
      final rows = await repo.byCategory("suggested");
      setState(() => smartSuggestions = rows.take(6).toList());
    } catch (_) {}
  }

  Future<void> _initSpeech() async {
    _speech = stt.SpeechToText();
    _speechAvailable = await _speech.initialize();
    setState(() {});
  }

  Future<void> _getGenres() async {
    try {
      final res = await Supabase.instance.client.from('topics').select();
      setState(() {
        genreTopics = List<Map<String, dynamic>>.from(res);
        loadingGenres = false;
      });
    } catch (_) {
      setState(() => loadingGenres = false);
    }
  }

  Future<void> _getNewReleases() async {
    try {
      final res = await Supabase.instance.client
          .from('stories')
          .select()
          .order('created_at', ascending: false)
          .limit(12);

      if (!mounted) return; // ✅ Prevents setState after dispose

      setState(() {
        newReleases = List<Map<String, dynamic>>.from(res);
        loadingNewReleases = false;
      });
    } catch (e) {
      if (!mounted) return; // ✅ Still prevent in catch block
      setState(() => loadingNewReleases = false);
    }
  }

  Future<void> _getCuratedBooks() async {
    try {
      final res = await Supabase.instance.client
          .from('stories')
          .select('id,title,author,image_url,rating')
          .order('rating', ascending: false)
          .limit(12);

      setState(() {
        curatedBooks = List<Map<String, dynamic>>.from(res);
        loadingCurated = false;
      });
    } catch (_) {
      setState(() => loadingCurated = false);
    }
  }

  // ------------------ SEARCH LOGIC ------------------

  void _debouncedRun(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _runSearch(q));
  }

  Future<void> _runSearch(String query) async {
    setState(() {
      isLoading = true;
      searchResults = [];
    });

    try {
      searchResults = await repo.searchStories(query.trim());
    } catch (_) {}

    setState(() => isLoading = false);
  }

  void _addToRecent(Map<String, dynamic> story) {
    recentStories.removeWhere((e) => e['id'] == story['id']);
    recentStories.insert(0, story);
    if (recentStories.length > 50) recentStories.removeLast();
    _saveRecents();
    setState(() {});
  }

  Widget _chartCard(String title, String imagePath) {
    return GestureDetector(
      onTap: () {
        setState(() => isSearching = true);
        _runSearch(title);
      },
      child: Container(
        width: 210,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          image: DecorationImage(
            image: AssetImage(imagePath),
            fit: BoxFit.cover,
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: Colors.black.withOpacity(0.35),
          ),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _speech.stop();
    super.dispose();
  }

  // ----------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: isSearching ? _buildSearchUI() : _buildDiscoverUI(),
      ),
    );
  }

  // ------------------ SHIMMER WIDGETS ------------------

  Widget _shimmerHorizontalBooks() {
    return SizedBox(
      height: 260,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: 6,
        itemBuilder: (_, __) {
          return IntrinsicHeight(
            child: Container(
              width: 160,
              margin: const EdgeInsets.only(right: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Shimmer.fromColors(
                      baseColor: Colors.grey.shade300,
                      highlightColor: Colors.grey.shade100,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Shimmer.fromColors(
                    baseColor: Colors.grey.shade300,
                    highlightColor: Colors.grey.shade100,
                    child: Container(
                      height: 14,
                      width: double.infinity,
                      margin: const EdgeInsets.only(top: 8),
                      color: Colors.white,
                    ),
                  ),
                  Shimmer.fromColors(
                    baseColor: Colors.grey.shade300,
                    highlightColor: Colors.grey.shade100,
                    child: Container(
                      height: 12,
                      width: 100,
                      margin: const EdgeInsets.only(top: 4),
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _shimmerList() => Column(
    children: List.generate(
      6,
      (i) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Shimmer.fromColors(
              baseColor: Colors.grey.shade300,
              highlightColor: Colors.grey.shade100,
              child: Container(width: 55, height: 55, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Shimmer.fromColors(
                baseColor: Colors.grey.shade300,
                highlightColor: Colors.grey.shade100,
                child: Container(height: 14, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  // ------------------ DISCOVER SCREEN UI ------------------

  Widget _buildDiscoverUI() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        GestureDetector(
          onTap: () => setState(() => isSearching = true),
          child: _searchBoxUIClosed(),
        ),

        const SizedBox(height: 20),

        SizedBox(
          height: MediaQuery.of(context).size.height * .12,
          child: loadingGenres
              ? _shimmerHorizontalBooks()
              : ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: genreTopics.length,
                  itemBuilder: (_, i) {
                    final g = genreTopics[i];
                    return GestureDetector(
                      onTap: () {
                        setState(() => isSearching = true);
                        _runSearch(g["name"]);
                      },
                      child: _genreCard(g),
                    );
                  },
                ),
        ),
        // ⭐ Charts Section
        const SizedBox(height: 25),
        _sectionTitle("Charts"),
        const SizedBox(height: 15),

        SizedBox(
          height: 150,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _chartCard("Top Trending 20", "assets/charts/top_trending.png"),
              const SizedBox(width: 14),
              _chartCard("New Release 20", "assets/charts/new_release.png"),
              const SizedBox(width: 14),
              _chartCard("Top Free 20", "assets/charts/top_free.png"),
              const SizedBox(width: 14),
              _chartCard("Top Artist 20", "assets/charts/top_artist.png"),
            ],
          ),
        ),

        const SizedBox(height: 20),
        _sectionTitle("Popular & New Releases"),
        const SizedBox(height: 15),
        loadingNewReleases
            ? _shimmerHorizontalBooks()
            : _bookHorizontal(newReleases),

        const SizedBox(height: 12),
        _sectionTitle("Most Rated Collections"),
        const SizedBox(height: 15),
        loadingCurated
            ? _shimmerHorizontalBooks()
            : _bookHorizontal(curatedBooks),

        // const SizedBox(height: 25),
        // _sectionTitle("Explore by Character"),
        // const SizedBox(height: 15),
        // loadingNewReleases
        //     ? _shimmerHorizontalBooks()
        //     : _bookHorizontal(newReleases),
      ],
    );
  }

  // ------------------ SEARCH UI ------------------

  Widget _buildSearchUI() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.all(12), child: _searchBoxUIOpen()),

        Expanded(
          child: isLoading
              ? _shimmerList()
              : (searchResults.isNotEmpty && _searchCtrl.text.isNotEmpty)
              ? ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: searchResults.length,
                  itemBuilder: (_, i) {
                    final s = searchResults[i];
                    return ListTile(
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CachedNetworkImage(
                          imageUrl: s["image_url"],
                          width: 45,
                          height: 45,
                          fit: BoxFit.cover,
                        ),
                      ),
                      title: Text(
                        s["title"],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        s["author"] ?? "",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () {
                        _addToRecent(s);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => BookDetailPage(story: s),
                          ),
                        );
                      },
                    );
                  },
                )
              : _buildSuggestionsAndRecent(),
        ),
      ],
    );
  }

  Widget _buildSuggestionsAndRecent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // _sectionTitle("Searches"),
          // const SizedBox(height: 10),

          // Column(
          //   children: smartSuggestions.take(4).map((s) {
          //     return Container(
          //       padding: const EdgeInsets.symmetric(vertical: 12),
          //       child: Row(
          //         mainAxisAlignment: MainAxisAlignment.spaceBetween,
          //         children: [
          //           Expanded(
          //             child: GestureDetector(
          //               onTap: () {
          //                 _searchCtrl.text = s["title"];
          //                 _runSearch(s["title"]);
          //               },
          //               child: Text(
          //                 s["title"] ?? "",
          //                 style: const TextStyle(
          //                   fontSize: 15,
          //                   fontWeight: FontWeight.w600,
          //                   color: Colors.black87,
          //                 ),
          //               ),
          //             ),
          //           ),
          //           PopupMenuButton<String>(
          //             icon: const Icon(
          //               Icons.more_vert,
          //               size: 22,
          //               color: Colors.black87,
          //             ),
          //             offset: const Offset(0, 35),
          //             onSelected: (value) {
          //               if (value == "search") {
          //                 _searchCtrl.text = s["title"];
          //                 _runSearch(s["title"]);
          //               } else if (value == "remove") {
          //                 setState(() => smartSuggestions.remove(s));
          //               }
          //             },
          //             itemBuilder: (context) => const [
          //               PopupMenuItem(
          //                 value: "search",
          //                 child: Text("Search this"),
          //               ),
          //               PopupMenuItem(value: "remove", child: Text("Remove")),
          //             ],
          //           ),
          //         ],
          //       ),
          //     );
          //   }).toList(),
          // ),

          // const SizedBox(height: 25),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _sectionTitle("Recent Searches"),
              if (recentStories.length > 3)
                GestureDetector(
                  onTap: () => setState(() => showAllRecent = true),
                  child: const Text(
                    "View all",
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),

          if (recentStories.isEmpty)
            _emptyRecentUI()
          else
            Column(
              children: [
                ...recentStories
                    .take(showAllRecent ? recentStories.length : 3)
                    .map((s) => _recentTile(s)),

                if (recentStories.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      setState(() => recentStories.clear());
                      _saveRecents();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        "Clear recent searches",
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.red.shade600,
                        ),
                      ),
                    ),
                  ),

                if (showAllRecent)
                  GestureDetector(
                    onTap: () => setState(() => showAllRecent = false),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        "Show less",
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  // ------------------ SEARCH BOX STATES ------------------

  Widget _searchBoxUIClosed() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: const [
              Expanded(
                child: Text(
                  "Search title, author or book",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black54,
                  ),
                ),
              ),
              Icon(Icons.search, size: 22, color: Colors.black87),
            ],
          ),
        ),
        Container(
          height: 1,
          margin: const EdgeInsets.symmetric(horizontal: 12),
          color: Colors.grey.shade300,
        ),
      ],
    );
  }

  Widget _searchBoxUIOpen() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                onPressed: () {
                  setState(() {
                    _searchCtrl.clear();
                    isSearching = false;
                    searchResults.clear();
                  });
                },
              ),
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  autofocus: true,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                  decoration: const InputDecoration(
                    hintText: "Search title, author or book",
                    hintStyle: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black54,
                    ),
                    border: InputBorder.none,
                  ),
                  onChanged: (v) {
                    if (v.length > 2) _debouncedRun(v);
                    setState(() {});
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.search, size: 24, color: Colors.black87),
                onPressed: () {
                  if (_searchCtrl.text.trim().isNotEmpty) {
                    _runSearch(_searchCtrl.text.trim());
                  }
                },
              ),
            ],
          ),
        ),
        Container(
          height: 1,
          margin: const EdgeInsets.symmetric(horizontal: 10),
          color: Colors.grey.shade300,
        ),
      ],
    );
  }

  // ------------------ COMMON WIDGETS ------------------

  Widget _bookHorizontal(List data) {
    return SizedBox(
      height: 230,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: data.length,
        itemBuilder: (_, i) {
          final d = data[i];
          return GestureDetector(
            onTap: () {
              _addToRecent(d);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => BookDetailPage(story: d)),
              );
            },
            child: _bookCard(d),
          );
        },
      ),
    );
  }

  Widget _recentTile(Map<String, dynamic> s) {
    return Dismissible(
      key: ValueKey(s["id"]),
      direction: DismissDirection.endToStart,
      onDismissed: (_) {
        setState(() => recentStories.remove(s));
        _saveRecents();
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red.shade400,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CachedNetworkImage(
            imageUrl: s["image_url"],
            width: 45,
            height: 45,
            fit: BoxFit.cover,
          ),
        ),
        title: Text(
          s["title"],
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          s["author"] ?? "",
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        trailing: GestureDetector(
          onTap: () {
            setState(() => recentStories.remove(s));
            _saveRecents();
          },
          child: const Icon(Icons.close, size: 18, color: Colors.black54),
        ),
        onTap: () {
          _addToRecent(s);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => BookDetailPage(story: s)),
          );
        },
      ),
    );
  }

  Widget _emptyRecentUI() {
    return SizedBox(
      width: double.infinity,
      height: 350, // adjust as needed
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history, // ⏳ Change to any you like (search/history)
            size: 85, // 🔥 Big icon
            color: Colors.grey.withOpacity(0.5),
          ),
          const SizedBox(height: 18),
          const Text(
            "No recent searches",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "Start searching to see history here",
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _bookCard(Map<String, dynamic> d) {
    return Container(
      width: 140,
      margin: const EdgeInsets.only(right: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CachedNetworkImage(
              imageUrl: d["image_url"],
              width: 140,
              height: 170,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            d["title"],
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          Text(
            d["author"] ?? "Unknown",
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _genreCard(Map<String, dynamic> g) {
    return Container(
      width: 110,
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        image: DecorationImage(
          image: CachedNetworkImageProvider(g["image_url"]),
          fit: BoxFit.cover,
        ),
      ),
      child: Align(
        alignment: Alignment.topLeft,
        child: Container(
          margin: const EdgeInsets.all(6),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black45,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            g["name"],
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(
    text,
    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
  );
}
