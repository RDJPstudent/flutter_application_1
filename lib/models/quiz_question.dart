
class QuizQuestion {
  final int id;
  final String category;
  final String difficulty;
  final String imagePath;
  final String correctAnswer;
  final List<String> incorrectAnswers;

  const QuizQuestion({
    required this.id,
    required this.category,
    required this.difficulty,
    required this.imagePath,
    required this.correctAnswer,
    required this.incorrectAnswers,
  });

  factory QuizQuestion.fromJson(Map<String, dynamic> json) {
    final incorrectAnswers =
        (json['incorrectAnswers'] as List<dynamic>)
            .map((answer) => answer as String)
            .toList();

    final question = QuizQuestion(
      id: json['id'] as int,
      category: json['category'] as String,
      difficulty: json['difficulty'] as String,
      imagePath: json['imagePath'] as String,
      correctAnswer: json['correctAnswer'] as String,
      incorrectAnswers: incorrectAnswers,
    );

    if (incorrectAnswers.length != 3) {
      throw FormatException(
        'Question ${question.id} must have '
        'exactly three incorrect answers.',
      );
    }

    final options = [
      question.correctAnswer,
      ...question.incorrectAnswers,
    ];

    if (options.any((answer) => answer.trim().isEmpty)) {
      throw FormatException(
        'Question ${question.id} contains an empty answer.',
      );
    }

    final uniqueOptions = options
        .map((answer) => answer.trim().toLowerCase())
        .toSet();

    if (uniqueOptions.length != 4) {
      throw FormatException(
        'Question ${question.id} must have '
        'four distinct answers.',
      );
    }

    if (question.imagePath.trim().isEmpty ||
        question.category.trim().isEmpty ||
        question.difficulty.trim().isEmpty) {
      throw FormatException(
        'Question ${question.id} has missing metadata.',
      );
    }

    return question;
  }
}
