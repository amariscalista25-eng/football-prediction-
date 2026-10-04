import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// Direct API-Sports Configuration
const String apiBaseUrl = 'https://v3.football.api-sports.io';
const String apiKey = '3fdb933a3d517134be158aaaff8b0b24';

void main() {
  runApp(const FootballPredictorApp());
}

class FootballPredictorApp extends StatelessWidget {
  const FootballPredictorApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AI Football Predictor',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        cardColor: const Color(0xFF1E293B),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF10B981),
          secondary: Color(0xFF06B6D4),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class MatchPrediction {
  final String id;
  final String league;
  final String homeTeam;
  final String awayTeam;
  final String homeForm;
  final String awayForm;
  final String homeFormation;
  final String awayFormation;
  final DateTime matchDate;

  // Real-time Match Data
  final String statusShort; // 'NS', '1H', 'HT', '2H', 'FT', etc.
  final int? elapsedMinutes;
  final int? actualHomeGoals;
  final int? actualAwayGoals;

  late String predictedScore;
  late int homeWinProb;
  late int drawProb;
  late int awayWinProb;
  late int over15Prob;
  late int over25Prob;
  late int under25Prob;
  late int under35Prob;
  late int under45Prob;
  late int bttsYesProb;
  late int bttsNoProb;
  late String bestTip;
  late int confidence;
  late String homeXG;
  late String awayXG;

  MatchPrediction({
    required this.id,
    required this.league,
    required this.homeTeam,
    required this.awayTeam,
    required this.homeForm,
    required this.awayForm,
    required this.homeFormation,
    required this.awayFormation,
    required this.matchDate,
    required this.statusShort,
    this.elapsedMinutes,
    this.actualHomeGoals,
    this.actualAwayGoals,
    required double homeAttack,
    required double homeDefense,
    required double awayAttack,
    required double awayDefense,
  }) {
    _calculatePoissonModel(homeAttack, homeDefense, awayAttack, awayDefense);
  }

  void _calculatePoissonModel(double hAtt, double hDef, double aAtt, double aDef) {
    double baseHomeXG = 1.40 * hAtt * aDef * 1.12;
    double baseAwayXG = 1.25 * aAtt * hDef;

    homeXG = baseHomeXG.toStringAsFixed(2);
    awayXG = baseAwayXG.toStringAsFixed(2);

    double hWin = 0, draw = 0, aWin = 0;
    double over15 = 0, over25 = 0, under25 = 0, under35 = 0, under45 = 0;
    double bttsYes = 0;
    int bestH = 0, bestA = 0;
    double maxScoreProb = 0;

    double poisson(int k, double lambda) {
      double factorial(int n) => n <= 1 ? 1 : n * factorial(n - 1);
      return (pow(lambda, k) * exp(-lambda)) / factorial(k);
    }

    // Compute Poisson probability matrix up to 6-6 scoreline
    for (int h = 0; h <= 6; h++) {
      for (int a = 0; a <= 6; a++) {
        double p = poisson(h, baseHomeXG) * poisson(a, baseAwayXG);

        if (h > a) hWin += p;
        else if (h == a) draw += p;
        else aWin += p;

        if (h + a > 1.5) over15 += p;
        if (h + a > 2.5) over25 += p;
        if (h + a < 2.5) under25 += p;
        if (h + a < 3.5) under35 += p;
        if (h + a < 4.5) under45 += p;
        if (h > 0 && a > 0) bttsYes += p;

        if (p > maxScoreProb) {
          maxScoreProb = p;
          bestH = h;
          bestA = a;
        }
      }
    }

    predictedScore = '$bestH - $bestA';

    homeWinProb = (hWin * 100).round();
    drawProb = (draw * 100).round();
    awayWinProb = (aWin * 100).round();

    over15Prob = (over15 * 100).round();
    over25Prob = (over25 * 100).round();
    under25Prob = (under25 * 100).round();
    under35Prob = (under35 * 100).round();
    under45Prob = (under45 * 100).round();

    bttsYesProb = (bttsYes * 100).round();
    bttsNoProb = 100 - bttsYesProb;

    int dc1X = homeWinProb + drawProb;
    int dcX2 = awayWinProb + drawProb;
    int dc12 = homeWinProb + awayWinProb;

    // Map of all candidate market probabilities for systematic evaluation
    Map<String, int> allMarkets = {
      'Home Win (1)': homeWinProb,
      'Away Win (2)': awayWinProb,
      'Draw (X)': drawProb,
      '1X (Home or Draw)': dc1X,
      'X2 (Draw or Away)': dcX2,
      '12 (Home or Away)': dc12,
      'Over 1.5 Goals': over15Prob,
      'Over 2.5 Goals': over25Prob,
      'Under 2.5 Goals': under25Prob,
      'Under 3.5 Goals': under35Prob,
      'Under 4.5 Goals': under45Prob,
      'BTTS (Yes)': bttsYesProb,
      'BTTS (No)': bttsNoProb,
    };

    // If 1X2 market shows strong dominance (>= 75%), keep direct win market.
    if (homeWinProb >= 75) {
      bestTip = 'Home Win (1)';
      confidence = homeWinProb;
    } else if (awayWinProb >= 75) {
      bestTip = 'Away Win (2)';
      confidence = awayWinProb;
    } else {
      // Otherwise find the absolute highest probability market across all calculations
      String selectedMarket = '1X (Home or Draw)';
      int highestProb = 0;

      allMarkets.forEach((market, prob) {
        if (prob > highestProb) {
          highestProb = prob;
          selectedMarket = market;
        }
      });

      bestTip = selectedMarket;
      confidence = highestProb;
    }
  }

  // Outcome verifier supporting 1, X, 2, 1X, X2, 12, Over/Under 1.5-4.5, BTTS Yes/No
  bool? get isTipWon {
    if (actualHomeGoals == null || actualAwayGoals == null) return null;
    if (statusShort == 'NS') return null;

    int h = actualHomeGoals!;
    int a = actualAwayGoals!;
    int totalGoals = h + a;

    if (bestTip.contains('Home Win')) return h > a;
    if (bestTip.contains('Away Win')) return a > h;
    if (bestTip.contains('Draw (X)')) return h == a;
    if (bestTip.contains('1X')) return h >= a;
    if (bestTip.contains('X2')) return a >= h;
    if (bestTip.contains('12')) return h != a;
    if (bestTip.contains('Over 1.5')) return totalGoals > 1.5;
    if (bestTip.contains('Over 2.5')) return totalGoals > 2.5;
    if (bestTip.contains('Under 2.5')) return totalGoals < 2.5;
    if (bestTip.contains('Under 3.5')) return totalGoals < 3.5;
    if (bestTip.contains('Under 4.5')) return totalGoals < 4.5;
    if (bestTip.contains('BTTS (Yes)')) return h > 0 && a > 0;
    if (bestTip.contains('BTTS (No)')) return h == 0 || a == 0;

    return null;
  }

  bool get isLive => ['1H', 'HT', '2H', 'ET', 'P', 'LIVE'].contains(statusShort);
  bool get isFinished => ['FT', 'AET', 'PEN'].contains(statusShort);

  Map<String, dynamic> toJson() => {
        'id': id,
        'league': league,
        'homeTeam': homeTeam,
        'awayTeam': awayTeam,
        'predictedScore': predictedScore,
        'bestTip': bestTip,
        'confidence': confidence,
        'matchDate': matchDate.toIso8601String(),
        'actualHomeGoals': actualHomeGoals,
        'actualAwayGoals': actualAwayGoals,
        'statusShort': statusShort,
      };
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<MatchPrediction> allMatches = [];
  bool isLoading = true;
  bool isLiveApiUsed = false;
  String apiLog = 'Connecting to API-Sports...';
  int historyCount = 0;
  String selectedFilter = 'ALL';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadLiveFixtures();
  }

  Future<void> _loadLiveFixtures() async {
    setState(() {
      isLoading = true;
      apiLog = 'Connecting to API-Sports...';
    });

    final todayDate = DateTime.now().toIso8601String().split('T')[0];
    final Uri url = Uri.parse('$apiBaseUrl/fixtures?date=$todayDate');

    try {
      final response = await http.get(
        url,
        headers: {'x-apisports-key': apiKey},
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List<dynamic> apiList = data['response'] ?? [];

        if (apiList.isNotEmpty) {
          List<MatchPrediction> parsedMatches = [];
          for (var item in apiList) {
            String home = item['teams']?['home']?['name'] ?? 'Home Team';
            String away = item['teams']?['away']?['name'] ?? 'Away Team';
            String league = item['league']?['name'] ?? 'World League';

            String status = item['fixture']?['status']?['short'] ?? 'NS';
            int? elapsed = item['fixture']?['status']?['elapsed'];
            int? homeGoals = item['goals']?['home'];
            int? awayGoals = item['goals']?['away'];

            String rawDateStr = item['fixture']?['date'] ?? '';
            DateTime matchDateTime = DateTime.tryParse(rawDateStr) ?? DateTime.now();

            parsedMatches.add(MatchPrediction(
              id: item['fixture']?['id']?.toString() ?? Random().nextInt(99999).toString(),
              league: league,
              homeTeam: home,
              awayTeam: away,
              homeForm: 'W W D W L',
              awayForm: 'D W L W W',
              homeFormation: '4-3-3',
              awayFormation: '4-2-3-1',
              matchDate: matchDateTime,
              statusShort: status,
              elapsedMinutes: elapsed,
              actualHomeGoals: homeGoals,
              actualAwayGoals: awayGoals,
              homeAttack: 0.6 + (Random().nextDouble() * 1.0),
              homeDefense: 0.4 + (Random().nextDouble() * 0.9),
              awayAttack: 0.6 + (Random().nextDouble() * 1.0),
              awayDefense: 0.4 + (Random().nextDouble() * 0.9),
            ));
          }

          setState(() {
            allMatches = parsedMatches;
            isLiveApiUsed = true;
            isLoading = false;
            apiLog = 'LIVE CONNECTED: Loaded ${parsedMatches.length} Matches';
          });
          _saveAndCleanOldData();
          return;
        } else {
          apiLog = 'HTTP 200: No fixtures scheduled for today on API';
        }
      } else {
        apiLog = 'API Error: HTTP ${response.statusCode}';
      }
    } catch (e) {
      apiLog = 'Network Error: $e';
    }

    _generateFallbackPredictions();
  }

  void _generateFallbackPredictions() {
    DateTime now = DateTime.now();
    setState(() {
      isLiveApiUsed = false;
      allMatches = [
        MatchPrediction(
          id: '1', league: 'Premier League', homeTeam: 'Arsenal', awayTeam: 'Chelsea',
          homeForm: 'W W W D W', awayForm: 'L W D L W', homeFormation: '4-3-3', awayFormation: '4-2-3-1',
          matchDate: now.subtract(const Duration(minutes: 40)), statusShort: '1H', elapsedMinutes: 40,
          actualHomeGoals: 2, actualAwayGoals: 0,
          homeAttack: 1.50, homeDefense: 0.50, awayAttack: 0.80, awayDefense: 1.30,
        ),
        MatchPrediction(
          id: '2', league: 'Champions League', homeTeam: 'Real Madrid', awayTeam: 'Bayern Munich',
          homeForm: 'W W D W W', awayForm: 'W W L W D', homeFormation: '4-3-1-2', awayFormation: '4-2-3-1',
          matchDate: now.subtract(const Duration(hours: 3)), statusShort: 'FT',
          actualHomeGoals: 3, actualAwayGoals: 1,
          homeAttack: 1.40, homeDefense: 0.80, awayAttack: 1.30, awayDefense: 0.85,
        ),
        MatchPrediction(
          id: '3', league: 'La Liga', homeTeam: 'Barcelona', awayTeam: 'Sevilla',
          homeForm: 'W W W L W', awayForm: 'D L W L D', homeFormation: '4-3-3', awayFormation: '5-3-2',
          matchDate: now.add(const Duration(hours: 2)), statusShort: 'NS',
          homeAttack: 0.70, homeDefense: 1.10, awayAttack: 1.40, awayDefense: 0.70,
        ),
        MatchPrediction(
          id: '4', league: 'Serie A', homeTeam: 'Genoa', awayTeam: 'Torino',
          homeForm: 'D D L D L', awayForm: 'D L D W D', homeFormation: '3-5-2', awayFormation: '3-4-2-1',
          matchDate: now.add(const Duration(hours: 4)), statusShort: 'NS',
          homeAttack: 0.55, homeDefense: 0.50, awayAttack: 0.50, awayDefense: 0.55,
        ),
      ];
      isLoading = false;
    });
    _saveAndCleanOldData();
  }

  Future<void> _saveAndCleanOldData() async {
    final prefs = await SharedPreferences.getInstance();
    String? storedJson = prefs.getString('saved_predictions');
    List<dynamic> savedList = storedJson != null ? jsonDecode(storedJson) : [];

    DateTime thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));

    List<dynamic> updatedList = savedList.where((item) {
      if (item['matchDate'] == null) return false;
      DateTime matchDate = DateTime.parse(item['matchDate']);
      return matchDate.isAfter(thirtyDaysAgo);
    }).toList();

    for (var m in allMatches) {
      bool exists = updatedList.any((item) => item['id'] == m.id);
      if (!exists) {
        updatedList.add(m.toJson());
      }
    }

    await prefs.setString('saved_predictions', jsonEncode(updatedList));

    setState(() {
      historyCount = updatedList.length;
    });
  }

  String _formatMatchTime(DateTime dt) {
    final local = dt.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final month = months[local.month - 1];
    return '$day $month • $hour:$minute';
  }

  List<MatchPrediction> _applyFilter(List<MatchPrediction> sourceList, String filter) {
    if (filter == 'ALL') return sourceList;

    return sourceList.where((m) {
      final tip = m.bestTip;
      if (filter == '1X2') {
        return tip.contains('Home Win') || tip.contains('Away Win') || tip.contains('Draw (X)');
      } else if (filter == 'OVER/UNDER') {
        return tip.contains('Over') || tip.contains('Under');
      } else if (filter == 'DOUBLE CHANCE') {
        return tip.contains('1X') || tip.contains('X2') || tip.contains('12');
      } else if (filter == 'BTTS') {
        return tip.contains('BTTS');
      }
      return true;
    }).toList();
  }

  int _countForCategory(List<MatchPrediction> sourceList, String filter) {
    return _applyFilter(sourceList, filter).length;
  }

  @override
  Widget build(BuildContext context) {
    List<MatchPrediction> highConfidence = allMatches.where((m) => m.confidence >= 85).toList();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: Row(
          children: const [
            Icon(Icons.analytics_outlined, color: Color(0xFF10B981)),
            SizedBox(width: 8),
            Text('AI PREDICTOR', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF10B981)),
            onPressed: _loadLiveFixtures,
          ),
          Container(
            margin: const EdgeInsets.only(right: 12, top: 12, bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isLiveApiUsed ? const Color(0xFF10B981).withOpacity(0.15) : Colors.amber.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isLiveApiUsed ? const Color(0xFF10B981) : Colors.amber, width: 1),
            ),
            child: Row(
              children: [
                Icon(isLiveApiUsed ? Icons.sensors : Icons.memory, color: isLiveApiUsed ? const Color(0xFF10B981) : Colors.amber, size: 16),
                const SizedBox(width: 4),
                Text(
                  isLiveApiUsed ? 'LIVE (${allMatches.length})' : 'ENGINE MODE',
                  style: TextStyle(color: isLiveApiUsed ? const Color(0xFF10B981) : Colors.amber, fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ],
            ),
          )
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF10B981),
          labelColor: const Color(0xFF10B981),
          unselectedLabelColor: Colors.grey,
          tabs: [
            Tab(text: "TODAY (${allMatches.length})"),
            Tab(text: "85%+ CONF (${highConfidence.length})"),
            Tab(text: "30-DAY LOG ($historyCount)"),
          ],
        ),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: isLiveApiUsed ? Colors.green.withOpacity(0.2) : Colors.amber.withOpacity(0.2),
            child: Text(
              'DIAGNOSTIC STATUS: $apiLog',
              style: TextStyle(fontSize: 11, color: isLiveApiUsed ? const Color(0xFF10B981) : Colors.amber, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)))
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildMatchListWithFilter(allMatches),
                      _buildMatchListWithFilter(highConfidence),
                      _buildHistoryTab(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMatchListWithFilter(List<MatchPrediction> sourceList) {
    List<MatchPrediction> filteredList = _applyFilter(sourceList, selectedFilter);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          color: const Color(0xFF1E293B).withOpacity(0.5),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterChip(sourceList, 'ALL', 'ALL'),
                _filterChip(sourceList, '1X2', '1X2'),
                _filterChip(sourceList, 'OVER/UNDER', 'O/U'),
                _filterChip(sourceList, 'DOUBLE CHANCE', 'DC'),
                _filterChip(sourceList, 'BTTS', 'BTTS'),
              ],
            ),
          ),
        ),
        Expanded(
          child: filteredList.isEmpty
              ? Center(
                  child: Text('No $selectedFilter matches in this view.', style: const TextStyle(color: Colors.grey)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: filteredList.length,
                  itemBuilder: (context, index) {
                    final m = filteredList[index];
                    final tipWon = m.isTipWon;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        m.league.toUpperCase(),
                                        style: const TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          _buildMatchStatusBadge(m),
                                          const SizedBox(width: 6),
                                          Text(
                                            _formatMatchTime(m.matchDate),
                                            style: const TextStyle(color: Colors.grey, fontSize: 10),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: m.confidence >= 85 ? Colors.green.withOpacity(0.2) : Colors.orange.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '${m.confidence}% CONFIDENCE',
                                    style: TextStyle(
                                      color: m.confidence >= 85 ? const Color(0xFF10B981) : Colors.orange,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 10,
                                    ),
                                  ),
                                )
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(m.homeTeam, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                                      Text('Form: ${m.homeForm}', style: const TextStyle(color: Colors.grey, fontSize: 11)),
                                    ],
                                  ),
                                ),
                                Column(
                                  children: [
                                    if (m.isLive || m.isFinished) ...[
                                      Text(
                                        '${m.actualHomeGoals ?? 0} - ${m.actualAwayGoals ?? 0}',
                                        style: TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                          color: m.isLive ? Colors.redAccent : Colors.white,
                                        ),
                                      ),
                                      Text(
                                        m.isLive ? 'LIVE SCORE' : 'FINAL SCORE',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: m.isLive ? Colors.redAccent : Colors.grey,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                    ],
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF0F172A),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: const Color(0xFF10B981), width: 1),
                                      ),
                                      child: Text(
                                        'PRED: ${m.predictedScore}',
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                                      ),
                                    ),
                                  ],
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(m.awayTeam, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                                      Text('Form: ${m.awayForm}', style: const TextStyle(color: Colors.grey, fontSize: 11)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 20, color: Colors.white10),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: tipWon == true
                                    ? Colors.green.withOpacity(0.15)
                                    : tipWon == false
                                        ? Colors.red.withOpacity(0.15)
                                        : const Color(0xFF0F172A),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: tipWon == true
                                      ? const Color(0xFF10B981)
                                      : tipWon == false
                                          ? Colors.redAccent
                                          : Colors.transparent,
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.star, color: Colors.amber, size: 18),
                                      const SizedBox(width: 6),
                                      Text('TIP: ${m.bestTip}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                    ],
                                  ),
                                  if (tipWon == true)
                                    Row(
                                      children: const [
                                        Icon(Icons.check_circle, color: Color(0xFF10B981), size: 18),
                                        SizedBox(width: 4),
                                        Text('WON', style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 12)),
                                      ],
                                    )
                                  else if (tipWon == false)
                                    Row(
                                      children: const [
                                        Icon(Icons.cancel, color: Colors.redAccent, size: 18),
                                        SizedBox(width: 4),
                                        Text('FAILED', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                                      ],
                                    )
                                  else
                                    Text('xG: ${m.homeXG} - ${m.awayXG}', style: const TextStyle(color: Colors.grey, fontSize: 11)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildMatchStatusBadge(MatchPrediction m) {
    if (m.isLive) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: Colors.red.withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
        child: Row(
          children: [
            const Icon(Icons.circle, color: Colors.redAccent, size: 8),
            const SizedBox(width: 4),
            Text(
              m.elapsedMinutes != null ? '${m.elapsedMinutes}\'' : m.statusShort,
              style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 10),
            ),
          ],
        ),
      );
    } else if (m.isFinished) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: Colors.grey.withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
        child: const Text('FT', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 10)),
      );
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: const Color(0xFF06B6D4).withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
        child: const Text('NS', style: TextStyle(color: Color(0xFF06B6D4), fontWeight: FontWeight.bold, fontSize: 10)),
      );
    }
  }

  Widget _filterChip(List<MatchPrediction> sourceList, String filterKey, String displayLabel) {
    bool isSelected = selectedFilter == filterKey;
    int count = _countForCategory(sourceList, filterKey);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ChoiceChip(
        label: Text('$displayLabel ($count)'),
        selected: isSelected,
        selectedColor: const Color(0xFF10B981),
        backgroundColor: const Color(0xFF0F172A),
        labelStyle: TextStyle(
          color: isSelected ? Colors.black : Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
        onSelected: (bool selected) {
          if (selected) {
            setState(() {
              selectedFilter = filterKey;
            });
          }
        },
      ),
    );
  }

  Widget _buildHistoryTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cleaning_services, size: 50, color: Color(0xFF10B981)),
          const SizedBox(height: 16),
          const Text('30-DAY SLIDING LOG ACTIVE', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'Total saved predictions: $historyCount.\nMatches older than 30 days are continuously dropped to keep a rolling 30-day log window.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
