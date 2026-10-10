
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

// An answer waiting to be saved.
class HistoryAnswer {
  final int questionId;
  final String category;
  final String difficulty;
  final String selectedAnswer;
  final String correctAnswer;

  const HistoryAnswer({
    required this.questionId,
    required this.category,
    required this.difficulty,
    required this.selectedAnswer,
    required this.correctAnswer,
  });

  bool get isCorrect => selectedAnswer == correctAnswer;
}

// Statistics for one category.
class CategoryPerformance {
  final String category;
  final int answered;
  final int correct;

  const CategoryPerformance({
    required this.category,
    required this.answered,
    required this.correct,
  });

  double get accuracy =>
      answered == 0 ? 0 : correct / answered;
}

// A recently completed round.
class RecentRound {
  final DateTime completedAt;
  final String category;
  final String difficulty;
  final int questionCount;
  final int correctCount;

  const RecentRound({
    required this.completedAt,
    required this.category,
    required this.difficulty,
    required this.questionCount,
    required this.correctCount,
  });
}

// A concept the player has answered incorrectly.
class MissedConcept {
  final String category;
  final String correctAnswer;
  final int misses;

  const MissedConcept({
    required this.category,
    required this.correctAnswer,
    required this.misses,
  });
}

// All information needed by the statistics screen.
class QuizStatistics {
  final int completedRounds;
  final int totalAnswers;
  final int correctAnswers;
  final List<CategoryPerformance> categories;
  final List<RecentRound> recentRounds;
  final List<MissedConcept> missedConcepts;

  const QuizStatistics({
    required this.completedRounds,
    required this.totalAnswers,
    required this.correctAnswers,
    required this.categories,
    required this.recentRounds,
    required this.missedConcepts,
  });

  double get accuracy =>
      totalAnswers == 0 ? 0 : correctAnswers / totalAnswers;
}


class QuestionPerformance {
  final int questionId;
  final int attempts;
  final int correct;

  const QuestionPerformance({
    required this.questionId,
    required this.attempts,
    required this.correct,
  });

  int get incorrect => attempts - correct;

  double get accuracy =>
      attempts == 0 ? 0 : correct / attempts;
}


class HistoryRepository {
  static Future<Database>? _databaseFuture;

  static Future<Database> get _database {
    return _databaseFuture ??= _openDatabase();
  }

  // Open or create the local SQLite database.
  static Future<Database> _openDatabase() async {
    final databasePath = p.join(
      await getDatabasesPath(),
      'image_quiz_history.db',
    );

    return openDatabase(
      databasePath,
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE quiz_rounds (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            completed_at TEXT NOT NULL,
            selected_category TEXT NOT NULL,
            selected_difficulty TEXT NOT NULL,
            question_count INTEGER NOT NULL,
            correct_count INTEGER NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE quiz_answers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            round_id INTEGER NOT NULL,
            question_id INTEGER NOT NULL,
            category TEXT NOT NULL,
            difficulty TEXT NOT NULL,
            selected_answer TEXT NOT NULL,
            correct_answer TEXT NOT NULL,
            is_correct INTEGER NOT NULL,
            FOREIGN KEY (round_id)
              REFERENCES quiz_rounds(id)
              ON DELETE CASCADE,
            UNIQUE (round_id, question_id)
          )
        ''');

        await db.execute('''
          CREATE INDEX idx_quiz_answers_round
          ON quiz_answers(round_id)
        ''');
      },
    );
  }

  // Save a full round atomically.
  static Future<void> saveRound({
    required String category,
    required String difficulty,
    required List<HistoryAnswer> answers,
  }) async {
    if (answers.isEmpty) {
      throw ArgumentError('Cannot save an empty round.');
    }

    final db = await _database;

    final correctCount =
        answers.where((answer) => answer.isCorrect).length;

    await db.transaction((transaction) async {
      final roundId = await transaction.insert(
        'quiz_rounds',
        {
          'completed_at':
              DateTime.now().toUtc().toIso8601String(),
          'selected_category': category,
          'selected_difficulty': difficulty,
          'question_count': answers.length,
          'correct_count': correctCount,
        },
      );

      for (final answer in answers) {
        await transaction.insert(
          'quiz_answers',
          {
            'round_id': roundId,
            'question_id': answer.questionId,
            'category': answer.category,
            'difficulty': answer.difficulty,
            'selected_answer': answer.selectedAnswer,
            'correct_answer': answer.correctAnswer,
            'is_correct': answer.isCorrect ? 1 : 0,
          },
        );
      }
    });
  }

  // Retrieve aggregated statistics and recent history.
  static Future<QuizStatistics> loadStatistics() async {
    final db = await _database;

    final totals = await db.rawQuery('''
      SELECT
        COUNT(*) AS rounds,
        COALESCE(SUM(question_count), 0) AS answered,
        COALESCE(SUM(correct_count), 0) AS correct
      FROM quiz_rounds
    ''');

    final categoryRows = await db.rawQuery('''
      SELECT
        category,
        COUNT(*) AS answered,
        SUM(is_correct) AS correct
      FROM quiz_answers
      GROUP BY category
      ORDER BY category
    ''');

    final recentRows = await db.rawQuery('''
      SELECT
        completed_at,
        selected_category,
        selected_difficulty,
        question_count,
        correct_count
      FROM quiz_rounds
      ORDER BY id DESC
      LIMIT 20
    ''');

    final missedRows = await db.rawQuery('''
      SELECT
        category,
        correct_answer,
        COUNT(*) AS misses
      FROM quiz_answers
      WHERE is_correct = 0
      GROUP BY category, correct_answer
      ORDER BY misses DESC, correct_answer
      LIMIT 5
    ''');

    final total = totals.first;

    return QuizStatistics(
      completedRounds: (total['rounds'] as num).toInt(),
      totalAnswers: (total['answered'] as num).toInt(),
      correctAnswers: (total['correct'] as num).toInt(),

      categories: categoryRows.map((row) {
        return CategoryPerformance(
          category: row['category'] as String,
          answered: (row['answered'] as num).toInt(),
          correct: (row['correct'] as num).toInt(),
        );
      }).toList(),

      recentRounds: recentRows.map((row) {
        return RecentRound(
          completedAt: DateTime.parse(
            row['completed_at'] as String,
          ).toLocal(),
          category: row['selected_category'] as String,
          difficulty: row['selected_difficulty'] as String,
          questionCount:
              (row['question_count'] as num).toInt(),
          correctCount:
              (row['correct_count'] as num).toInt(),
        );
      }).toList(),

      missedConcepts: missedRows.map((row) {
        return MissedConcept(
          category: row['category'] as String,
          correctAnswer: row['correct_answer'] as String,
          misses: (row['misses'] as num).toInt(),
        );
      }).toList(),
    );
  }

  
static Future<Map<int, QuestionPerformance>>
    loadQuestionPerformance() async {
  final db = await _database;

  final rows = await db.rawQuery('''
    SELECT
      question_id,
      COUNT(*) AS attempts,
      COALESCE(SUM(is_correct), 0) AS correct
    FROM quiz_answers
    GROUP BY question_id
  ''');

  final performance = <int, QuestionPerformance>{};

  for (final row in rows) {
    final questionId =
        (row['question_id'] as num).toInt();

    performance[questionId] = QuestionPerformance(
      questionId: questionId,
      attempts: (row['attempts'] as num).toInt(),
      correct: (row['correct'] as num).toInt(),
    );
  }

  return performance;
}


}
