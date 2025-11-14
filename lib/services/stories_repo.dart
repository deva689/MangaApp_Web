// lib/services/stories_repo.dart

import 'package:supabase_flutter/supabase_flutter.dart';

class StoriesRepo {
  /// ✅ Supabase DB instance
  final SupabaseClient _db = Supabase.instance.client;

  /// ✅ Fetch Topics (used for Browse by Genre grid UI)
  Future<List<Map<String, dynamic>>> getTopics() async {
    final rows = await _db.from("topics").select().order("id", ascending: true);

    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// ✅ Fetch stories by Category (Daily Recommended / Cards / Banner)
  Future<List<Map<String, dynamic>>> byCategory(
    String category, {
    int limit = 20,
  }) async {
    final rows = await _db
        .from('stories')
        .select()
        .eq('category', category)
        .order('created_at', ascending: false)
        .limit(limit);

    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// ✅ Weekly Ranking (from dailyupdate table)
  Future<List<Map<String, dynamic>>> weeklyRanking() async {
    final rows = await _db
        .from('dailyupdate')
        .select()
        .order('ranking', ascending: true);

    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// ✅ Fetch all stories (Used in "You Might Also Like")
  Future<List<Map<String, dynamic>>> allStories() async {
    final rows = await _db
        .from('stories')
        .select()
        .order('created_at', ascending: false);

    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// ✅ Fetch stories by Genre (browse page)
  Future<List<Map<String, dynamic>>> byGenre(String genre) async {
    final rows = await _db
        .from('stories')
        .select()
        .eq('genre', genre)
        .order('created_at', ascending: false);

    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// ✅ Search stories (title / author / genre)
  Future<List<Map<String, dynamic>>> searchStories(String query) async {
    if (query.trim().isEmpty) return [];

    final rows = await _db
        .from('stories')
        .select()
        .or("title.ilike.%$query%,author.ilike.%$query%,genre.ilike.%$query%")
        .order('created_at', ascending: false);

    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// ✅ Most viewed stories (Top 10 Today)
  Future<List<Map<String, dynamic>>> topStoriesByViews({int limit = 10}) async {
    final rows = await _db
        .from('stories')
        .select()
        .order('views', ascending: false)
        .limit(limit);

    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// ✅ Trending stories (last X days)
  Future<List<Map<String, dynamic>>> topStoriesByViewsWithinDays(
    int days, {
    int limit = 50,
  }) async {
    try {
      final startDate = DateTime.now().subtract(Duration(days: days));
      final formatted = startDate.toIso8601String();

      final rows = await _db
          .from('stories')
          .select()
          .gte('created_at', formatted)
          .order('views', ascending: false)
          .limit(limit);

      return (rows as List).cast<Map<String, dynamic>>();
    } catch (e) {
      print("Error during topStoriesByViewsWithinDays: $e");
      return await topStoriesByViews(limit: limit);
    }
  }

  /// ✅ Recommended stories based on user's preferred genres
  Future<List<Map<String, dynamic>>> recommendedStories() async {
    final String userId = _db.auth.currentUser!.id;

    final pref = await _db
        .from("user_preferences")
        .select("genres")
        .eq("user_id", userId)
        .maybeSingle();

    if (pref == null || pref["genres"] == null) {
      return [];
    }

    final List<dynamic> genres = pref["genres"];

    final rows = await _db
        .from("stories")
        .select()
        .inFilter(
          "genre",
          genres,
        ) // ✅ Supabase v2 syntax (correct replacement for .in_())
        .order("views", ascending: false);

    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// ✅ Top stories by Genre + date filter (Weekly ranking filtered)
  Future<List<Map<String, dynamic>>> topStoriesByGenreAndDays(
    String genre,
    int days, {
    int limit = 50,
  }) async {
    try {
      final startDate = DateTime.now().subtract(Duration(days: days));
      final formatted = startDate.toIso8601String();

      final rows = await _db
          .from('stories')
          .select()
          .eq('genre', genre)
          .gte('created_at', formatted)
          .order('views', ascending: false)
          .limit(limit);

      return (rows as List).cast<Map<String, dynamic>>();
    } catch (e) {
      print("Error during topStoriesByGenreAndDays: $e");
      return [];
    }
  }
}
