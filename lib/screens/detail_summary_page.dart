import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DetailSummaryPage extends StatefulWidget {
  final Map<String, dynamic> story;

  const DetailSummaryPage({super.key, required this.story});

  @override
  State<DetailSummaryPage> createState() => _DetailSummaryPageState();
}

class _DetailSummaryPageState extends State<DetailSummaryPage> {
  late Map<String, dynamic> story;
  Map<String, dynamic>? userReview;
  List<Map<String, dynamic>> similarStories = [];
  double currentRatingLocal = 0.0;

  @override
  void initState() {
    super.initState();
    story = Map<String, dynamic>.from(widget.story);

    _loadUserReview();
    _fetchSimilarStories();
    _loadReviewCount();

    // ✅ FIRST set initial rating from incoming story
    currentRatingLocal = _parseRating(story["rating"]);

    // ✅ THEN update rating from database and refresh local variable
    _updateStoryRating().then((_) {
      if (mounted) {
        setState(() {
          currentRatingLocal = _parseRating(story["rating"]);
        });
      }
    });
  }

  Future<void> _loadReviewCount() async {
    final supabase = Supabase.instance.client;

    try {
      final reviews = await supabase
          .from("story_reviews")
          .select("id")
          .eq("story_id", story["id"].toString());

      final count = reviews.length;

      // ✅ Update in DB too
      await supabase
          .from("stories")
          .update({"total_reviews": count})
          .eq("id", story["id"].toString());

      if (mounted) {
        setState(() {
          story["total_reviews"] = count;
        });
      }
    } catch (e) {
      debugPrint("Load review count error: $e");
    }
  }

  Future<void> _updateStoryRating() async {
    final supabase = Supabase.instance.client;

    try {
      // Fetch all ratings for this story
      final reviews = await supabase
          .from("story_reviews")
          .select("rating")
          .eq("story_id", story["id"].toString());

      double total = 0;
      for (var r in reviews) {
        total += (r["rating"] as num).toDouble();
      }

      int reviewCount = reviews.length;
      double avg = reviewCount == 0 ? 0.0 : total / reviewCount;

      // Update stories table
      await supabase
          .from("stories")
          .update({"rating": avg, "total_reviews": reviewCount})
          .eq("id", story["id"].toString());

      // Refresh local UI
      final updatedStory = await supabase
          .from("stories")
          .select()
          .eq("id", story["id"])
          .single();

      if (mounted) {
        setState(() {
          story = updatedStory;
        });
      }
    } catch (e) {
      debugPrint("Update rating error: $e");
    }
  }

  Future<void> _fetchSimilarStories() async {
    try {
      final genre = story["genre"];
      if (genre == null) return;

      final data = await Supabase.instance.client
          .from("stories")
          .select("*")
          .eq("genre", genre)
          .neq("id", story["id"]) // exclude current book
          .limit(10);

      setState(() {
        similarStories = List<Map<String, dynamic>>.from(data);
      });
    } catch (e) {
      debugPrint("Error loading similar stories: $e");
    }
  }

  // Safe parsing helpers
  double _parseRating(dynamic rating) {
    if (rating == null) return 0.0;
    if (rating is num) return rating.toDouble();
    if (rating is String) return double.tryParse(rating) ?? 0.0;
    return 0.0;
  }

  int _parseRatingCount(dynamic count) {
    if (count == null) return 0;
    if (count is num) return count.toInt();
    if (count is String) return int.tryParse(count) ?? 0;
    return 0;
  }

  Future<void> _loadUserReview() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final response = await Supabase.instance.client
          .from("story_reviews")
          .select()
          .eq("user_id", user.id)
          .eq("story_id", story["id"].toString())
          .maybeSingle();

      if (mounted) {
        setState(() {
          userReview = response;
        });
      }
    } catch (e) {
      debugPrint("Load review error: $e");
    }
  }

  void _showRatingPopup(BuildContext context) {
    int rating = _parseRating(userReview?["rating"]).toInt();
    final reviewCtrl = TextEditingController(text: userReview?["review"] ?? "");

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, modalSetState) {
            return SafeArea(
              child: DraggableScrollableSheet(
                initialChildSize: 0.55,
                minChildSize: 0.4,
                maxChildSize: 0.7,
                expand: false,
                builder: (_, controller) {
                  final bottomInset = MediaQuery.of(context).viewInsets.bottom;
                  return Padding(
                    padding: EdgeInsets.only(bottom: bottomInset),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: const BoxDecoration(
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(22),
                        ),
                        gradient: LinearGradient(
                          colors: [Color(0xFFCCB5FF), Color(0xFFE8DFFF)],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                      child: SingleChildScrollView(
                        controller: controller,
                        child: Column(
                          children: [
                            // Drag handle
                            Container(
                              width: 40,
                              height: 5,
                              decoration: BoxDecoration(
                                color: Colors.white54,
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            const SizedBox(height: 15),

                            // Title
                            Text(
                              userReview != null
                                  ? "Update Your Review"
                                  : "Rate This Book",
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 20,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 20),

                            // Star Rating
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(5, (i) {
                                return IconButton(
                                  icon: Icon(
                                    i < rating ? Icons.star : Icons.star_border,
                                    color: Colors.orange,
                                    size: 38,
                                  ),
                                  onPressed: () {
                                    modalSetState(
                                      () => rating = i + 1,
                                    ); // update bottomsheet stars
                                    setState(
                                      () => currentRatingLocal = (i + 1)
                                          .toDouble(),
                                    ); // update main screen stars
                                  },
                                );
                              }),
                            ),
                            const SizedBox(height: 16),

                            // Review TextField
                            TextField(
                              controller: reviewCtrl,
                              maxLength: 500,
                              maxLines: 5,
                              decoration: InputDecoration(
                                hintText: "Share your experience...",
                                filled: true,
                                fillColor: Colors.white.withOpacity(0.85),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: const EdgeInsets.all(16),
                              ),
                            ),
                            const SizedBox(height: 20),

                            // Submit Button
                            ElevatedButton(
                              onPressed: () async {
                                final user =
                                    Supabase.instance.client.auth.currentUser;
                                if (user == null) {
                                  _showSnackBar(
                                    context,
                                    "Please login to review",
                                    Colors.orange,
                                  );
                                  return;
                                }

                                if (rating == 0) {
                                  _showSnackBar(
                                    context,
                                    "Please select a rating",
                                    Colors.orange,
                                  );
                                  return;
                                }

                                final supabase = Supabase.instance.client;
                                final isEdit = userReview != null;

                                try {
                                  // ✅ Insert or Update the review
                                  if (isEdit) {
                                    await supabase
                                        .from("story_reviews")
                                        .update({
                                          "rating": rating,
                                          "review": reviewCtrl.text.trim(),
                                          "created_at": DateTime.now()
                                              .toIso8601String(),
                                        })
                                        .eq("user_id", user.id.toString())
                                        .eq("story_id", story["id"].toString());
                                  } else {
                                    await supabase
                                        .from("story_reviews")
                                        .insert({
                                          "story_id": story["id"].toString(),
                                          "user_id": user.id.toString(),
                                          "rating": rating,
                                          "review": reviewCtrl.text.trim(),
                                          "created_at": DateTime.now()
                                              .toIso8601String(),
                                        });
                                  }

                                  // ✅ Load updated reviews list
                                  // ✅ Load updated reviews list
                                  final reviews = await supabase
                                      .from("story_reviews")
                                      .select("rating")
                                      .eq("story_id", story["id"].toString());

                                  // ✅ Calculate new average and count
                                  double total = 0;
                                  for (var r in reviews) {
                                    total += (r["rating"] as num).toDouble();
                                  }

                                  int count = reviews.length;
                                  double avg = total / count;

                                  // ✅ Update in stories table
                                  await supabase
                                      .from("stories")
                                      .update({
                                        "rating": avg,
                                        "rating_count": count,
                                        "total_reviews":
                                            count, // ✅ IMPORTANT — store in stories table
                                      })
                                      .eq("id", story["id"].toString());

                                  // ✅ Get updated story
                                  final updatedStory = await supabase
                                      .from("stories")
                                      .select()
                                      .eq("id", story["id"])
                                      .single();

                                  await _loadReviewCount(); // ✅ refresh count from story_reviews table
                                  await _updateStoryRating();

                                  if (mounted) {
                                    setState(() {
                                      story = updatedStory;
                                      currentRatingLocal =
                                          avg; // ✅ update UI stars with new avg
                                    });
                                  }

                                  Navigator.pop(context);
                                  FocusScope.of(context).unfocus();

                                  _showSnackBar(
                                    context,
                                    "Review ${isEdit ? "updated" : "submitted"} successfully!",
                                    Colors.green,
                                  );
                                } catch (e) {
                                  Navigator.pop(context);
                                  await _loadReviewCount(); // ✅ refresh count from story_reviews table
                                  await _updateStoryRating();

                                  // _showSnackBar(
                                  //   context,
                                  //   "Error: $e",
                                  //   Colors.red,
                                  // );
                                }
                              },

                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 50,
                                  vertical: 16,
                                ),
                                elevation: 8,
                              ),
                              child: Text(
                                userReview != null
                                    ? "UPDATE REVIEW"
                                    : "POST REVIEW",
                                style: const TextStyle(
                                  color: Colors.redAccent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),

                            const SizedBox(height: 12),

                            TextButton(
                              onPressed: () {
                                Navigator.pop(context);
                                FocusScope.of(context).unfocus();
                              },
                              child: const Text(
                                "Cancel",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  double _calculateNewAverage(
    dynamic oldAvg,
    dynamic oldCount,
    int newRating,
    bool isEdit,
  ) {
    double avg = _parseRating(oldAvg);
    int count = _parseRatingCount(oldCount);

    if (count == 0) return newRating.toDouble();

    if (isEdit) {
      double oldUserRating = _parseRating(userReview?["rating"] ?? 0);
      return ((avg * count) - oldUserRating + newRating) / count;
    } else {
      return ((avg * count) + newRating) / (count + 1);
    }
  }

  void _showSnackBar(BuildContext context, String message, Color color) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Widget _buildStarRating(double rating, {double size = 20}) {
    int fullStars = rating.floor();
    bool hasHalf = (rating - fullStars) >= 0.5;
    return Row(
      children: List.generate(5, (i) {
        if (i < fullStars)
          return Icon(Icons.star, color: Colors.amber, size: size);
        if (i == fullStars && hasHalf)
          return Icon(Icons.star_half, color: Colors.amber, size: size);
        return Icon(Icons.star_border, color: Colors.grey.shade400, size: size);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double currentRating = _parseRating(story["rating"]);
    final int reviewCount = _parseRatingCount(story["total_reviews"]);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Detail Summary",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Book Summary",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text(
              story["description"] ?? "No summary available.",
              style: TextStyle(
                fontSize: 14,
                height: 1.6,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 30),

            // Ratings Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Text(
                  "Ratings and reviews",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                Icon(Icons.arrow_forward_ios, size: 18),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  currentRatingLocal.toStringAsFixed(1),
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildStarRating(currentRatingLocal, size: 22),
                    Text(
                      "$reviewCount reviews",
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 30),

            // Rate this book
            const Text(
              "Rate this book",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            _buildStarRating(_parseRating(userReview?["rating"]), size: 28),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => _showRatingPopup(context),
              child: Text(
                userReview != null ? "Edit your review" : "Write a review",
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 30),

            // Similar Genre
            const Text(
              "Similar Genre",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 130,
              child: similarStories.isEmpty
                  ? Center(child: Text("No similar books"))
                  : ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: similarStories.length,
                      itemBuilder: (context, index) {
                        final book = similarStories[index];
                        return GestureDetector(
                          onTap: () {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (_) => DetailSummaryPage(story: book),
                              ),
                            );
                          },
                          child: _genreBox(book["title"], book["image_url"]),
                        );
                      },
                    ),
            ),

            const SizedBox(height: 30),

            // Similar Books
            // Row(
            //   mainAxisAlignment: MainAxisAlignment.spaceBetween,
            //   children: const [
            //     Text(
            //       "Similar Books",
            //       style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            //     ),
            //     Text(
            //       "See All",
            //       style: TextStyle(
            //         color: Colors.redAccent,
            //         fontWeight: FontWeight.w600,
            //       ),
            //     ),
            //   ],
            // ),
            // const SizedBox(height: 14),
            // ClipRRect(
            //   borderRadius: BorderRadius.circular(16),
            //   child: CachedNetworkImage(
            //     imageUrl: story["image_url"] ?? "",
            //     height: 220,
            //     width: double.infinity,
            //     fit: BoxFit.cover,
            //     placeholder: (_, __) => Container(color: Colors.grey.shade200),
            //     errorWidget: (_, __, ___) => const Icon(Icons.error),
            //   ),
            // ),
            // const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  // FIXED: img.Url → imgUrl
  Widget _genreBox(String label, String? imgUrl) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: CachedNetworkImage(
              imageUrl: imgUrl ?? "",
              width: 80,
              height: 80,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(color: Colors.grey.shade300),
              errorWidget: (_, __, ___) =>
                  const Icon(Icons.broken_image, color: Colors.grey),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
