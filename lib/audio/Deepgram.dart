import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

Future<void> deepgramTranscribe(File audioFile) async {
  final apiKey = "9f257c1c680b180d1a80711004a8439c198d6670";

  final url = Uri.parse(
    "https://api.deepgram.com/v1/listen?diarize=true&punctuate=true",
  );

  final bytes = await audioFile.readAsBytes();

  final response = await http.post(
    url,
    headers: {
      "Authorization": "Token $apiKey",
      "Content-Type": "audio/wav", // or audio/mpeg for mp3
    },
    body: bytes,
  );

  final data = jsonDecode(response.body);

  final results =
      data["results"]["channels"][0]["alternatives"][0]["paragraphs"]["paragraphs"];

  print("===== SPEAKER OUTPUT =====");

  for (var p in results) {
    print("Speaker ${p['speaker']}: ${p['text']}");
  }
}
