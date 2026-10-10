
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/data/history_repository.dart';
import 'package:flutter_application_1/models/quiz_question.dart';
import 'package:flutter_application_1/services/adaptive_question_selector.dart';

void main() {
  final questions = List.generate(
    6,
    (index) => QuizQuestion(
      id: index + 1,
      category: 'Geography',
      difficulty: 'Easy',
      imagePath: 'assets/images/example.jpg',
      correctAnswer: 'Glacier',
      incorrectAnswers: const [
        'Plateau',
        'Canyon',
        'Volcano',
      ],
    ),
  );

  test('Missed questions receive greater weight', () {
    const missed = QuestionPerformance(
      questionId: 1,
      attempts: 5,
      correct: 0,
    );

    const mastered = QuestionPerformance(
      questionId: 2,
      attempts: 5,
      correct: 5,
    );

    expect(
      AdaptiveQuestionSelector.weightFor(missed),
      greaterThan(
        AdaptiveQuestionSelector.weightFor(mastered),
      ),
    );
  });

  test('Unseen questions retain useful priority', () {
    const mastered = QuestionPerformance(
      questionId: 2,
      attempts: 5,
      correct: 5,
    );

    expect(
      AdaptiveQuestionSelector.weightFor(null),
      greaterThan(
        AdaptiveQuestionSelector.weightFor(mastered),
      ),
    );
  });

  test('A question never repeats within a round', () {
    final selected =
        AdaptiveQuestionSelector.selectQuestions(
      available: questions,
      count: 5,
      performance: {},
      random: Random(42),
    );

    final ids = selected.map((q) => q.id).toList();

    expect(selected.length, 5);
    expect(ids.toSet().length, 5);
  });

  test('More heavily missed questions are selected more often',
      () {
    const missed = QuestionPerformance(
      questionId: 1,
      attempts: 5,
      correct: 0,
    );

    const mastered = QuestionPerformance(
      questionId: 2,
      attempts: 5,
      correct: 5,
    );

    final rng = Random(42);
    int missedSelections = 0;
    int masteredSelections = 0;

    for (int i = 0; i < 1000; i++) {
      final selected =
          AdaptiveQuestionSelector.selectQuestions(
        available: questions.take(2).toList(),
        count: 1,
        performance: {
          1: missed,
          2: mastered,
        },
        random: rng,
      );

      if (selected.single.id == 1) {
        missedSelections++;
      } else {
        masteredSelections++;
      }
    }

    expect(
      missedSelections,
      greaterThan(masteredSelections),
    );
  });
}
