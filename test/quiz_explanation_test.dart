
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/models/quiz_question.dart';

void main() {
  final originalQuestion = <String, dynamic>{
    'id': 1,
    'category': 'Geography',
    'difficulty': 'Easy',
    'imagePath': 'assets/images/mountain_range.jpg',
    'correctAnswer': 'Mountain range',
    'incorrectAnswers': [
      'Mountain pass',
      'Plateau',
      'Valley',
    ],
  };

  test('Older questions still load', () {
    final question = QuizQuestion.fromJson(
      originalQuestion,
    );

    expect(question.explanation, isEmpty);
    expect(question.incorrectExplanations, isEmpty);
  });

  test('New explanations load correctly', () {
    final data = {
      ...originalQuestion,
      'explanation': 'A connected mountain system.',
      'incorrectExplanations': {
        'Mountain pass': 'A route through mountains.',
      },
    };

    final question = QuizQuestion.fromJson(data);

    expect(
      question.explanation,
      'A connected mountain system.',
    );

    expect(
      question.incorrectExplanations['Mountain pass'],
      'A route through mountains.',
    );
  });

  test('Unknown answer explanations are rejected', () {
    final data = {
      ...originalQuestion,
      'incorrectExplanations': {
        'River delta': 'Not a mountain range.',
      },
    };

    expect(
      () => QuizQuestion.fromJson(data),
      throwsFormatException,
    );
  });
}
