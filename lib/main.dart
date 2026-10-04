import 'dart:math' as math;
import 'package:flutter/material.dart';

void main() {
  runApp(const FootballPredictorApp());
}

class FootballPredictorApp extends StatelessWidget {
  const FootballPredictorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Advanced Football Match Engine',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.teal,
        scaffoldBackgroundColor: const Color(0xFF121212),
        cardColor: const Color(0xFF1E1E1E),
      ),
      home: const MatchPredictorScreen(),
    );
  }
}

/// Core Calculation Engine Model
class MatchCalculationEngine {
  static const double leagueAvgGoals = 1.35;
  static const double homeAdvantage = 1.15;
  static const double htSplitRatio = 0.43; // 43% goals scored in 1st Half
  static const double h2SplitRatio = 0.57; // 57% goals scored in 2nd Half

  static double factorial(int k) {
    if (k <= 1) return 1.0;
    double result = 1.0;
    for (int i = 2; i <= k; i++) {
      result *= i;
    }
    return result;
  }

  static double poissonProbability(int k, double lambda) {
    if (lambda <= 0) return k == 0 ? 1.0 : 0.0;
    return (math.pow(lambda, k) * math.exp(-lambda)) / factorial(k);
  }

  static PredictionResult compute({
    required String homeTeam,
    required String awayTeam,
    required double homeGoalsScored5,
    required double homeGoalsConceded5,
    required double awayGoalsScored5,
    required double awayGoalsConceded5,
    required double homeTierRating,
    required double awayTierRating,
    required double homeVariance,
    required double awayVariance,
  }) {
    // 1. Attack & Defense Ratings
    double homeAttack = (homeGoalsScored5 / 5.0) / leagueAvgGoals;
    double homeDefense = (homeGoalsConceded5 / 5.0) / leagueAvgGoals;
    double awayAttack = (awayGoalsScored5 / 5.0) / leagueAvgGoals;
    double awayDefense = (awayGoalsConceded5 / 5.0) / leagueAvgGoals;

    // 2. Tier Disparity Multipliers
    double tierRatioHome = homeTierRating / awayTierRating;
    double tierRatioAway = awayTierRating / homeTierRating;

    // 3. Full-Time Expected Goals (xG)
    double homeFtXg = homeAttack * awayDefense * tierRatioHome * homeAdvantage * leagueAvgGoals;
    double awayFtXg = awayAttack * homeDefense * tierRatioAway * leagueAvgGoals;
    double totalXg = homeFtXg + awayFtXg;

    // 4. Time-Split Analysis (HT / 2H)
    double homeHtXg = homeFtXg * htSplitRatio;
    double awayHtXg = awayFtXg * htSplitRatio;

    // 5. Goal Variance Safety Check
    double combinedVariance = homeVariance + awayVariance;
    bool isHighVariance = combinedVariance > 1.5;

    // 6. Compute 6x6 Poisson Distribution Matrix (Goals 0..5)
    double homeWinProb = 0.0;
    double drawProb = 0.0;
    double awayWinProb = 0.0;
    double over15Prob = 0.0;
    double over25Prob = 0.0;

    int maxLikelyHomeHt = 0;
    int maxLikelyAwayHt = 0;
    int maxLikelyHomeFt = 0;
    int maxLikelyAwayFt = 0;
    double maxHtProb = -1.0;
    double maxFtProb = -1.0;

    for (int h = 0; h <= 5; h++) {
      for (int a = 0; a <= 5; a++) {
        // Full Time Matrix Cell
        double pHomeFt = poissonProbability(h, homeFtXg);
        double pAwayFt = poissonProbability(a, awayFtXg);
        double cellFtProb = pHomeFt * pAwayFt;

        if (h > a) homeWinProb += cellFtProb;
        if (h == a) drawProb += cellFtProb;
        if (h < a) awayWinProb += cellFtProb;

        if ((h + a) > 1) over15Prob += cellFtProb;
        if ((h + a) > 2) over25Prob += cellFtProb;

        if (cellFtProb > maxFtProb) {
          maxFtProb = cellFtProb;
          maxLikelyHomeFt = h;
          maxLikelyAwayFt = a;
        }

        // Half Time Matrix Cell
        double pHomeHt = poissonProbability(h, homeHtXg);
        double pAwayHt = poissonProbability(a, awayHtXg);
        double cellHtProb = pHomeHt * pAwayHt;

        if (cellHtProb > maxHtProb) {
          maxHtProb = cellHtProb;
          maxLikelyHomeHt = h;
          maxLikelyAwayHt = a;
        }
      }
    }

    // 7. Market Probabilities & Logic Overrides
    double dc1XProb = homeWinProb + drawProb;
    double bttsYesProb = (1.0 - math.exp(-homeFtXg)) * (1.0 - math.exp(-awayFtXg));
    double bttsNoProb = 1.0 - bttsYesProb;

    // Recommendation Rule Engine
    String rec1X2 = homeWinProb >= 0.45
        ? "$homeTeam Win (1)"
        : (awayWinProb >= 0.45 ? "$awayTeam Win (2)" : "Draw (X)");

    String recDc = dc1XProb >= 0.70 ? "1X ($homeTeam / Draw)" : "12 or X2";

    String recOU;
    if (isHighVariance || totalXg >= 2.5) {
      recOU = over25Prob >= 0.55 ? "Over 2.5 Goals" : "Over 1.5 Goals";
    } else {
      recOU = "Under 2.5 Goals";
    }

    String recBtts = (bttsYesProb >= 0.50 || (isHighVariance && totalXg > 2.2))
        ? "BTTS (Yes)"
        : "BTTS (No)";

    return PredictionResult(
      homeTeam: homeTeam,
      awayTeam: awayTeam,
      homeFtXg: homeFtXg,
      awayFtXg: awayFtXg,
      totalXg: totalXg,
      combinedVariance: combinedVariance,
      isHighVariance: isHighVariance,
      homeWinProb: homeWinProb * 100,
      drawProb: drawProb * 100,
      awayWinProb: awayWinProb * 100,
      dc1XProb: dc1XProb * 100,
      over25Prob: over25Prob * 100,
      bttsYesProb: bttsYesProb * 100,
      bttsNoProb: bttsNoProb * 100,
      likelyHtScore: "$maxLikelyHomeHt - $maxLikelyAwayHt",
      likelyFtScore: "$maxLikelyHomeFt - $maxLikelyAwayFt",
      recommended1X2: rec1X2,
      recommendedDC: recDc,
      recommendedOU: recOU,
      recommendedBTTS: recBtts,
    );
  }
}

class PredictionResult {
  final String homeTeam;
  final String awayTeam;
  final double homeFtXg;
  final double awayFtXg;
  final double totalXg;
  final double combinedVariance;
  final bool isHighVariance;
  final double homeWinProb;
  final double drawProb;
  final double awayWinProb;
  final double dc1XProb;
  final double over25Prob;
  final double bttsYesProb;
  final double bttsNoProb;
  final String likelyHtScore;
  final String likelyFtScore;
  final String recommended1X2;
  final String recommendedDC;
  final String recommendedOU;
  final String recommendedBTTS;

  PredictionResult({
    required this.homeTeam,
    required this.awayTeam,
    required this.homeFtXg,
    required this.awayFtXg,
    required this.totalXg,
    required this.combinedVariance,
    required this.isHighVariance,
    required this.homeWinProb,
    required this.drawProb,
    required this.awayWinProb,
    required this.dc1XProb,
    required this.over25Prob,
    required this.bttsYesProb,
    required this.bttsNoProb,
    required this.likelyHtScore,
    required this.likelyFtScore,
    required this.recommended1X2,
    required this.recommendedDC,
    required this.recommendedOU,
    required this.recommendedBTTS,
  });
}

class MatchPredictorScreen extends StatefulWidget {
  const MatchPredictorScreen({super.key});

  @override
  State<MatchPredictorScreen> createState() => _MatchPredictorScreenState();
}

class _MatchPredictorScreenState extends State<MatchPredictorScreen> {
  final _homeController = TextEditingController(text: 'Dragones de Oaxaca');
  final _awayController = TextEditingController(text: 'Real Refineros');

  double _homeScored = 11.0;
  double _homeConceded = 6.0;
  double _awayScored = 8.0;
  double _awayConceded = 9.0;

  double _homeTier = 1.4;
  double _awayTier = 1.0;

  double _homeVariance = 0.95;
  double _awayVariance = 0.85;

  PredictionResult? _result;

  @override
  void initState() {
    super.initState();
    _calculate();
  }

  void _calculate() {
    setState(() {
      _result = MatchCalculationEngine.compute(
        homeTeam: _homeController.text.isEmpty ? 'Home' : _homeController.text,
        awayTeam: _awayController.text.isEmpty ? 'Away' : _awayController.text,
        homeGoalsScored5: _homeScored,
        homeGoalsConceded5: _homeConceded,
        awayGoalsScored5: _awayScored,
        awayGoalsConceded5: _awayConceded,
        homeTierRating: _homeTier,
        awayTierRating: _awayTier,
        homeVariance: _homeVariance,
        awayVariance: _awayVariance,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Poisson Match Prediction Engine'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildInputCard(),
            const SizedBox(height: 16),
            if (_result != null) _buildResultsCard(_result!),
          ],
        ),
      ),
    );
  }

  Widget _buildInputCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAlignment.start,
          children: [
            const Text(
              'Match Inputs (Past 5 Games)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.tealAccent),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _homeController,
                    decoration: const InputDecoration(labelText: 'Home Team'),
                    onChanged: (_) => _calculate(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _awayController,
                    decoration: const InputDecoration(labelText: 'Away Team'),
                    onChanged: (_) => _calculate(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildSlider('Home Scored (5 Games): ${_homeScored.toInt()}', _homeScored, 0, 25, (v) {
              setState(() => _homeScored = v);
              _calculate();
            }),
            _buildSlider('Home Conceded (5 Games): ${_homeConceded.toInt()}', _homeConceded, 0, 25, (v) {
              setState(() => _homeConceded = v);
              _calculate();
            }),
            _buildSlider('Away Scored (5 Games): ${_awayScored.toInt()}', _awayScored, 0, 25, (v) {
              setState(() => _awayScored = v);
              _calculate();
            }),
            _buildSlider('Away Conceded (5 Games): ${_awayConceded.toInt()}', _awayConceded, 0, 25, (v) {
              setState(() => _awayConceded = v);
              _calculate();
            }),
            const Divider(height: 24),
            _buildSlider('Home Tier Rating: ${_homeTier.toStringAsFixed(2)}', _homeTier, 0.5, 3.0, (v) {
              setState(() => _homeTier = v);
              _calculate();
            }),
            _buildSlider('Away Tier Rating: ${_awayTier.toStringAsFixed(2)}', _awayTier, 0.5, 3.0, (v) {
              setState(() => _awayTier = v);
              _calculate();
            }),
            _buildSlider('Home Variance (\u03C3\u00B2): ${_homeVariance.toStringAsFixed(2)}', _homeVariance, 0.1, 2.5, (v) {
              setState(() => _homeVariance = v);
              _calculate();
            }),
            _buildSlider('Away Variance (\u03C3\u00B2): ${_awayVariance.toStringAsFixed(2)}', _awayVariance, 0.1, 2.5, (v) {
              setState(() => _awayVariance = v);
              _calculate();
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildSlider(String label, double value, double min, double max, ValueChanged<double> onChanged) {
    return Column(
      crossAxisAlignment: CrossAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
        Slider(
          value: value,
          min: min,
          max: max,
          activeColor: Colors.teal,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildResultsCard(PredictionResult res) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Prediction Dashboard',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.tealAccent),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: res.isHighVariance ? Colors.redAccent.withAlpha(50) : Colors.greenAccent.withAlpha(50),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    res.isHighVariance ? 'HIGH VARIANCE (\u03C3\u00B2 > 1.5)' : 'LOW VARIANCE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: res.isHighVariance ? Colors.redAccent : Colors.greenAccent,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _resultRow('Match Expected Goals (xG):', res.totalXg.toStringAsFixed(2)),
            _resultRow('${res.homeTeam} xG:', res.homeFtXg.toStringAsFixed(2)),
            _resultRow('${res.awayTeam} xG:', res.awayFtXg.toStringAsFixed(2)),
            const Divider(height: 24),
            _resultRow('HT Expected Score:', res.likelyHtScore, isBold: true),
            _resultRow('FT Expected Score:', res.likelyFtScore, isBold: true),
            const Divider(height: 24),
            const Text('Market Predictions', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white70)),
            const SizedBox(height: 8),
            _predictionTile('1X2 Market', res.recommended1X2, '${res.homeWinProb.toStringAsFixed(1)}% / ${res.drawProb.toStringAsFixed(1)}% / ${res.awayWinProb.toStringAsFixed(1)}%'),
            _predictionTile('Double Chance', res.recommendedDC, '${res.dc1XProb.toStringAsFixed(1)}% 1X Prob'),
            _predictionTile('Over / Under', res.recommendedOU, '${res.over25Prob.toStringAsFixed(1)}% Over 2.5 Prob'),
            _predictionTile('BTTS', res.recommendedBTTS, '${res.bttsYesProb.toStringAsFixed(1)}% Yes / ${res.bttsNoProb.toStringAsFixed(1)}% No'),
          ],
        ),
      ),
    );
  }

  Widget _resultRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 14)),
          Text(
            value,
            style: TextStyle(
              color: isBold ? Colors.tealAccent : Colors.white,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _predictionTile(String market, String pick, String prob) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAlignment.start,
            children: [
              Text(market, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              Text(pick, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.tealAccent)),
            ],
          ),
          Text(prob, style: const TextStyle(fontSize: 12, color: Colors.white70)),
        ],
      ),
    );
  }
}
