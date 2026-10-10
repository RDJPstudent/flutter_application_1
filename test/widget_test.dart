
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/models/quiz_question.dart';

void main() {
  test('QuizQuestion loads valid question data', () {
    final question = QuizQuestion.fromJson({
      'id': 1,
      'category': 'Geography',
      'difficulty': 'Easy',
      'imagePath': 'assets/images/mountain_range.jpg',
      'correctAnswer': 'Mountain range',
      'incorrectAnswers': [
        'Plateau',
        'Valley',
        'Mountain pass',
      ],
    });

    expect(question.id, 1);
    expect(question.correctAnswer, 'Mountain range');
    expect(question.incorrectAnswers.length, 3);
  });

  test('QuizQuestion rejects duplicate answers', () {
    expect(
      () => QuizQuestion.fromJson({
        'id': 2,
        'category': 'Geography',
        'difficulty': 'Easy',
        'imagePath': 'assets/images/test.jpg',
        'correctAnswer': 'Canyon',
        'incorrectAnswers': [
          'Canyon',
          'Glacier',
          'Valley',
        ],
      }),
      throwsFormatException,
    );
  });
}
