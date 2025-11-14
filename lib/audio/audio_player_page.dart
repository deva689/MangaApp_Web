import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AudioPlayerPage extends StatefulWidget {
  final Map<String, dynamic> story;
  final Map<String, dynamic>? episode;
  final bool isEpisode;

  const AudioPlayerPage({
    super.key,
    required this.story,
    this.episode,
    this.isEpisode = false,
  });

  @override
  State<AudioPlayerPage> createState() => _AudioPlayerPageState();
}

class Segment {
  final int speaker;
  final String text;
  final double start;
  final double end;
  final List<WordTiming>? words;

  Segment({
    required this.speaker,
    required this.text,
    required this.start,
    required this.end,
    this.words,
  });

  Map<String, dynamic> toJson() => {
    'speaker': speaker,
    'text': text,
    'start': start,
    'end': end,
    'words': words?.map((w) => w.toJson()).toList(),
  };

  static Segment fromMap(Map m) => Segment(
    speaker: (m['speaker'] is int)
        ? m['speaker']
        : int.parse(m['speaker'].toString()),
    text: m['text'] ?? '',
    start: (m['start'] is num)
        ? (m['start'] as num).toDouble()
        : double.parse(m['start'].toString()),
    end: (m['end'] is num)
        ? (m['end'] as num).toDouble()
        : double.parse(m['end'].toString()),
    words: m['words'] != null
        ? (m['words'] as List).map((w) => WordTiming.fromMap(w as Map)).toList()
        : null,
  );
}

class WordTiming {
  final String word;
  final double start;
  final double end;

  WordTiming({required this.word, required this.start, required this.end});

  Map<String, dynamic> toJson() => {'word': word, 'start': start, 'end': end};

  static WordTiming fromMap(Map m) => WordTiming(
    word: m['word'] ?? '',
    start: (m['start'] is num)
        ? (m['start'] as num).toDouble()
        : double.parse(m['start'].toString()),
    end: (m['end'] is num)
        ? (m['end'] as num).toDouble()
        : double.parse(m['end'].toString()),
  );
}

class _AudioPlayerPageState extends State<AudioPlayerPage> {
  final AudioPlayer _player = AudioPlayer();
  late final SupabaseClient supabase;

  bool isPlaying = false;
  bool isLoading = false;
  Duration duration = Duration.zero;
  Duration position = Duration.zero;
  double speed = 1.0;
  bool isFavorite = false;
  bool isLoopEnabled = false;
  bool hasIncreasedViews = false;
  String? downloadedPath;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;

  List<Segment> _segments = [];
  bool _isTranscriptLoading = false;
  final ScrollController _transcriptScrollController = ScrollController();
  int? _activeSegmentIndex;
  int? _activeWordIndex; // Track active word within segment

  final List<Color> _speakerColors = [
    const Color(0xFF00D9FF), // Bright Cyan
    const Color(0xFFFF6B9D), // Pink
    const Color(0xFF9D4EDD), // Purple
    const Color(0xFFFFBE0B), // Yellow
    const Color(0xFF06FFA5), // Mint Green
    const Color(0xFFFF006E), // Magenta
    const Color(0xFF3A86FF), // Blue
    const Color(0xFFFF8500), // Orange
  ];

  Timer? _positionTimer;

  @override
  void initState() {
    super.initState();
    supabase = Supabase.instance.client;
    _initPlayer();
    _checkFavorite();
    _loadTranscriptFromSupabaseIfExists();
    _checkIfDownloaded();
    // notifiers already initialized inline above
  }

  @override
  void dispose() {
    _positionTimer?.cancel();
    _transcriptScrollController.dispose();
    _player.dispose();
    _activeSegmentNotifier.dispose();
    _activeWordNotifier.dispose();
    super.dispose();
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

  Future<void> _initPlayer() async {
    try {
      _player.setReleaseMode(ReleaseMode.stop);

      _player.onDurationChanged.listen((d) {
        if (mounted) setState(() => duration = d);
      });

      _player.onPositionChanged.listen((p) {
        if (mounted) {
          setState(() => position = p);
          _updateActiveSegmentAndWord();
        }
      });

      _player.onPlayerComplete.listen((_) {
        if (!mounted) return;
        setState(() {
          isPlaying = false;
          position = Duration.zero;
        });
      });

      final audioUrl = widget.isEpisode
          ? widget.episode!['audio_url']
          : widget.story['audio_url'];

      if (audioUrl != null && audioUrl.toString().isNotEmpty) {
        setState(() => isLoading = true);

        if (downloadedPath != null && File(downloadedPath!).existsSync()) {
          await _player.setSourceUrl(downloadedPath!);
        } else {
          await _player.setSourceUrl(audioUrl.toString());
        }
        await _player.resume();

        setState(() {
          isPlaying = true;
          isLoading = false;
        });

        _increaseViews();
        _startPositionTimer();
      }
    } catch (e) {
      debugPrint('Error initializing player: $e');
      if (mounted) setState(() => isLoading = false);
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

  void _startPositionTimer() {
    _positionTimer?.cancel();
    _positionTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      _updateActiveSegmentAndWord();
    });
  }

  // Live notifiers so modal receives updates while it's open
  final ValueNotifier<int?> _activeSegmentNotifier = ValueNotifier<int?>(null);
  final ValueNotifier<int?> _activeWordNotifier = ValueNotifier<int?>(null);

  void _updateActiveSegmentAndWord() {
    if (_segments.isEmpty) return;

    final posSeconds = position.inMilliseconds / 1000.0;
    int? newActiveSegmentIndex;
    int? newActiveWordIndex;

    for (int i = 0; i < _segments.length; i++) {
      if (posSeconds >= _segments[i].start && posSeconds <= _segments[i].end) {
        newActiveSegmentIndex = i;

        final words = _segments[i].words;
        if (words != null && words.isNotEmpty) {
          for (int j = 0; j < words.length; j++) {
            final w = words[j];

            // --- NEW: support both absolute and relative word timings ---
            final absoluteWordStart = w.start;
            final absoluteWordEnd = w.end;

            // if word timings are relative to the segment, add segment.start
            final relativeWordStart = _segments[i].start + w.start;
            final relativeWordEnd = _segments[i].start + w.end;

            final matchesAbsolute =
                posSeconds >= absoluteWordStart &&
                posSeconds <= absoluteWordEnd;
            final matchesRelative =
                posSeconds >= relativeWordStart &&
                posSeconds <= relativeWordEnd;

            if (matchesAbsolute || matchesRelative) {
              newActiveWordIndex = j;
              break;
            }
          }
        }
        break;
      }
    }

    if (newActiveSegmentIndex != _activeSegmentIndex ||
        newActiveWordIndex != _activeWordIndex) {
      setState(() {
        _activeSegmentIndex = newActiveSegmentIndex;
        _activeWordIndex = newActiveWordIndex;
      });

      // update notifiers so modal will rebuild its highlights
      _activeSegmentNotifier.value = newActiveSegmentIndex;
      _activeWordNotifier.value = newActiveWordIndex;
    }

    if (newActiveSegmentIndex != null &&
        _transcriptScrollController.hasClients) {
      _scrollToSegment(newActiveSegmentIndex);
    }
  }

  void _scrollToSegment(int index) {
    if (!_transcriptScrollController.hasClients) return;

    const itemHeight = 120.0;
    final targetOffset = index * itemHeight;
    final maxScroll = _transcriptScrollController.position.maxScrollExtent;
    final minScroll = _transcriptScrollController.position.minScrollExtent;

    final safeOffset = targetOffset.clamp(minScroll, maxScroll);

    _transcriptScrollController.animateTo(
      safeOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  Future<void> _increaseViews() async {
    if (hasIncreasedViews) return;
    final storyId = widget.story['id'];
    if (storyId == null) return;

    try {
      final currentViews = widget.story['views'] ?? 0;
      await supabase
          .from('stories')
          .update({'views': currentViews + 1})
          .eq('id', storyId);
      hasIncreasedViews = true;
    } catch (e) {
      debugPrint('Error increasing views: $e');
    }
  }

  String _format(Duration d) =>
      "${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";

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
      if (mounted) setState(() => isFavorite = favs.contains(storyId));
    } catch (e) {
      debugPrint("Error checking favorite: $e");
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
        if (mounted) setState(() => isFavorite = true);
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

      if (mounted) setState(() => isFavorite = !isFavorite);
    } catch (e) {
      debugPrint("Error toggling favorite: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to update favorite")),
        );
      }
    }
  }

  void _toggleSpeed() {
    setState(() {
      if (speed == 1.0) {
        speed = 1.5;
      } else if (speed == 1.5) {
        speed = 2.0;
      } else {
        speed = 1.0;
      }
    });
    _player.setPlaybackRate(speed);
  }

  void _toggleLoop() {
    setState(() {
      isLoopEnabled = !isLoopEnabled;
      _player.setReleaseMode(
        isLoopEnabled ? ReleaseMode.loop : ReleaseMode.stop,
      );
    });
  }

  Future<void> _togglePlayPause() async {
    try {
      setState(() => isLoading = true);

      final audioUrl = widget.isEpisode
          ? widget.episode!['audio_url']
          : widget.story['audio_url'];

      if (!isPlaying) {
        if (audioUrl == null || audioUrl.toString().isEmpty) {
          throw Exception("Audio URL missing");
        }

        await _player.resume();

        if (!hasIncreasedViews) _increaseViews();
        _startPositionTimer();
      } else {
        await _player.pause();
      }

      setState(() {
        isPlaying = !isPlaying;
        isLoading = false;
      });
    } catch (e) {
      debugPrint("Play/Pause error: $e");
      if (mounted) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Playback error: $e")));
      }
    }
  }

  Future<void> _loadTranscriptFromSupabaseIfExists() async {
    try {
      final storyId = widget.story['id'];
      if (storyId == null) return;

      final res = await supabase
          .from('stories')
          .select('transcript')
          .eq('id', storyId)
          .maybeSingle();
      if (res == null) return;

      final transcript = res['transcript'];
      if (transcript == null) return;

      final List segs = transcript is String
          ? jsonDecode(transcript)
          : transcript;
      _segments = segs.map((m) => Segment.fromMap(m as Map)).toList();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Error loading transcript from Supabase: $e');
    }
  }

  Future<void> _fetchTranscriptFromDeepgramAndSave(String audioUrl) async {
    if (audioUrl.isEmpty) return;
    setState(() => _isTranscriptLoading = true);

    try {
      const deepgramKey = "9f257c1c680b180d1a80711004a8439c198d6670";
      final uri = Uri.parse(
        "https://api.deepgram.com/v1/listen?diarize=true&punctuate=true&model=nova-2",
      );
      final audioBytes = await _downloadAudioBytes(audioUrl);

      final response = await http.post(
        uri,
        headers: {
          "Authorization": "Token $deepgramKey",
          "Content-Type": "audio/mpeg",
        },
        body: audioBytes,
      );

      if (response.statusCode != 200) {
        debugPrint('Deepgram error: ${response.statusCode} ${response.body}');
        throw Exception('Transcription failed: ${response.statusCode}');
      }

      final Map data = jsonDecode(response.body);
      List<Segment> parsed = [];

      try {
        final paragraphs =
            data['results']?['channels']?[0]?['alternatives']?[0]?['paragraphs']?['paragraphs'];

        if (paragraphs is List && paragraphs.isNotEmpty) {
          for (var p in paragraphs) {
            final speaker = p['speaker'] ?? 0;
            final text = (p['text'] ?? '').toString().trim();
            final start = (p['start'] ?? 0).toDouble();
            final end = (p['end'] ?? 0).toDouble();

            // Extract word timings
            List<WordTiming>? wordTimings;
            if (p['words'] != null) {
              wordTimings = (p['words'] as List).map((w) {
                return WordTiming(
                  word: w['word'] ?? '',
                  start: (w['start'] ?? 0).toDouble(),
                  end: (w['end'] ?? 0).toDouble(),
                );
              }).toList();
            }

            if (text.isNotEmpty) {
              parsed.add(
                Segment(
                  speaker: (speaker is int)
                      ? speaker
                      : int.parse(speaker.toString()),
                  text: text,
                  start: start,
                  end: end,
                  words: wordTimings,
                ),
              );
            }
          }
        } else {
          final utterances = data['results']?['utterances'];
          if (utterances is List && utterances.isNotEmpty) {
            for (var u in utterances) {
              final speaker = u['speaker'] ?? 0;
              final text = (u['transcript'] ?? u['text'] ?? '')
                  .toString()
                  .trim();
              final start = (u['start'] ?? 0).toDouble();
              final end = (u['end'] ?? 0).toDouble();

              // Extract word timings
              List<WordTiming>? wordTimings;
              if (u['words'] != null) {
                wordTimings = (u['words'] as List).map((w) {
                  return WordTiming(
                    word: w['word'] ?? '',
                    start: (w['start'] ?? 0).toDouble(),
                    end: (w['end'] ?? 0).toDouble(),
                  );
                }).toList();
              }

              if (text.isNotEmpty) {
                parsed.add(
                  Segment(
                    speaker: (speaker is int)
                        ? speaker
                        : int.parse(speaker.toString()),
                    text: text,
                    start: start,
                    end: end,
                    words: wordTimings,
                  ),
                );
              }
            }
          }
        }
      } catch (e) {
        debugPrint('Error parsing Deepgram: $e');
      }

      if (parsed.isEmpty) {
        final altText =
            data['results']?['channels']?[0]?['alternatives']?[0]?['transcript'] ??
            '';
        if ((altText ?? '').toString().isNotEmpty) {
          parsed.add(
            Segment(
              speaker: 0,
              text: altText.toString(),
              start: 0.0,
              end: duration.inSeconds.toDouble() > 0
                  ? duration.inSeconds.toDouble()
                  : 99999.0,
            ),
          );
        }
      }

      _segments = parsed;
      if (mounted) {
        setState(() {});
      }
      // push the current active indexes to notifiers so modal updates
      _activeSegmentNotifier.value = _activeSegmentIndex;
      _activeWordNotifier.value = _activeWordIndex;

      try {
        final storyId = widget.story['id'];
        if (storyId != null) {
          final jsonList = parsed.map((s) => s.toJson()).toList();
          await supabase
              .from('stories')
              .update({'transcript': jsonList})
              .eq('id', storyId);
        }
      } catch (e) {
        debugPrint('Error saving transcript to Supabase: $e');
      }
    } catch (e) {
      debugPrint('Deepgram fetch error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Transcript failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isTranscriptLoading = false);
    }
  }

  void _openMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  downloadedPath != null ? Icons.check_circle : Icons.download,
                  color: downloadedPath != null ? Colors.green : Colors.black,
                ),
                title: Text(
                  downloadedPath != null
                      ? "Downloaded (Offline Ready)"
                      : "Download for Offline",
                ),
                onTap: () async {
                  Navigator.pop(context);
                  await _downloadAudio();
                },
              ),
              ListTile(
                leading: const Icon(Icons.close),
                title: const Text("Close"),
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
        );
      },
    );
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

  Future<List<int>> _downloadAudioBytes(String url) async {
    final uri = Uri.parse(url);
    final res = await http.get(uri);
    if (res.statusCode == 200) {
      return res.bodyBytes;
    } else {
      throw Exception('Failed to download audio: ${res.statusCode}');
    }
  }

  void _openTranscriptFullScreen() async {
    final audioUrl = widget.isEpisode
        ? widget.episode!['audio_url']?.toString() ?? ''
        : widget.story['audio_url']?.toString() ?? '';

    if (_segments.isEmpty && !_isTranscriptLoading) {
      await _fetchTranscriptFromDeepgramAndSave(audioUrl);
    }

    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      enableDrag: true,
      builder: (ctx) {
        return TranscriptModal(
          segments: _segments,
          isLoading: _isTranscriptLoading,
          activeSegmentNotifier: _activeSegmentNotifier,
          activeWordNotifier: _activeWordNotifier,
          position: position,
          isPlaying: isPlaying,
          speakerColors: _speakerColors,
          storyTitle: widget.story['title'] ?? 'Untitled',
          audioUrl: audioUrl,
          onGenerateTranscript: () async {
            await _fetchTranscriptFromDeepgramAndSave(audioUrl);
          },
          onSegmentTap: (segment) {
            _player.seek(
              Duration(milliseconds: (segment.start * 1000).toInt()),
            );
            if (!isPlaying) {
              _player.resume();
              setState(() => isPlaying = true);
              _startPositionTimer();
            }
          },
          onSeek: (seconds) {
            // seek and play
            _player.seek(Duration(milliseconds: (seconds * 1000).toInt()));
            if (!isPlaying) {
              _player.resume();
              setState(() => isPlaying = true);
              _startPositionTimer();
            }
          },
        );
      },
    );
  }

  String _timeLabel(double seconds) {
    final d = Duration(milliseconds: (seconds * 1000).toInt());
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return "$m:${s.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    final story = widget.story;
    final imageUrl = story['image_url'] ?? '';
    final title = story['title'] ?? 'Untitled';
    final author = story['author'] ?? 'Unknown';
    final genre = story['genre'] ?? 'Story';

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (imageUrl != null && imageUrl.toString().isNotEmpty)
            Positioned.fill(
              child: Opacity(
                opacity: 0.15,
                child: CachedNetworkImage(
                  imageUrl: imageUrl.toString(),
                  fit: BoxFit.cover,
                  placeholder: (context, url) =>
                      Container(color: Colors.grey[900]),
                  errorWidget: (context, url, error) =>
                      Container(color: Colors.grey[900]),
                ),
              ),
            ),
          Positioned.fill(
            child: Container(color: Colors.black.withOpacity(0.6)),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 28,
                          color: Colors.white,
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                      IconButton(
                        icon: const Icon(Icons.more_vert, color: Colors.white),
                        onPressed: () => _openMenu(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  genre,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 20),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    imageUrl: imageUrl.toString(),
                    width: 240,
                    height: 300,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      width: 240,
                      height: 300,
                      color: Colors.grey[800],
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                    errorWidget: (context, url, error) => Container(
                      width: 240,
                      height: 300,
                      color: Colors.grey[800],
                      child: const Icon(
                        Icons.music_note,
                        size: 80,
                        color: Colors.white30,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  author,
                  style: const TextStyle(color: Colors.white60, fontSize: 14),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: Icon(
                        isFavorite ? Icons.favorite : Icons.favorite_border,
                        color: isFavorite ? Colors.redAccent : Colors.white,
                        size: 26,
                      ),
                      onPressed: _toggleFavorite,
                    ),
                    const SizedBox(width: 16),
                    IconButton(
                      icon: const Icon(
                        Icons.graphic_eq,
                        color: Colors.white,
                        size: 26,
                      ),
                      onPressed: _openTranscriptFullScreen,
                    ),
                    const SizedBox(width: 16),
                    IconButton(
                      icon: Icon(
                        downloadedPath != null
                            ? Icons.check_circle
                            : Icons.download,
                        color: downloadedPath != null
                            ? Colors.green
                            : Colors.white,
                        size: 26,
                      ),
                      onPressed: () async {
                        if (downloadedPath == null) {
                          await _downloadAudio(); // your download function
                          setState(() {}); // update UI after download
                        }
                      },
                    ),
                    const SizedBox(width: 16),
                    IconButton(
                      icon: const Icon(
                        Icons.share,
                        color: Colors.white,
                        size: 26,
                      ),
                      onPressed: () {},
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Slider(
                  value: position.inSeconds.toDouble(),
                  max: duration.inSeconds.toDouble() > 0
                      ? duration.inSeconds.toDouble()
                      : 1,
                  activeColor: Colors.white,
                  inactiveColor: Colors.white30,
                  onChanged: (v) async {
                    await _player.seek(Duration(seconds: v.toInt()));
                  },
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _format(position),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        _format(duration),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: _toggleSpeed,
                      child: Text(
                        "${speed}x",
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      icon: const Icon(
                        Icons.replay_30_outlined,
                        color: Colors.white,
                      ),
                      iconSize: 36,
                      onPressed: () {
                        final newPosition =
                            position - const Duration(seconds: 30);
                        _player.seek(
                          newPosition.isNegative ? Duration.zero : newPosition,
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _togglePlayPause,
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: isLoading
                            ? const Padding(
                                padding: EdgeInsets.all(20),
                                child: CircularProgressIndicator(
                                  color: Colors.black,
                                  strokeWidth: 3,
                                ),
                              )
                            : Icon(
                                isPlaying ? Icons.pause : Icons.play_arrow,
                                size: 44,
                                color: Colors.black,
                              ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(
                        Icons.forward_30_outlined,
                        color: Colors.white,
                      ),
                      iconSize: 36,
                      onPressed: () {
                        final newPosition =
                            position + const Duration(seconds: 30);
                        _player.seek(
                          newPosition > duration ? duration : newPosition,
                        );
                      },
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      icon: Icon(
                        Icons.loop,
                        color: isLoopEnabled ? Colors.blueAccent : Colors.white,
                      ),
                      iconSize: 26,
                      onPressed: _toggleLoop,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Separate TranscriptModal Widget for better organization
class TranscriptModal extends StatefulWidget {
  final List<Segment> segments;
  final bool isLoading;

  // ACTIVE highlight tracking
  final ValueNotifier<int?> activeSegmentNotifier;
  final ValueNotifier<int?> activeWordNotifier;

  final Duration position;
  final bool isPlaying;

  final List<Color> speakerColors;
  final String storyTitle;
  final String audioUrl;

  final VoidCallback onGenerateTranscript;
  final Function(Segment) onSegmentTap;
  final void Function(double seconds) onSeek;

  const TranscriptModal({
    super.key,
    required this.segments,
    required this.isLoading,
    required this.activeSegmentNotifier,
    required this.activeWordNotifier,
    required this.position,
    required this.isPlaying,
    required this.speakerColors,
    required this.storyTitle,
    required this.audioUrl,
    required this.onGenerateTranscript,
    required this.onSegmentTap,
    required this.onSeek, // ✅ FIXED
  });

  @override
  State<TranscriptModal> createState() => _TranscriptModalState();
}

class _TranscriptModalState extends State<TranscriptModal> {
  final ScrollController _scrollController = ScrollController();
  bool _isGenerating = false;
  List<Segment> _segments = [];

  @override
  void initState() {
    super.initState();
    widget.activeSegmentNotifier.addListener(_onActiveChanged);
    widget.activeWordNotifier.addListener(_onActiveChanged);
  }

  String _timeLabel(double seconds) {
    final d = Duration(milliseconds: (seconds * 1000).toInt());
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return "$m:${s.toString().padLeft(2, '0')}";
  }

  void _onActiveChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.activeSegmentNotifier.removeListener(_onActiveChanged);
    widget.activeWordNotifier.removeListener(_onActiveChanged);
    _scrollController.dispose();
    super.dispose();
  }

  Widget _buildWordHighlightedText(
    Segment seg,
    bool isActive,
    Color speakerColor,
    int segmentIndex,
    int? activeSegmentIndex,
    int? activeWordIndex,
  ) {
    // fallback if no word timings
    if (seg.words == null || seg.words!.isEmpty) {
      return Text(
        seg.text,
        style: TextStyle(
          color: isActive ? Colors.white : Colors.white60,
          fontSize: 16,
          height: 1.6,
          fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
        ),
      );
    }

    final isActiveSegment = activeSegmentIndex == segmentIndex;

    // build TextSpan list with recognizers
    final spans = <TextSpan>[];
    for (var entry in seg.words!.asMap().entries) {
      final wordIndex = entry.key;
      final w = entry.value;

      // determine the absolute seconds to seek to for this word
      // prefer absolute word.start if it looks like absolute (>= seg.start),
      // otherwise assume relative and add segment.start
      double seekSeconds;
      if (w.start >= seg.start && w.start <= seg.end) {
        // looks absolute
        seekSeconds = w.start;
      } else {
        // relative to segment
        seekSeconds = seg.start + w.start;
      }

      final bool isActiveWord =
          isActiveSegment && (activeWordIndex == wordIndex);

      final recognizer = TapGestureRecognizer()
        ..onTap = () {
          try {
            widget.onSeek(seekSeconds);
          } catch (e) {
            debugPrint('onSeek failed: $e');
          }
        };

      spans.add(
        TextSpan(
          text: "${w.word} ",
          recognizer: recognizer,
          style: TextStyle(
            color: isActiveWord
                ? speakerColor
                : isActiveSegment
                ? Colors.white
                : Colors.white60,
            fontSize: 17,
            height: 1.6,
            fontWeight: isActiveWord ? FontWeight.w700 : FontWeight.w500,
            shadows: isActiveWord
                ? [Shadow(color: speakerColor.withOpacity(0.8), blurRadius: 14)]
                : [],
            decoration: TextDecoration.none,
          ),
        ),
      );
    }

    return RichText(text: TextSpan(children: spans));
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF1A1A2E), Color(0xFF0F0F1E)],
            ),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'TRANSCRIPT',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.storyTitle,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const Divider(color: Colors.white12, height: 1),

              // CONTENT
              Expanded(
                child: _isGenerating || widget.isLoading
                    ? _buildLoading()
                    : widget.segments.isEmpty
                    ? _buildEmptyState()
                    : _buildTranscriptList(scrollController),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          CircularProgressIndicator(color: Colors.white),
          SizedBox(height: 16),
          Text(
            'Generating transcript...',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Colors.white10,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.text_fields,
              size: 48,
              color: Colors.white38,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'No transcript available',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Generate a transcript to follow along',
            style: TextStyle(color: Colors.white60, fontSize: 14),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () async {
              setState(() => _isGenerating = true);
              widget.onGenerateTranscript();
              setState(() => _isGenerating = false);
            },
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Generate Transcript'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTranscriptList(ScrollController scrollController) {
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      itemCount: widget.segments.length,
      itemBuilder: (context, index) {
        final seg = widget.segments[index];
        final speakerColor =
            widget.speakerColors[seg.speaker % widget.speakerColors.length];

        return GestureDetector(
          onTap: () => widget.onSegmentTap(seg),
          child: ValueListenableBuilder<int?>(
            valueListenable: widget.activeSegmentNotifier,
            builder: (context, activeSegmentIndex, _) {
              final isActive = activeSegmentIndex == index;

              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: isActive
                      ? LinearGradient(
                          colors: [
                            speakerColor.withOpacity(0.2),
                            speakerColor.withOpacity(0.05),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  color: !isActive ? Colors.white.withOpacity(0.03) : null,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isActive
                        ? speakerColor.withOpacity(0.8)
                        : Colors.white.withOpacity(0.08),
                    width: isActive ? 2.5 : 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // time + speaker
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Speaker ${seg.speaker + 1}",
                          style: TextStyle(
                            color: isActive ? speakerColor : Colors.white70,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          "${_timeLabel(seg.start)} - ${_timeLabel(seg.end)}",
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // LIVE WORD HIGHLIGHT
                    ValueListenableBuilder<int?>(
                      valueListenable: widget.activeWordNotifier,
                      builder: (context, activeWordIndex, __) {
                        return _buildWordHighlightedText(
                          seg,
                          isActive,
                          speakerColor,
                          index,
                          activeSegmentIndex,
                          activeWordIndex,
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}
