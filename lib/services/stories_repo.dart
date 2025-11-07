// lib/services/stories_repo.dart

import 'package:supabase_flutter/supabase_flutter.dart';

class StoriesRepo {
  final _db = Supabase.instance.client;

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

  Future<List<Map<String, dynamic>>> weeklyRanking() async {
    final rows = await _db
        .from('dailyupdate')
        .select()
        .order('ranking', ascending: true);
    return (rows as List).cast<Map<String, dynamic>>();
  }
}
