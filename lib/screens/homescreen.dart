import 'package:cached_network_image/cached_network_image.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:manga/screens/book_detail_page.dart';
import 'package:manga/screens/browse_genre.dart';
import 'package:manga/services/stories_repo.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final repo = StoriesRepo();

  late Future<List<Map<String, dynamic>>> dailyF;
  late Future<List<Map<String, dynamic>>> rankingF;
  late Future<List<Map<String, dynamic>>> suggestF;
  late Future<List<Map<String, dynamic>>> allStoriesF;
  late Future<List<Map<String, dynamic>>> top10AudiobooksF;
  late Future<List<Map<String, dynamic>>> recommendedF;
  late Future<List<Map<String, dynamic>>> topicsF;

  late CarouselSliderController _carouselController;
  int _currentPage = 0;
  String? selectedGenre;

  List<String> genres = [];
  bool loadingGenres = true;

  @override
  void initState() {
    super.initState();
    _loadSelectedGenre();
    _initializeFutures();
    _carouselController = CarouselSliderController();
    fetchGenres(); // <--- IMPORTANT ✅
  }

  Future<void> fetchGenres() async {
    final supabase = Supabase.instance.client;

    try {
      final data = await supabase.from("topics").select("name");

      List<String> fetched = data
          .map<String>((e) => e["name"].toString())
          .toList();

      setState(() {
        genres = ["All", ...fetched]; // ✅ prepend "All"
        loadingGenres = false;
      });
    } catch (e) {
      print("Error loading genres: $e");
      setState(() => loadingGenres = false);
    }
  }

  // Load saved genre from SharedPreferences
  Future<void> _loadSelectedGenre() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      selectedGenre = prefs.getString('selected_genre');
    });
  }

  // Save selected genre to SharedPreferences
  Future<void> _saveSelectedGenre(String genre) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_genre', genre);
  }

  void _initializeFutures() {
    dailyF = repo.topStoriesByViews();
    rankingF = _getRankingStoriesByGenre(selectedGenre);
    suggestF = repo.byCategory("suggested");
    allStoriesF = repo.allStories();
    top10AudiobooksF = _getTop10Last24Hours();
    recommendedF = _recommendedStories();
    topicsF = _getTopics();
  }

  // Get topics from database
  Future<List<Map<String, dynamic>>> _getTopics() async {
    final supabase = Supabase.instance.client;
    try {
      final rows = await supabase
          .from("topics")
          .select()
          .order("id", ascending: true);
      return (rows as List).cast<Map<String, dynamic>>();
    } catch (e) {
      print('Error fetching topics: $e');
      return [];
    }
  }

  // Get top 10 audiobooks from last 24 hours
  // ✅ Get top 10 stories by views (NOT created_at)
  Future<List<Map<String, dynamic>>> _getTop10Last24Hours() async {
    try {
      final supabase = Supabase.instance.client;

      final response = await supabase
          .from("stories")
          .select("*")
          .order("views", ascending: false) // ✅ Sort by views
          .limit(10); // ✅ Top 10 only

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print("❌ Error fetching Top 10 stories: $e");
      return [];
    }
  }

  // Custom method to get ranking stories filtered by genre
  Future<List<Map<String, dynamic>>> _getRankingStoriesByGenre(
    String? genre,
  ) async {
    try {
      final allStories = await repo.topStoriesByViews();

      if (genre == null || genre.isEmpty || genre == "All") {
        return allStories; // ✅ "All" returns everything
      }

      return allStories
          .where(
            (story) =>
                (story['genre'] ?? "").toLowerCase() == genre.toLowerCase(),
          )
          .toList();
    } catch (e) {
      print('Error getting ranking stories: $e');
      return [];
    }
  }

  // Get recommended stories based on user preferences
  Future<List<Map<String, dynamic>>> _recommendedStories() async {
    final supabase = Supabase.instance.client;

    try {
      final user = supabase.auth.currentUser;
      if (user == null) return [];

      // get saved genres from user preferences
      final pref = await supabase
          .from("user_preferences")
          .select("genres")
          .eq("user_id", user.id)
          .maybeSingle();

      print("User Pref: $pref");

      if (pref == null || pref["genres"] == null) return [];

      final List<dynamic> selectedGenres = pref["genres"];
      if (selectedGenres.isEmpty) return [];

      print("Selected genres: $selectedGenres");

      // ✅ Exact match to DB values
      final data = await supabase
          .from("stories")
          .select("*")
          .inFilter("genre", selectedGenres)
          .order("views", ascending: false);

      print("Recommended Stories: ${data.length}");

      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      print("Error in recommended stories: $e");
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    const montserrat = "Montserrat";
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final carouselHeight = screenHeight * 0.55;

    return WillPopScope(
      onWillPop: () async {
        SystemNavigator.pop(); // ✅ closes the app on back press (best practice)
        return false; // ✅ prevents navigation to previous login screen
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          automaticallyImplyLeading: false,
          elevation: 0,
          title: Text(
            "Daily Recommended",
            style: TextStyle(
              fontSize: 24,
              fontFamily: montserrat,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            physics: BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ✅ FULL SCREEN RESPONSIVE CAROUSEL WITH SHIMMER
                FutureBuilder(
                  future: dailyF,
                  builder: (_, snap) {
                    if (!snap.hasData) {
                      return _buildCarouselShimmer(carouselHeight, screenWidth);
                    }

                    final items = snap.data!;

                    if (items.isEmpty) {
                      return SizedBox(
                        height: carouselHeight,
                        child: const Center(
                          child: Text('No stories available'),
                        ),
                      );
                    }

                    return Column(
                      children: [
                        CarouselSlider.builder(
                          carouselController: _carouselController,
                          itemCount: items.length,
                          itemBuilder: (_, i, realIndex) {
                            final it = items[i];

                            return GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => BookDetailPage(story: it),
                                  ),
                                );
                              },
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  top: 8,
                                  bottom: 22,
                                ),
                                child: AnimatedScale(
                                  duration: const Duration(milliseconds: 300),
                                  scale: _currentPage == i ? 1.0 : 0.90,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.3),
                                          blurRadius: 10,
                                          spreadRadius: 2,
                                          offset: const Offset(0, 6),
                                        ),
                                      ],
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(7),
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          CachedNetworkImage(
                                            imageUrl: it["image_url"] ?? "",
                                            fit: BoxFit.cover,
                                            errorWidget:
                                                (context, url, error) =>
                                                    Container(
                                                      color: Colors.grey[300],
                                                      child: const Icon(
                                                        Icons.error,
                                                      ),
                                                    ),
                                          ),

                                          // Gradient Overlay
                                          Container(
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                begin: Alignment.bottomCenter,
                                                end: Alignment.topCenter,
                                                colors: [
                                                  Colors.black.withOpacity(
                                                    0.85,
                                                  ),
                                                  Colors.transparent,
                                                ],
                                              ),
                                            ),
                                          ),

                                          // Text section
                                          Padding(
                                            padding: const EdgeInsets.all(20),
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.end,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 12,
                                                        vertical: 6,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.orange,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          30,
                                                        ),
                                                  ),
                                                  child: Text(
                                                    it['genre'] ?? "",
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(height: 12),
                                                Text(
                                                  it['title'] ?? 'Untitled',
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 26,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                const SizedBox(height: 6),
                                                Text(
                                                  it['author'] ??
                                                      "Unknown Author",
                                                  style: TextStyle(
                                                    color: Colors.white
                                                        .withOpacity(0.85),
                                                    fontSize: 15,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                          options: CarouselOptions(
                            height: carouselHeight,
                            viewportFraction: 0.78,
                            enlargeCenterPage: true,
                            autoPlay: true,
                            autoPlayInterval: const Duration(seconds: 4),
                            autoPlayAnimationDuration: const Duration(
                              milliseconds: 800,
                            ),
                            onPageChanged: (index, reason) {
                              setState(() => _currentPage = index);
                            },
                          ),
                        ),

                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(items.length, (i) {
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              height: 6,
                              width: _currentPage == i ? 24 : 8,
                              decoration: BoxDecoration(
                                color: _currentPage == i
                                    ? Colors.blue
                                    : Colors.grey.shade400,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            );
                          }),
                        ),
                        const SizedBox(height: 8),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),

                // _sectionTitle("Top 10 Audiobooks (24 Hours)"),
                FutureBuilder(
                  future: top10AudiobooksF,
                  builder: (_, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return _buildHorizontalShimmer();
                    }

                    if (!snap.hasData || snap.data!.isEmpty) {
                      return const SizedBox(
                        height: 100,
                        child: Center(child: Text('No audiobooks available')),
                      );
                    }
                    final items = snap.data!;

                    return SizedBox(
                      height: 250,
                      child: ListView.builder(
                        padding: const EdgeInsets.only(left: 16),
                        scrollDirection: Axis.horizontal,
                        itemCount: items.length,
                        itemBuilder: (_, i) {
                          final it = items[i];

                          return GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => BookDetailPage(story: it),
                                ),
                              );
                            },
                            child: Container(
                              margin: const EdgeInsets.only(right: 16),
                              width: 150,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Stack(
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: CachedNetworkImage(
                                          imageUrl: it['image_url'],
                                          height: 180,
                                          width: 150,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                      // Stylish large rank number bottom-left corner
                                      Positioned(
                                        bottom: -10,
                                        left: 4,
                                        child: Text(
                                          '${i + 1}',
                                          style: GoogleFonts.bodoniModa(
                                            fontSize: 98,
                                            fontWeight:
                                                FontWeight.w500, // ✅ HERE
                                            height: 1.0,
                                            color: Colors.white.withOpacity(
                                              0.97,
                                            ),
                                            letterSpacing: -3,
                                            shadows: [
                                              Shadow(
                                                color: Colors.black.withOpacity(
                                                  0.6,
                                                ),
                                                blurRadius: 6,
                                                offset: Offset(2, 3),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    it['title'] ?? 'Lorem ipsum',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: Colors.black,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    it['author'] ?? 'Lorem ipsum',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),

                _sectionTitle("Weekly Ranking"),

                const SizedBox(height: 10),

                // Genre Filter Chips
                SizedBox(
                  height: 32, // 🔥 reduced height
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.only(left: 16),
                    itemCount: genres.length,
                    itemBuilder: (_, i) {
                      final g = genres[i];
                      final isSelected = selectedGenre == g;

                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            selectedGenre = g;
                            rankingF = _getRankingStoriesByGenre(g);
                            _saveSelectedGenre(g);
                          });
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14, // 🔥 reduced width padding
                            vertical: 6, // 🔥 reduced height padding
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.grey.shade200
                                : const Color(0xFFEA7A61),
                            borderRadius: BorderRadius.circular(
                              20,
                            ), // 🔥 smaller radius
                          ),
                          child: Text(
                            g,
                            style: TextStyle(
                              color: isSelected ? Colors.black : Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 12, // ✅ smaller font
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 20),

                // ✅ WEEKLY RANKING STORY LIST (Card Style with Image)
                FutureBuilder(
                  future: rankingF,
                  builder: (_, snap) {
                    if (!snap.hasData) {
                      return _buildHorizontalShimmer();
                    }

                    final items = snap.data!;

                    if (items.isEmpty) {
                      return const SizedBox(
                        height: 100,
                        child: Center(child: Text('No stories available')),
                      );
                    }

                    // 👉 Split list into chunks of 2 items (1–2, 3–4, ...)
                    final groupedItems = <List<Map<String, dynamic>>>[];
                    for (int i = 0; i < items.length; i += 2) {
                      groupedItems.add(
                        items.sublist(
                          i,
                          i + 2 > items.length ? items.length : i + 2,
                        ),
                      );
                    }

                    return SizedBox(
                      height: 250,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.only(left: 16),
                        itemCount: groupedItems.length,
                        itemBuilder: (_, colIndex) {
                          final columnItems = groupedItems[colIndex];

                          return SizedBox(
                            height: 250,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: List.generate(columnItems.length, (
                                rowIndex,
                              ) {
                                final it = columnItems[rowIndex];
                                final actualIndex = colIndex * 2 + rowIndex;

                                return Padding(
                                  padding: EdgeInsets.only(
                                    right: 16,
                                    bottom: rowIndex == 0 ? 12 : 0,
                                  ),
                                  child: GestureDetector(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              BookDetailPage(story: it),
                                        ),
                                      );
                                    },
                                    child: Container(
                                      width: 270,
                                      height: 115,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(16),
                                        gradient: LinearGradient(
                                          colors: [
                                            Color(0xFFEA7A61),
                                            Colors.white,
                                          ],
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Stack(
                                            children: [
                                              ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                                child: CachedNetworkImage(
                                                  imageUrl:
                                                      it["image_url"] ?? "",
                                                  height: 115,
                                                  width: 90,
                                                  fit: BoxFit.cover,
                                                  errorWidget:
                                                      (
                                                        context,
                                                        url,
                                                        error,
                                                      ) => Container(
                                                        height: 115,
                                                        width: 90,
                                                        color: Colors.grey[300],
                                                        child: const Icon(
                                                          Icons.error,
                                                        ),
                                                      ),
                                                ),
                                              ),

                                              Positioned(
                                                top: 0,
                                                left: 0,
                                                child: ClipRRect(
                                                  borderRadius:
                                                      const BorderRadius.only(
                                                        topLeft:
                                                            Radius.circular(16),
                                                        bottomRight:
                                                            Radius.circular(4),
                                                      ),
                                                  child: Container(
                                                    width: 28,
                                                    height: 28,
                                                    alignment: Alignment.center,
                                                    decoration: BoxDecoration(
                                                      gradient: LinearGradient(
                                                        colors: [
                                                          Color(0xFFEA7A61),
                                                          Colors.orange.shade200
                                                              .withOpacity(0.7),
                                                        ],
                                                      ),
                                                    ),
                                                    child: Text(
                                                      "${actualIndex + 1}",
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 16,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(width: 12),

                                          Expanded(
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  it["title"] ?? "Untitled",
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  it["author"] ??
                                                      "Unknown Author",
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    color: Colors.grey.shade600,
                                                  ),
                                                ),
                                                const SizedBox(height: 6),
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                        vertical: 5,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: Color(0xFFEA7A61),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          20,
                                                        ),
                                                  ),
                                                  child: Text(
                                                    it["genre"] ?? "",
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
                const SizedBox(height: 14),

                _sectionTitle("What you might like"),

                const SizedBox(height: 14),

                FutureBuilder(
                  future: recommendedF,
                  builder: (_, snap) {
                    if (!snap.hasData) {
                      return _buildHorizontalShimmer();
                    }

                    final items = snap.data!;
                    if (items.isEmpty) return const SizedBox();

                    return SizedBox(
                      height: 240,
                      child: ListView.builder(
                        // shrinkWrap: true,
                        // physics: NeverScrollableScrollPhysics(),
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.only(left: 16),
                        itemCount: items.length,
                        itemBuilder: (_, i) {
                          final it = items[i];

                          return GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => BookDetailPage(story: it),
                                ),
                              );
                            },
                            child: Container(
                              width: 150,
                              margin: const EdgeInsets.only(right: 14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(14),
                                    child: CachedNetworkImage(
                                      imageUrl: it["image_url"] ?? "",
                                      height: 190,
                                      width: 150,
                                      fit: BoxFit.cover,
                                      errorWidget: (context, url, error) =>
                                          Container(
                                            height: 190,
                                            width: 150,
                                            color: Colors.grey[300],
                                            child: const Icon(Icons.error),
                                          ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    it["title"] ?? "Untitled",
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  Text(
                                    it["author"] ?? "Unknown Author",
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),

                const SizedBox(height: 10),

                _sectionTitle("Browse by Genre"),

                const SizedBox(height: 12),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: FutureBuilder<List<Map<String, dynamic>>>(
                    future: topicsF,
                    builder: (_, snap) {
                      if (!snap.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final topics = snap.data!;

                      if (topics.isEmpty) {
                        return const Center(child: Text('No genres available'));
                      }

                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: topics.length,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              childAspectRatio: 2.2,
                            ),
                        itemBuilder: (_, i) {
                          final topic = topics[i];

                          return GestureDetector(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    BrowseGenrePage(genre: topic["name"] ?? ""),
                              ),
                            ),
                            child: Stack(
                              children: [
                                // ✅ Background image from Supabase table
                                Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    image: DecorationImage(
                                      image: NetworkImage(
                                        topic["image_url"] ?? "",
                                      ),
                                      fit: BoxFit.cover,
                                      onError: (error, stackTrace) {},
                                    ),
                                  ),
                                ),

                                // ✅ Transparent layer for text visibility
                                Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    color: Colors.black.withOpacity(0.25),
                                  ),
                                ),

                                // ✅ Genre label
                                Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: Text(
                                    topic["name"] ?? "",
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),

                const SizedBox(height: 16),

                _sectionTitle("You Might Also Like"),
                const SizedBox(height: 6),

                FutureBuilder(
                  future: allStoriesF,
                  builder: (_, snap) {
                    if (!snap.hasData) {
                      return _buildListTileShimmer();
                    }

                    final items = snap.data!;

                    if (items.isEmpty) {
                      return const Center(child: Text('No stories available'));
                    }

                    return Column(
                      children: List.generate(items.length, (i) {
                        final it = items[i];
                        return ListTile(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => BookDetailPage(story: it),
                              ),
                            );
                          },
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CachedNetworkImage(
                              imageUrl: it['image_url'] ?? "",
                              width: 55,
                              height: 55,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Shimmer.fromColors(
                                baseColor: Colors.grey[300]!,
                                highlightColor: Colors.grey[100]!,
                                child: Container(
                                  width: 55,
                                  height: 55,
                                  color: Colors.white,
                                ),
                              ),
                              errorWidget: (context, url, error) => Container(
                                width: 55,
                                height: 55,
                                color: Colors.grey[300],
                                child: const Icon(Icons.error, size: 20),
                              ),
                            ),
                          ),
                          title: Text(
                            it['title'] ?? 'Untitled',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            it['author'] ?? "Unknown Author",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: const Icon(Icons.more_vert),
                        );
                      }),
                    );
                  },
                ),

                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildHorizontalShimmer() {
    return SizedBox(
      height: 250,
      child: ListView.builder(
        shrinkWrap: true,
        physics: NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.only(left: 16),
        scrollDirection: Axis.horizontal,
        itemCount: 5,
        itemBuilder: (_, i) {
          return Shimmer.fromColors(
            baseColor: Colors.grey[300]!,
            highlightColor: Colors.grey[100]!,
            child: Container(
              margin: const EdgeInsets.only(right: 16),
              width: 150,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 180,
                    width: 150,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(height: 14, width: 130, color: Colors.white),
                  const SizedBox(height: 4),
                  Container(height: 12, width: 100, color: Colors.white),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCarouselShimmer(double height, double width) {
    return Column(
      children: [
        Shimmer.fromColors(
          baseColor: Colors.grey[300]!,
          highlightColor: Colors.grey[100]!,
          child: Container(
            height: height,
            margin: const EdgeInsets.symmetric(horizontal: 36, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (i) {
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              height: 6,
              width: 8,
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(4),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildListTileShimmer() {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 5,
      itemBuilder: (_, i) {
        return Shimmer.fromColors(
          baseColor: Colors.grey[300]!,
          highlightColor: Colors.grey[100]!,
          child: ListTile(
            leading: Container(
              width: 55,
              height: 55,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            title: Container(
              height: 14,
              width: double.infinity,
              color: Colors.white,
            ),
            subtitle: Container(
              height: 12,
              width: 100,
              color: Colors.white,
              margin: const EdgeInsets.only(top: 4),
            ),
          ),
        );
      },
    );
  }

  Widget _buildImageShimmer() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Container(
        height: 180,
        width: 150,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}
