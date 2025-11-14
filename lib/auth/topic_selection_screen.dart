import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:manga/providers/supabase_provider.dart';
import 'package:manga/main_nav.dart';

class TopicSelectionScreen extends ConsumerStatefulWidget {
  const TopicSelectionScreen({super.key});

  @override
  ConsumerState<TopicSelectionScreen> createState() =>
      _TopicSelectionScreenState();
}

class _TopicSelectionScreenState extends ConsumerState<TopicSelectionScreen> {
  List<Map<String, dynamic>> topics = []; // ✅ topics from supabase
  List<String> selectedTopics = []; // ✅ selected topic names
  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadTopicsFromSupabase();
  }

  // ✅ Fetch topics dynamically from Supabase
  Future<void> loadTopicsFromSupabase() async {
    final supabase = ref.read(supabaseClientProvider);

    final data = await supabase.from("topics").select("*");

    setState(() {
      topics = List<Map<String, dynamic>>.from(data);
      loading = false;
    });
  }

  void toggleTopic(String name) {
    setState(() {
      if (selectedTopics.contains(name)) {
        selectedTopics.remove(name);
      } else if (selectedTopics.length < 3) {
        selectedTopics.add(name);
      }
    });
  }

  Future<void> saveSelectedGenres() async {
    if (selectedTopics.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select at least 3 topics")),
      );
      return;
    }

    final supabase = ref.read(supabaseClientProvider);
    final userId = supabase.auth.currentUser!.id;

    await supabase.from("user_preferences").upsert({
      "user_id": userId,
      "genres": selectedTopics,
      "favourites": [], // ✅ FIX: ensure non-null array
    }, onConflict: "user_id");

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const MainNav()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white,
                    Colors.white,
                    Colors.white,
                    Colors.white,
                    Colors.white,
                    Colors.white,
                    Colors.white,
                    Color(0xFFD4BFFF),
                  ],
                ),
              ),
              child: SafeArea(
                child: Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 16),
                            const Text(
                              "Welcome to AudioReads",
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              "Pick 3 topics you like",
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.black54,
                              ),
                            ),
                            const SizedBox(height: 20),

                            // ✅ Dynamic topic grid
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: topics.length,
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 3,
                                    childAspectRatio: 0.73,
                                    crossAxisSpacing: 10,
                                    mainAxisSpacing: 10,
                                  ),
                              itemBuilder: (context, index) {
                                final topic = topics[index];
                                final isSelected = selectedTopics.contains(
                                  topic["name"],
                                );

                                return GestureDetector(
                                  onTap: () {
                                    if (!isSelected &&
                                        selectedTopics.length == 3) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            "You can choose only 3",
                                          ),
                                        ),
                                      );
                                      return;
                                    }
                                    toggleTopic(topic["name"]);
                                  },
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(14),
                                      image: DecorationImage(
                                        image: NetworkImage(topic["image_url"]),
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                    child: Stack(
                                      children: [
                                        Container(
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                            color: Colors.black.withOpacity(
                                              isSelected ? 0.6 : 0.2,
                                            ),
                                          ),
                                        ),
                                        Positioned(
                                          bottom: 10,
                                          left: 12,
                                          child: Text(
                                            topic["name"].toString().replaceAll(
                                              " ",
                                              "\n",
                                            ), // ✅ Key change
                                            textAlign: TextAlign.left,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              color: Colors.white,
                                              fontWeight: FontWeight.w600,
                                              height:
                                                  1.1, // reduces line spacing
                                            ),
                                          ),
                                        ),

                                        if (isSelected)
                                          Positioned(
                                            right: 6,
                                            top: 6,
                                            child: Container(
                                              padding: const EdgeInsets.all(4),
                                              decoration: const BoxDecoration(
                                                color: Colors.white,
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(
                                                Icons.check,
                                                size: 16,
                                                color: Colors.black,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),

                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ),

                    // ✅ Done button
                    Container(
                      padding: const EdgeInsets.only(bottom: 20, top: 10),
                      child: Center(
                        child: Container(
                          width: 120,
                          height: 44,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFF6B9D), Color(0xFFFF8FB3)],
                            ),
                            borderRadius: BorderRadius.circular(25),
                          ),
                          child: ElevatedButton(
                            onPressed: saveSelectedGenres,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(25),
                              ),
                            ),
                            child: const Text(
                              "DONE",
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
