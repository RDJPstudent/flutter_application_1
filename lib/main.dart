import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'data/quiz_repository.dart';
import 'models/quiz_question.dart';

import 'data/history_repository.dart';
import 'screens/statistics_screen.dart';

import 'services/adaptive_question_selector.dart';

void main() {
  runApp(const ImageQuizApp());
}

// One record per answer given by the player.
class AnswerRecord {
  final QuizQuestion question;
  final String selectedAnswer;

  const AnswerRecord({required this.question, required this.selectedAnswer});

  bool get isCorrect => selectedAnswer == question.correctAnswer;
}

// The three main states of our application.
enum GameScreen { setup, quiz, feedback, results }

enum QuizMode { random, adaptive }

class ImageQuizApp extends StatelessWidget {
  const ImageQuizApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Image Identification',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const QuizScreen(),
    );
  }
}

class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  static const String all = '__all__';

  QuizMode _selectedMode = QuizMode.random;

  bool _isPreparingQuiz = false;

  // Full question library.
  List<QuizQuestion> _questionBank = [];

  // Game configuration.
  String _selectedCategory = all;
  String _selectedDifficulty = all;
  int _questionCount = 5;

  // Active round.
  List<QuizQuestion> _questions = [];
  List<String> _options = [];
  final List<AnswerRecord> _answers = [];

  int _currentIndex = 0;
  String? _selectedAnswer;

  // Screen and loading state.
  GameScreen _screen = GameScreen.setup;
  bool _isLoading = true;
  String? _loadError;
  bool _isSavingHistory = false;
  String? _historyError;

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  // --------------------------------------------------
  // QUESTION LIBRARY
  // --------------------------------------------------

  Future<void> _loadQuestions() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final questions = await QuizRepository.loadQuestions();

      if (!mounted) return;

      setState(() {
        _questionBank = questions;
        _selectedCategory = all;
        _selectedDifficulty = all;
        _questionCount = math.min(5, questions.length);
        _screen = GameScreen.setup;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _loadError = error.toString();
        _isLoading = false;
      });
    }
  }

  // Discover categories from JSON.
  List<String> get _categories {
    final values = _questionBank
        .map((question) => question.category)
        .toSet()
        .toList();

    values.sort();
    return values;
  }

  // Only show difficulties for the current category.
  List<String> get _difficulties {
    final values = _questionBank
        .where(
          (question) =>
              _selectedCategory == all ||
              question.category == _selectedCategory,
        )
        .map((question) => question.difficulty)
        .toSet()
        .toList();

    values.sort();
    return values;
  }

  // Apply both selected filters.
  List<QuizQuestion> get _filteredQuestions {
    return _questionBank.where((question) {
      final matchesCategory =
          _selectedCategory == all || question.category == _selectedCategory;

      final matchesDifficulty =
          _selectedDifficulty == all ||
          question.difficulty == _selectedDifficulty;

      return matchesCategory && matchesDifficulty;
    }).toList();
  }

  // Prevent selections larger than the available pool.
  // Limit rounds to 20 questions for this milestone.
  int get _maximumQuestionCount => math.min(20, _filteredQuestions.length);

  void _changeCategory(String? value) {
    if (value == null) return;

    setState(() {
      _selectedCategory = value;
      _selectedDifficulty = all;

      _questionCount = math.min(5, _filteredQuestions.length);
    });
  }

  void _changeDifficulty(String? value) {
    if (value == null) return;

    setState(() {
      _selectedDifficulty = value;

      _questionCount = math.min(5, _filteredQuestions.length);
    });
  }

  // --------------------------------------------------
  // GAME LOGIC
  // --------------------------------------------------

  Future<void> _startGame() async {
    if (_isPreparingQuiz) return;

    final available = _filteredQuestions;
    final count = _questionCount;
    final mode = _selectedMode;

    // Validate the requested round.
    if (available.isEmpty || count < 1 || count > available.length) {
      return;
    }

    setState(() {
      _isPreparingQuiz = true;
    });

    try {
      late final List<QuizQuestion> selectedQuestions;

      if (mode == QuizMode.adaptive) {
        // Read the saved history from SQLite.
        final performance = await HistoryRepository.loadQuestionPerformance();

        // Apply weighted random selection.
        selectedQuestions = AdaptiveQuestionSelector.selectQuestions(
          available: available,
          count: count,
          performance: performance,
        );
      } else {
        // Preserve the original equal-probability mode.
        final shuffled = List<QuizQuestion>.of(available)..shuffle();

        selectedQuestions = shuffled.take(count).toList();
      }

      if (!mounted) return;

      // Both modes use the same gameplay mechanics.
      setState(() {
        _questions = selectedQuestions;

        _answers.clear();
        _currentIndex = 0;
        _selectedAnswer = null;

        _isSavingHistory = false;
        _historyError = null;

        _shuffleOptions();

        _screen = GameScreen.quiz;
        _isPreparingQuiz = false;
      });
    } catch (error) {
      debugPrint('Quiz preparation failed: $error');

      if (!mounted) return;

      setState(() {
        _isPreparingQuiz = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not prepare quiz: $error')));
    }
  }

  void _shuffleOptions() {
    final question = _questions[_currentIndex];

    _options = [question.correctAnswer, ...question.incorrectAnswers]
      ..shuffle();
  }

  void _selectAnswer(String answer) {
    // Prevent changing a submitted answer.
    if (_selectedAnswer != null) return;

    setState(() {
      _selectedAnswer = answer;

      _answers.add(
        AnswerRecord(
          question: _questions[_currentIndex],
          selectedAnswer: answer,
        ),
      );

      // Immediately display educational feedback.
      _screen = GameScreen.feedback;
    });
  }

  Future<void> _nextQuestion() async {
    // A question must be answered before advancing.
    if (_selectedAnswer == null || _isSavingHistory) {
      return;
    }

    // Continue normally if more questions remain.
    if (_currentIndex < _questions.length - 1) {
      setState(() {
        _currentIndex++;
        _selectedAnswer = null;
        _shuffleOptions();

        // Return from feedback to image identification.
        _screen = GameScreen.quiz;
      });

      return;
    }

    // The final question has been answered.
    // Save the completed round before showing results.
    setState(() {
      _isSavingHistory = true;
      _historyError = null;
    });

    try {
      final historyAnswers = _answers.map((record) {
        return HistoryAnswer(
          questionId: record.question.id,
          category: record.question.category,
          difficulty: record.question.difficulty,
          selectedAnswer: record.selectedAnswer,
          correctAnswer: record.question.correctAnswer,
        );
      }).toList();

      await HistoryRepository.saveRound(
        category: _selectedCategory == all
            ? 'All categories'
            : _selectedCategory,
        difficulty: _selectedDifficulty == all
            ? 'All difficulties'
            : _selectedDifficulty,
        answers: historyAnswers,
      );

      if (!mounted) return;

      setState(() {
        _isSavingHistory = false;
        _screen = GameScreen.results;
      });
    } catch (error) {
      debugPrint('Failed to save quiz history: $error');

      if (!mounted) return;

      setState(() {
        _isSavingHistory = false;
        _historyError = error.toString();
      });
    }
  }

  void _returnHome() {
    setState(() {
      _screen = GameScreen.setup;
    });
  }

  int get _score => _answers.where((record) => record.isCorrect).length;

  // --------------------------------------------------
  // ROOT SCREEN
  // --------------------------------------------------

  @override
  Widget build(BuildContext context) {
    Widget content;

    if (_isLoading) {
      content = const Center(child: CircularProgressIndicator());
    } else if (_loadError != null) {
      content = Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 12),
              const Text('Could not load questions'),
              const SizedBox(height: 10),
              Text(_loadError!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loadQuestions,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    } else {
      switch (_screen) {
        case GameScreen.setup:
          content = _buildSetupScreen();

        case GameScreen.quiz:
          content = _buildQuizScreen();

        case GameScreen.feedback:
          content = _buildFeedbackScreen();

        case GameScreen.results:
          content = _buildResultsScreen();
      }
    }

    return Scaffold(body: SafeArea(child: content));
  }

  // --------------------------------------------------
  // GAME SETUP SCREEN
  // --------------------------------------------------

  Widget _buildSetupScreen() {
    final availableCount = _filteredQuestions.length;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 24),
        const Icon(Icons.image_search, size: 72, color: Colors.teal),
        const SizedBox(height: 16),
        const Text(
          'Image Identification',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 27, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text('Configure your next quiz.', textAlign: TextAlign.center),
        const SizedBox(height: 32),

        // Category selection.
        DropdownButtonFormField<String>(
          key: ValueKey('category-$_selectedCategory'),
          initialValue: _selectedCategory,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Category',
            border: OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem(value: all, child: Text('All categories')),
            ..._categories.map(
              (category) =>
                  DropdownMenuItem(value: category, child: Text(category)),
            ),
          ],
          onChanged: _changeCategory,
        ),

        const SizedBox(height: 18),

        // Difficulty selection.
        DropdownButtonFormField<String>(
          key: ValueKey(
            'difficulty-$_selectedCategory-'
            '$_selectedDifficulty',
          ),
          initialValue: _selectedDifficulty,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Difficulty',
            border: OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem(value: all, child: Text('All difficulties')),
            ..._difficulties.map(
              (difficulty) =>
                  DropdownMenuItem(value: difficulty, child: Text(difficulty)),
            ),
          ],
          onChanged: _changeDifficulty,
        ),

        const SizedBox(height: 18),

        // Question count selection.
        DropdownButtonFormField<int>(
          key: ValueKey(
            'count-$_selectedCategory-'
            '$_selectedDifficulty-$_questionCount',
          ),
          initialValue: _questionCount,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Number of questions',
            border: OutlineInputBorder(),
          ),
          items: [
            for (int count = 1; count <= _maximumQuestionCount; count++)
              DropdownMenuItem(value: count, child: Text('$count questions')),
          ],
          onChanged: (value) {
            if (value == null) return;

            setState(() {
              _questionCount = value;
            });
          },
        ),

        const SizedBox(height: 20),

        const Text(
          'Practice Mode',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),

        const SizedBox(height: 12),

        SegmentedButton<QuizMode>(
          segments: const [
            ButtonSegment<QuizMode>(
              value: QuizMode.random,
              label: Text('Random'),
              icon: Icon(Icons.shuffle),
            ),
            ButtonSegment<QuizMode>(
              value: QuizMode.adaptive,
              label: Text('Adaptive'),
              icon: Icon(Icons.psychology),
            ),
          ],
          selected: {_selectedMode},
          onSelectionChanged: _isPreparingQuiz
              ? null
              : (selectedModes) {
                  setState(() {
                    _selectedMode = selectedModes.first;
                  });
                },
        ),

        const SizedBox(height: 10),

        Text(
          _selectedMode == QuizMode.adaptive
              ? 'Prioritizes questions you have answered '
                    'incorrectly and questions you have not tried.'
              : 'Selects eligible questions with equal probability.',
          style: const TextStyle(fontSize: 13, color: Colors.grey),
        ),

        const SizedBox(height: 24),

        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(
                  '$availableCount questions available',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$_questionCount questions '
                  'will be selected randomly.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 26),

        SizedBox(
          height: 54,
          child: FilledButton.icon(
            onPressed: availableCount > 0 && !_isPreparingQuiz
                ? _startGame
                : null,
            icon: _isPreparingQuiz
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow),
            label: Text(_isPreparingQuiz ? 'Preparing Quiz...' : 'Start Quiz'),
          ),
        ),

        const SizedBox(height: 12),

        SizedBox(
          height: 50,
          child: OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => const StatisticsScreen(),
                ),
              );
            },
            icon: const Icon(Icons.bar_chart),
            label: const Text('View Statistics'),
          ),
        ),
      ],
    );
  }

  // --------------------------------------------------
  // QUIZ SCREEN
  // --------------------------------------------------

  Widget _buildQuizScreen() {
    final question = _questions[_currentIndex];

    return LayoutBuilder(
      builder: (context, constraints) {
        final imageHeight = (constraints.maxHeight - 20) * 0.73;

        return Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              SizedBox(
                height: imageHeight,
                width: double.infinity,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.asset(
                        question.imagePath,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stack) {
                          return Container(
                            color: Colors.black12,
                            alignment: Alignment.center,
                            child: Text(
                              'Image not found:\n'
                              '${question.imagePath}',
                              textAlign: TextAlign.center,
                            ),
                          );
                        },
                      ),

                      Positioned(
                        top: 12,
                        left: 12,
                        right: 12,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _imageLabel(
                              'Question ${_currentIndex + 1}'
                              ' / ${_questions.length}',
                            ),
                            _imageLabel('Score: $_score'),
                          ],
                        ),
                      ),

                      // Feedback after an answer.
                      if (_selectedAnswer != null)
                        Positioned(
                          left: 10,
                          right: 10,
                          bottom: 10,
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.black87,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _selectedAnswer == question.correctAnswer
                                        ? 'Correct!'
                                        : 'Incorrect!\n'
                                              '${question.correctAnswer}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),

                                FilledButton(
                                  onPressed: _isSavingHistory
                                      ? null
                                      : _nextQuestion,
                                  child: _isSavingHistory
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : Text(
                                          _historyError != null
                                              ? 'Retry'
                                              : _currentIndex ==
                                                    _questions.length - 1
                                              ? 'Results'
                                              : 'Next',
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // Four answer buttons.
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(child: _answerButton(_options[0], question)),
                          const SizedBox(width: 8),
                          Expanded(child: _answerButton(_options[1], question)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(child: _answerButton(_options[2], question)),
                          const SizedBox(width: 8),
                          Expanded(child: _answerButton(_options[3], question)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _imageLabel(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _answerButton(String answer, QuizQuestion question) {
    Color background = Colors.white;
    Color foreground = Colors.black87;
    Color border = Colors.grey;

    if (_selectedAnswer != null) {
      if (answer == question.correctAnswer) {
        background = Colors.green.shade100;
        foreground = Colors.green.shade900;
        border = Colors.green;
      } else if (answer == _selectedAnswer) {
        background = Colors.red.shade100;
        foreground = Colors.red.shade900;
        border = Colors.red;
      }
    }

    return OutlinedButton(
      onPressed: _selectedAnswer == null ? () => _selectAnswer(answer) : null,
      style: OutlinedButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
        disabledBackgroundColor: background,
        disabledForegroundColor: foreground,
        side: BorderSide(color: border, width: 2),
        padding: const EdgeInsets.all(6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(
        answer,
        textAlign: TextAlign.center,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildFeedbackScreen() {
    final question = _questions[_currentIndex];
    final record = _answers.last;

    final isCorrect = record.isCorrect;

    final explanation = question.explanation.isNotEmpty
        ? question.explanation
        : 'An explanation has not been added '
              'for this question yet.';

    final wrongAnswerExplanation =
        question.incorrectExplanations[record.selectedAnswer];

    final isLastQuestion = _currentIndex == _questions.length - 1;

    return Column(
      children: [
        // Scrollable feedback content.
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Icon(
                    isCorrect ? Icons.check_circle : Icons.cancel,
                    color: isCorrect ? Colors.green : Colors.red,
                    size: 30,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isCorrect ? 'Correct answer!' : 'Incorrect answer',
                      style: const TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // Smaller version of the original image.
              SizedBox(
                height: 180,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    color: Colors.black12,
                    child: Image.asset(
                      question.imagePath,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return const Center(
                          child: Text('Image could not be loaded.'),
                        );
                      },
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Show what the player selected.
              const Text(
                'Your answer',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 4),
              Text(
                record.selectedAnswer,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(height: 14),

              // Always display the correct answer.
              const Text(
                'Correct answer',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 4),
              Text(
                question.correctAnswer,
                style: TextStyle(
                  color: Colors.green,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 20),

              // Main educational explanation.
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.menu_book),
                          SizedBox(width: 8),
                          Text(
                            'Explanation',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      Text(
                        explanation,
                        style: const TextStyle(fontSize: 16, height: 1.5),
                      ),
                    ],
                  ),
                ),
              ),

              // Additional explanation for a wrong answer.
              if (!isCorrect) ...[
                const SizedBox(height: 12),

                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Why your answer was incorrect',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                        const SizedBox(height: 10),

                        Text(
                          wrongAnswerExplanation ??
                              'A comparison has not been '
                                  'added for this option yet.',
                          style: const TextStyle(fontSize: 16, height: 1.5),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),

        // Show database errors without losing the answer.
        if (_historyError != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Could not save this round: $_historyError',
              style: const TextStyle(color: Colors.red, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ),

        // Continue button remains visible when scrolling.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: _isSavingHistory ? null : _nextQuestion,
              child: _isSavingHistory
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      _historyError != null
                          ? 'Retry Saving'
                          : isLastQuestion
                          ? 'Save and View Results'
                          : 'Next Question',
                    ),
            ),
          ),
        ),
      ],
    );
  }

  // --------------------------------------------------
  // RESULTS SCREEN
  // --------------------------------------------------

  Widget _buildResultsScreen() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SizedBox(height: 20),
          const Icon(Icons.emoji_events, size: 65, color: Colors.amber),
          const SizedBox(height: 12),
          const Text(
            'Quiz Complete!',
            style: TextStyle(fontSize: 27, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            '$_score / ${_questions.length}',
            style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          const Text(
            'Answer Review',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),

          Expanded(
            child: ListView.builder(
              itemCount: _answers.length,
              itemBuilder: (context, index) {
                final record = _answers[index];
                final question = record.question;

                final explanation = question.explanation.isNotEmpty
                    ? question.explanation
                    : 'No explanation has been added yet.';

                final wrongExplanation =
                    question.incorrectExplanations[record.selectedAnswer];

                return Card(
                  child: ExpansionTile(
                    key: PageStorageKey<int>(question.id),

                    leading: Icon(
                      record.isCorrect ? Icons.check_circle : Icons.cancel,
                      color: record.isCorrect ? Colors.green : Colors.red,
                    ),

                    title: Text('${index + 1}. ${question.correctAnswer}'),

                    subtitle: Text(
                      'Your answer: ${record.selectedAnswer}\n'
                      '${question.category} • '
                      '${question.difficulty}',
                    ),

                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),

                    expandedCrossAxisAlignment: CrossAxisAlignment.start,

                    children: [
                      const Text(
                        'Explanation',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),

                      const SizedBox(height: 8),

                      Text(explanation),

                      if (!record.isCorrect) ...[
                        const SizedBox(height: 14),

                        const Text(
                          'Why your selection was incorrect',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),

                        const SizedBox(height: 8),

                        Text(
                          wrongExplanation ??
                              'No comparison has been added '
                                  'for this option yet.',
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _returnHome,
                  child: const Text('Home'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _isPreparingQuiz ? null : _startGame,
                  child: Text(_isPreparingQuiz ? 'Preparing...' : 'Play Again'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
