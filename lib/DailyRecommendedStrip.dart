import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class DailyRecommendedStrip extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  const DailyRecommendedStrip({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 210,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final it = items[i];
          return Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: CachedNetworkImage(
                  imageUrl: it['image_url'],
                  width: 160,
                  height: 210,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(color: Colors.black12),
                ),
              ),
              Positioned(
                left: 10, bottom: 10,
                child: Text(
                  it['title'] ?? '',
                  style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14, shadows: [Shadow(blurRadius: 4)]
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
