
import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/quiz_question.dart';

class QuizRepository {
  static Future<List<QuizQuestion>> loadQuestions() async {
    // Read the bundled JSON file.
    final jsonString = await rootBundle.loadString(
      'assets/data/questions.json',
    );

    // Convert the JSON string to Dart data.
    final decoded = jsonDecode(jsonString);

    if (decoded is! List) {
      throw const FormatException(
        'The question library must be a JSON array.',
      );
    }

    final questions = <QuizQuestion>[];

    for (final entry in decoded) {
      if (entry is! Map<String, dynamic>) {
        throw const FormatException(
          'Every question must be a JSON object.',
        );
      }

      questions.add(QuizQuestion.fromJson(entry));
    }

    // A playable round requires at least five questions.
    if (questions.length < 5) {
      throw const FormatException(
        'The question library needs at least five questions.',
      );
    }

    // Every question must have a unique identifier.
    final ids = questions.map((question) => question.id).toSet();

    if (ids.length != questions.length) {
      throw const FormatException(
        'Duplicate question IDs were found.',
      );
    }

    return questions;
  }
}
