
class QuizQuestion {
  final int id;
  final String category;
  final String difficulty;
  final String imagePath;
  final String correctAnswer;
  final List<String> incorrectAnswers;

  // Milestone 7: educational feedback.
  final String explanation;
  final Map<String, String> incorrectExplanations;

  const QuizQuestion({
    required this.id,
    required this.category,
    required this.difficulty,
    required this.imagePath,
    required this.correctAnswer,
    required this.incorrectAnswers,
    this.explanation = '',
    this.incorrectExplanations = const {},
  });

  factory QuizQuestion.fromJson(
    Map<String, dynamic> json,
  ) {
    final id = json['id'];

    if (id is! int) {
      throw const FormatException(
        'A question must have an integer ID.',
      );
    }

    final rawAnswers = json['incorrectAnswers'];

    if (rawAnswers is! List) {
      throw FormatException(
        'Question $id must have an incorrectAnswers array.',
      );
    }

    final incorrectAnswers = <String>[];

    for (final answer in rawAnswers) {
      if (answer is! String) {
        throw FormatException(
          'Question $id contains a non-text answer.',
        );
      }

      incorrectAnswers.add(answer);
    }

    // New explanatory fields are optional.
    final rawExplanation = json['explanation'];

    if (rawExplanation != null &&
        rawExplanation is! String) {
      throw FormatException(
        'Question $id has an invalid explanation.',
      );
    }

    final rawIncorrectExplanations =
        json['incorrectExplanations'];

    final incorrectExplanations = <String, String>{};

    if (rawIncorrectExplanations != null) {
      if (rawIncorrectExplanations
          is! Map<String, dynamic>) {
        throw FormatException(
          'Question $id must use an object for '
          'incorrectExplanations.',
        );
      }

      for (final entry
          in rawIncorrectExplanations.entries) {
        if (entry.value is! String ||
            (entry.value as String).trim().isEmpty) {
          throw FormatException(
            'Question $id has an invalid explanation '
            'for "${entry.key}".',
          );
        }

        incorrectExplanations[entry.key] =
            (entry.value as String).trim();
      }
    }

    // Preserve validation of the original fields.
    final question = QuizQuestion(
      id: id,
      category: json['category'] as String,
      difficulty: json['difficulty'] as String,
      imagePath: json['imagePath'] as String,
      correctAnswer: json['correctAnswer'] as String,
      incorrectAnswers: incorrectAnswers,
      explanation: (rawExplanation as String?)?.trim() ?? '',
      incorrectExplanations: incorrectExplanations,
    );

    if (incorrectAnswers.length != 3) {
      throw FormatException(
        'Question $id must have exactly '
        'three incorrect answers.',
      );
    }

    final options = [
      question.correctAnswer,
      ...question.incorrectAnswers,
    ];

    if (options.any((answer) => answer.trim().isEmpty)) {
      throw FormatException(
        'Question $id contains an empty answer.',
      );
    }

    final uniqueOptions = options
        .map((answer) => answer.trim().toLowerCase())
        .toSet();

    if (uniqueOptions.length != 4) {
      throw FormatException(
        'Question $id must have four distinct answers.',
      );
    }

    if (question.imagePath.trim().isEmpty ||
        question.category.trim().isEmpty ||
        question.difficulty.trim().isEmpty) {
      throw FormatException(
        'Question $id contains missing metadata.',
      );
    }

    // Every incorrect explanation must match
    // an actual incorrect answer.
    for (final answer
        in incorrectExplanations.keys) {
      if (!incorrectAnswers.contains(answer)) {
        throw FormatException(
          'Question $id has an explanation for '
          '"$answer", but that answer does not exist.',
        );
      }
    }

    return question;
  }
}
