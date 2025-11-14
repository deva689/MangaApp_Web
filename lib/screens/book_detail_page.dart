import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
import 'package:manga/audio/audio_player_page.dart';
import 'package:manga/screens/detail_summary_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class BookDetailPage extends StatefulWidget {
  final Map<String, dynamic> story;

  const BookDetailPage({super.key, required this.story});

  @override
  State<BookDetailPage> createState() => _BookDetailPageState();
}

class _BookDetailPageState extends State<BookDetailPage> {
  final SupabaseClient supabase = Supabase.instance.client;
  bool isFavorite = false;
  Duration audioDuration = Duration.zero;
  Map<String, Duration> episodeDurations = {};
  String? downloadedPath;
  Map<String, String?> episodeDownloads = {};
  bool _isDownloading = false;
  double _downloadProgress = 0.0;

  String truncateText(String text, {int limit = 140}) {
    if (text.length <= limit) return text;
    return text.substring(0, limit) + "...";
  }

  @override
  void initState() {
    super.initState();
    _checkFavorite();
    _loadAudioDuration(); // ✅ Fetch duration
    _loadReviewCount();
    _updateStoryRating();
    _loadEpisodes();
    _checkIfDownloaded();
  }

  Future<String?> downloadEpisode(Map<String, dynamic> episode) async {
    try {
      final url = episode['audio_url']?.toString();
      if (url == null || url.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Episode audio URL missing")),
        );
        return null;
      }

      final epId = episode["id"].toString();

      setState(() {
        _isDownloading = true;
        _downloadProgress = 0.0;
      });

      final dir = await getApplicationDocumentsDirectory();
      final filePath = "${dir.path}/episode_$epId.mp3";
      final file = File(filePath);

      final request = http.Request('GET', Uri.parse(url));
      final httpClient = http.Client();
      final streamedResponse = await httpClient.send(request);

      final contentLength = streamedResponse.contentLength ?? 0;
      final sink = file.openWrite();
      int bytesReceived = 0;

      await for (final chunk in streamedResponse.stream) {
        bytesReceived += chunk.length;
        sink.add(chunk);

        if (contentLength > 0) {
          setState(() {
            _downloadProgress = bytesReceived / contentLength;
          });
        }
      }

      await sink.close();
      httpClient.close();

      // 🔥 Save meta to SharedPreferences
      await _saveEpisodeMeta(episode, filePath);

      setState(() {
        _isDownloading = false;
        _downloadProgress = 0.0;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Episode downloaded: ${episode['title']}")),
      );

      return filePath;
    } catch (e) {
      debugPrint("Episode Download Error: $e");
      setState(() {
        _isDownloading = false;
        _downloadProgress = 0.0;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Episode download failed")));

      return null;
    }
  }

  Future<void> _saveEpisodeMeta(
    Map<String, dynamic> episode,
    String path,
  ) async {
    final prefs = await SharedPreferences.getInstance();

    List<String> list = prefs.getStringList("episode_downloads") ?? [];

    final item = jsonEncode({
      "id": episode["id"],
      "story_id": episode["story_id"],
      "title": episode["title"],
      "episode_number": episode["episode_number"],
      "local_path": path,
    });

    list.removeWhere((e) => jsonDecode(e)["id"] == episode["id"]);
    list.add(item);

    await prefs.setStringList("episode_downloads", list);
  }

  Future<void> _checkIfDownloaded() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList("downloads") ?? [];

    for (var e in list) {
      final item = jsonDecode(e);
      if (item["id"].toString() == widget.story["id"].toString()) {
        setState(() {
          downloadedPath = item["local_path"];
        });
        break;
      }
    }
  }

  Future<void> _updateStoryRating() async {
    final supabase = Supabase.instance.client;

    try {
      // fetch all ratings for this story
      final reviews = await supabase
          .from("story_reviews")
          .select("rating")
          .eq("story_id", widget.story["id"].toString());

      double total = 0;
      for (var r in reviews) {
        total += (r["rating"] as num).toDouble();
      }

      int reviewCount = reviews.length;
      double avg = reviewCount == 0 ? 0.0 : total / reviewCount;

      // update stories table
      await supabase
          .from("stories")
          .update({"rating": avg, "total_reviews": reviewCount})
          .eq("id", widget.story["id"].toString());

      if (mounted) {
        setState(() {
          widget.story["rating"] = avg;
          widget.story["total_reviews"] = reviewCount;
        });
      }
    } catch (e) {
      debugPrint("Rating update error: $e");
    }
  }

  Future<void> _loadReviewCount() async {
    final supabase = Supabase.instance.client;

    try {
      final reviews = await supabase
          .from("story_reviews")
          .select("id")
          .eq("story_id", widget.story["id"].toString()); // ✅ widget.story

      if (mounted) {
        setState(() {
          widget.story["rating_count"] = reviews.length; // ✅ update story map
        });
      }
    } catch (e) {
      debugPrint("Load review count error: $e");
    }
  }

  Future<void> _loadAudioDuration() async {
    try {
      if (widget.story['story_type'] == "episodic") {
        return; // episodic stories don't use a single duration
      }

      final player = AudioPlayer();

      player.onDurationChanged.listen((d) {
        if (mounted) {
          setState(() => audioDuration = d);
        }
        player.dispose();
      });

      await player.setSourceUrl(widget.story['audio_url']);
    } catch (e) {
      debugPrint("Error loading audio duration: $e");
    }
  }

  List<dynamic> episodeList = [];
  bool loadingEpisodes = true;

  Future<void> _loadEpisodes() async {
    try {
      if (widget.story['story_type'] != "episodic") return;

      final data = await supabase
          .from("stories_episode")
          .select()
          .eq("story_id", widget.story["id"])
          .order("episode_number", ascending: true);

      episodeList = data;
      loadingEpisodes = false;
      setState(() {});

      // 🔥 Load durations for each episode
      for (var ep in episodeList) {
        final url = ep["audio_url"];
        if (url == null || url.isEmpty) continue;

        final player = AudioPlayer();

        await player.setSourceUrl(url);

        player.onDurationChanged.listen((d) {
          episodeDurations[ep["id"].toString()] = d;
          setState(() {});
          player.dispose();
        });
      }
    } catch (e) {
      debugPrint("Episode load error: $e");
    }
  }

  String formatEp(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return "${d.inMinutes}:${two(d.inSeconds % 60)}";
  }

  String _format(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return "${d.inMinutes}:${two(d.inSeconds % 60)}";
  }

  Future<void> _checkFavorite() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      final storyId = widget.story['id']?.toString();

      if (userId == null || storyId == null) return;

      final pref = await supabase
          .from("user_preferences")
          .select("favourites")
          .eq("user_id", userId)
          .maybeSingle();

      if (pref == null) return;

      final favs = List<String>.from(pref["favourites"] ?? []);
      setState(() => isFavorite = favs.contains(storyId));
    } catch (e) {
      debugPrint("Fav check error: $e");
    }
  }

  Future<void> _toggleFavorite() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      final storyId = widget.story['id']?.toString();

      if (userId == null || storyId == null) return;

      final pref = await supabase
          .from("user_preferences")
          .select("favourites")
          .eq("user_id", userId)
          .maybeSingle();

      List<String> favs = [];

      if (pref == null) {
        await supabase.from("user_preferences").insert({
          "user_id": userId,
          "favourites": [storyId],
        });
        setState(() => isFavorite = true);
        return;
      }

      favs = List<String>.from(pref["favourites"] ?? []);

      if (favs.contains(storyId)) {
        favs.remove(storyId);
      } else {
        favs.add(storyId);
      }

      await supabase
          .from("user_preferences")
          .update({"favourites": favs})
          .eq("user_id", userId);

      setState(() => isFavorite = !isFavorite);
    } catch (e) {
      debugPrint("Fav toggle error: $e");
    }
  }

  Future<void> _saveDownloadMeta(
    Map<String, dynamic> story,
    String path,
  ) async {
    final prefs = await SharedPreferences.getInstance();

    List<String> list = prefs.getStringList("downloads") ?? [];

    final item = jsonEncode({
      "id": story["id"],
      "title": story["title"],
      "image_url": story["image_url"],
      "local_path": path,
    });

    list.removeWhere((e) => jsonDecode(e)["id"] == story["id"]);
    list.add(item);

    await prefs.setStringList("downloads", list);
  }

  String _formatRating(dynamic r) {
    if (r == null) return "0.0";
    if (r is num) return r.toStringAsFixed(1);
    return double.tryParse(r.toString())?.toStringAsFixed(1) ?? "0.0";
  }

  Future<void> _downloadAudio() async {
    try {
      final url = widget.story['audio_url']?.toString();
      if (url == null || url.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Audio URL missing")));
        return;
      }

      setState(() {
        _isDownloading = true;
        _downloadProgress = 0.0;
      });

      final dir = await getApplicationDocumentsDirectory();
      final filePath = "${dir.path}/${widget.story['id']}.mp3";
      final file = File(filePath);

      final request = http.Request('GET', Uri.parse(url));
      final httpClient = http.Client();
      final streamedResponse = await httpClient.send(request);

      final contentLength = streamedResponse.contentLength ?? 0;
      final sink = file.openWrite();
      int bytesReceived = 0;

      await for (final chunk in streamedResponse.stream) {
        bytesReceived += chunk.length;
        sink.add(chunk);

        if (contentLength > 0) {
          setState(() {
            _downloadProgress = bytesReceived / contentLength;
          });
        }
      }

      await sink.close();
      httpClient.close();

      await _saveDownloadMeta(widget.story, filePath);

      setState(() {
        downloadedPath = filePath;
        _isDownloading = false;
        _downloadProgress = 0.0;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Downloaded for offline use!")),
      );
    } catch (e) {
      debugPrint("Download error: $e");
      setState(() {
        _isDownloading = false;
        _downloadProgress = 0.0;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Download failed")));
    }
  }

  Widget _singleChapterTile() {
    final story = widget.story;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        story["title"],
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      subtitle: Text(
        audioDuration.inSeconds == 0 ? "Loading..." : _format(audioDuration),
        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
      ),

      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(
              downloadedPath != null ? Icons.check_circle : Icons.download,
              color: downloadedPath != null ? Colors.green : Colors.black87,
              size: 26,
            ),
            onPressed: () async {
              if (downloadedPath == null) {
                await _downloadAudio();
                setState(() {});
              }
            },
          ),

          const Icon(Icons.play_circle_fill, size: 36, color: Colors.black87),
        ],
      ),

      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => AudioPlayerPage(story: story)),
        );
      },
    );
  }

  Widget _episodeListView() {
    if (loadingEpisodes) {
      return const Center(child: CircularProgressIndicator());
    }

    if (episodeList.isEmpty) {
      return const Text(
        "No episodes uploaded yet.",
        style: TextStyle(color: Colors.grey),
      );
    }

    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: episodeList.length,
      itemBuilder: (context, index) {
        final ep = episodeList[index];
        final epId = ep["id"].toString();

        return ListTile(
          title: Text(
            ep["title"] ?? "Episode ${ep["episode_number"]}",
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          subtitle: Text(
            episodeDurations[epId] != null
                ? formatEp(episodeDurations[epId]!)
                : "Loading...",
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),

          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(
                  episodeDownloads[epId] != null
                      ? Icons.check_circle
                      : Icons.download,
                  color: episodeDownloads[epId] != null
                      ? Colors.green
                      : Colors.black87,
                  size: 24,
                ),
                onPressed: () async {
                  if (episodeDownloads[epId] == null) {
                    episodeDownloads[epId] = await downloadEpisode(ep);
                    setState(() {});
                  }
                },
              ),

              const Icon(
                Icons.play_circle_fill,
                size: 36,
                color: Colors.black87,
              ),
            ],
          ),

          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AudioPlayerPage(
                  story: widget.story,
                  episode: ep,
                  isEpisode: true,
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final story = widget.story;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ✅ Top nav bar
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, size: 24),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Row(
                    children: const [
                      Icon(Icons.search, size: 22),
                      SizedBox(width: 18),
                      Icon(Icons.send_outlined, size: 22),
                      SizedBox(width: 18),
                      Icon(Icons.more_vert, size: 22),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // ✅ Book preview row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CachedNetworkImage(
                      imageUrl: story["image_url"],
                      width: 135,
                      height: 170,
                      fit: BoxFit.cover,
                    ),
                  ),

                  const SizedBox(width: 14),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          story["genre"] ?? "",
                          style: TextStyle(
                            color: Colors.orange.shade700,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),

                        const SizedBox(height: 6),

                        Text(
                          story["title"] ?? "",
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                          ),
                        ),

                        const SizedBox(height: 4),

                        Text(
                          story["author"] ?? "",
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                        ),

                        const SizedBox(height: 10),

                        // ✅ Offer banner
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE97A54),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            "Special offer get 50% off",
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),

                        const SizedBox(height: 10),

                        // ✅ Listen $10 + price
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            ElevatedButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        AudioPlayerPage(story: story),
                                  ),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFF3F3F3),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 22,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: Text(
                                "Listen \$${story['price']}",
                                style: const TextStyle(
                                  color: Colors.black87,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),

                            const SizedBox(width: 10),

                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "List Price",
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                Row(
                                  children: [
                                    Text(
                                      "\$399",
                                      style: TextStyle(
                                        fontSize: 13,
                                        decoration: TextDecoration.lineThrough,
                                        color: Colors.grey.shade500,
                                      ),
                                    ),

                                    const SizedBox(width: 15),

                                    GestureDetector(
                                      onTap: _toggleFavorite,
                                      child: Icon(
                                        isFavorite
                                            ? Icons.favorite
                                            : Icons.favorite_border,
                                        size: 28,
                                        color: isFavorite
                                            ? Colors.red
                                            : Colors.black87,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 22),

              // ✅ Rating / Pages / Duration Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _infoTile(
                    Icons.star,
                    _formatRating(
                      story['rating'],
                    ), // ✅ shows 3.0 instead of 3 or 0
                    "${story['total_reviews'] ?? 0} reviews",
                  ),

                  _divider(),

                  story["story_type"] == "episodic"
                      ? _infoTile(
                          Icons.list_alt,
                          "${episodeList.length}",
                          "Episodes",
                        )
                      : _infoTile(
                          Icons.timer_outlined,
                          audioDuration.inSeconds == 0
                              ? "Loading..."
                              : _format(audioDuration),
                          "duration",
                        ),
                ],
              ),

              const SizedBox(height: 22),

              // ✅ Book Summary title
              const Text(
                "Book Summary",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),

              const SizedBox(height: 8),

              Text(
                truncateText(story["description"] ?? ""),
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade700,
                  height: 1.4,
                ),
              ),

              const SizedBox(height: 8),

              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DetailSummaryPage(story: story),
                    ),
                  ).then((_) {
                    _loadReviewCount();
                    _updateStoryRating(); // ✅ also refresh rating after return
                  });
                },
                child: Center(
                  child: RichText(
                    text: TextSpan(
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.redAccent,
                        fontWeight: FontWeight.bold,
                      ),
                      children: [
                        TextSpan(text: "READ MORE "),
                        WidgetSpan(
                          child: Icon(
                            Icons.arrow_forward,
                            size: 16,
                            color: Colors.redAccent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 22),

              // ✅ Chapters title
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Text(
                    "Available Chapters",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  Icon(Icons.graphic_eq, size: 22),
                ],
              ),

              const SizedBox(height: 10),

              story["story_type"] == "single"
                  ? _singleChapterTile()
                  : _episodeListView(),
            ],
          ),
        ),
      ),
    );
  }

  // ✅ Divider inline
  Widget _divider() =>
      Container(height: 30, width: 1.4, color: Colors.grey.shade400);

  // ✅ Chapter Row
  Widget _chapterTile(BuildContext context, String title, String duration) {
    final story = widget.story;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      subtitle: Text(
        duration,
        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
      ),
      trailing: const Icon(
        Icons.play_circle_fill,
        size: 36,
        color: Colors.black87,
      ),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => AudioPlayerPage(story: story)),
        );
      },
    );
  }

  // ✅ Info Tile (rating/pages/duration)
  Widget _infoTile(IconData icon, String top, String bottom) {
    return Column(
      children: [
        Row(
          children: [
            Text(
              top,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(width: 4),
            Icon(icon, size: 17),
          ],
        ),
        Text(
          bottom,
          style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
        ),
      ],
    );
  }
}
