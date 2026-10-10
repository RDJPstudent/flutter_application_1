
import 'package:flutter/material.dart';

import '../data/history_repository.dart';

class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() =>
      _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  late Future<QuizStatistics> _statisticsFuture;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _statisticsFuture = HistoryRepository.loadStatistics();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Player Statistics'),
        actions: [
          IconButton(
            tooltip: 'Refresh statistics',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<QuizStatistics>(
        future: _statisticsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState !=
              ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Could not load statistics.'),
                    const SizedBox(height: 10),
                    Text(
                      '${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _refresh,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }

          final stats = snapshot.data!;

          if (stats.completedRounds == 0) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No completed rounds yet.\n'
                  'Finish a quiz to begin tracking progress.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return _buildStatistics(stats);
        },
      ),
    );
  }

  Widget _buildStatistics(QuizStatistics stats) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            _metric(
              '${stats.completedRounds}',
              'Rounds',
            ),
            _metric(
              '${stats.totalAnswers}',
              'Answers',
            ),
            _metric(
              '${(stats.accuracy * 100).toStringAsFixed(1)}%',
              'Accuracy',
            ),
          ],
        ),

        const SizedBox(height: 12),

        Text(
          '${stats.correctAnswers} correct answers '
          'out of ${stats.totalAnswers}',
          textAlign: TextAlign.center,
        ),

        const SizedBox(height: 24),

        _sectionHeading('Accuracy by category'),

        for (final category in stats.categories)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          category.category,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Text(
                        '${category.correct}/'
                        '${category.answered}'
                        ' (${(category.accuracy * 100).round()}%)',
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  LinearProgressIndicator(
                    value: category.accuracy,
                    minHeight: 8,
                  ),
                ],
              ),
            ),
          ),

        const SizedBox(height: 20),

        _sectionHeading('Frequently missed concepts'),

        if (stats.missedConcepts.isEmpty)
          const ListTile(
            title: Text('No incorrect answers recorded.'),
          ),

        for (final concept in stats.missedConcepts)
          ListTile(
            leading: const Icon(Icons.error_outline),
            title: Text(concept.correctAnswer),
            subtitle: Text(concept.category),
            trailing: Text('${concept.misses} missed'),
          ),

        const SizedBox(height: 20),

        _sectionHeading('Recent rounds'),

        for (final round in stats.recentRounds)
          Card(
            child: ListTile(
              leading: const Icon(Icons.history),
              title: Text(
                '${round.correctCount} / '
                '${round.questionCount} correct',
              ),
              subtitle: Text(
                '${round.category} • ${round.difficulty}\n'
                '${round.completedAt.toString().substring(0, 16)}',
              ),
              isThreeLine: true,
            ),
          ),
      ],
    );
  }

  Widget _metric(String value, String label) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: 16,
            horizontal: 4,
          ),
          child: Column(
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  style: const TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                label,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeading(String title) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: 10,
        left: 4,
      ),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
