
import 'dart:math';

import '../data/history_repository.dart';
import '../models/quiz_question.dart';

class AdaptiveQuestionSelector {
  // Calculate the selection weight for one question.
  static double weightFor(
    QuestionPerformance? performance,
  ) {
    // Unseen questions receive an exploration bonus.
    if (performance == null ||
        performance.attempts == 0) {
      return 4.0;
    }

    final attempts = performance.attempts;
    final incorrect = performance.incorrect;

    final smoothedError =
        (incorrect + 1) / (attempts + 2);

    return 1.0 + (4.0 * smoothedError);
  }

  // Select questions using weighted random sampling
  // WITHOUT replacement.
  static List<QuizQuestion> selectQuestions({
    required List<QuizQuestion> available,
    required int count,
    required Map<int, QuestionPerformance> performance,
    Random? random,
  }) {
    if (count < 1 || count > available.length) {
      throw RangeError.range(
        count,
        1,
        available.length,
        'count',
      );
    }

    final rng = random ?? Random();

    final remaining = List<QuizQuestion>.of(available);
    final selected = <QuizQuestion>[];

    for (int round = 0; round < count; round++) {
      // Calculate the total weight of all
      // questions that have not been selected.
      double totalWeight = 0;

      for (final question in remaining) {
        totalWeight += weightFor(
          performance[question.id],
        );
      }

      // Draw a random position along that weight.
      double draw = rng.nextDouble() * totalWeight;

      int chosenIndex = remaining.length - 1;

      for (int i = 0; i < remaining.length; i++) {
        final questionWeight = weightFor(
          performance[remaining[i].id],
        );

        draw -= questionWeight;

        if (draw < 0) {
          chosenIndex = i;
          break;
        }
      }

      // Remove the selected question from the pool.
      // This prevents repetition within the round.
      selected.add(remaining.removeAt(chosenIndex));
    }

    return selected;
  }
}
