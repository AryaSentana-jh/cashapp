import 'package:google_generative_ai/google_generative_ai.dart';
import 'dart:io';

void main() async {
  final apiKey = 'AIzaSyD5q6O5lk2oUa9GHFsjXk24yxHZBVzSD0k';
  final model = GenerativeModel(model: 'gemini-1.5-flash-001', apiKey: apiKey);
  final prompt = 'Say hello';

  try {
    final response = await model.generateContent([Content.text(prompt)]);
    print('Success: ${response.text}');
  } catch (e) {
    print('Error: $e');
  }
  exit(0);
}
