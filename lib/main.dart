import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const CalculatorApp());
}

// ─── App Root ────────────────────────────────────────────────────────────────

class CalculatorApp extends StatelessWidget {
  const CalculatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Liquid Glass Calculator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.white),
        useMaterial3: true,
        fontFamily: 'SF Pro Display',
      ),
      home: const CalculatorPage(),
    );
  }
}

// ─── Expression Parser ───────────────────────────────────────────────────────
//
// Extracted into a class so methods can forward-reference each other
// without Dart's "referenced before declaration" restriction on local functions.

class _ExpressionParser {
  _ExpressionParser(String expr) : _tokens = _tokenize(expr);

  final List<String> _tokens;
  int _pos = 0;

  /// Entry point — parse and return the result.
  double parse() => _parseExpr();

  double _parseExpr() {
    double result = _parseTerm();
    while (_pos < _tokens.length &&
        (_tokens[_pos] == '+' || _tokens[_pos] == '-')) {
      final op = _tokens[_pos++];
      final right = _parseTerm();
      result = op == '+' ? result + right : result - right;
    }
    return result;
  }

  double _parseTerm() {
    double result = _parseFactor();
    while (_pos < _tokens.length &&
        (_tokens[_pos] == '*' || _tokens[_pos] == '/')) {
      final op = _tokens[_pos++];
      final right = _parseFactor();
      result = op == '*' ? result * right : result / right;
    }
    return result;
  }

  double _parseFactor() {
    if (_pos < _tokens.length && _tokens[_pos] == '-') {
      _pos++;
      return -_parseFactor();
    }
    if (_pos < _tokens.length && _tokens[_pos] == '(') {
      _pos++;
      final val = _parseExpr();
      if (_pos < _tokens.length && _tokens[_pos] == ')') _pos++;
      return val;
    }
    final token = _tokens[_pos++];
    return double.parse(token);
  }

  static List<String> _tokenize(String expr) {
    final tokens = <String>[];
    final numBuffer = StringBuffer();

    void flushBuffer() {
      if (numBuffer.isNotEmpty) {
        tokens.add(numBuffer.toString());
        numBuffer.clear();
      }
    }

    for (int i = 0; i < expr.length; i++) {
      final ch = expr[i];
      if (ch == ' ') continue;
      if ('0123456789.'.contains(ch)) {
        numBuffer.write(ch);
      } else if ('+-*/()'.contains(ch)) {
        // Treat '-' as unary when it follows an operator, '(', or is first
        if (ch == '-' && (i == 0 || '+-*/('.contains(expr[i - 1]))) {
          numBuffer.write(ch);
        } else {
          flushBuffer();
          tokens.add(ch);
        }
      }
    }
    flushBuffer();
    return tokens;
  }
}

// ─── Calculator Logic ─────────────────────────────────────────────────────────

class CalculatorLogic {
  String _expression = '';
  String _display = '0';
  bool _hasResult = false;
  final List<String> _history = [];

  String get display => _display;
  String get expression => _expression;
  bool get hasResult => _hasResult;
  List<String> get history => List.unmodifiable(_history);

  void input(String value) {
    if (value == 'C') {
      _expression = '';
      _display = '0';
      _hasResult = false;
    } else if (value == 'Del' || value == '⌫') {
      _hasResult = false;
      if (_expression.isNotEmpty) {
        _expression = _expression.substring(0, _expression.length - 1);
        _display = _expression.isEmpty ? '0' : _expression;
      }
    } else if (value == '=') {
      _evaluate();
    } else if (value == '%') {
      _applyPercent();
    } else {
      // Map display-friendly symbols → eval-friendly operators
      _hasResult = false;
      final char = value == '×'
          ? '*'
          : value == '÷'
          ? '/'
          : value == '−'
          ? '-'
          : value;
      _expression += char;
      _display = _expression;
    }
  }

  void _evaluate() {
    if (_expression.isEmpty) return;
    try {
      final result = _ExpressionParser(_expression).parse();
      final resultStr = _formatNumber(result);
      final displayExpr = _expression
          .replaceAll('*', '×')
          .replaceAll('/', '÷')
          .replaceAll('-', '−');
      _history.add(displayExpr);
      _expression = resultStr;
      _display = resultStr;
      _hasResult = true;
    } catch (_) {
      _display = 'Error';
      _expression = '';
    }
  }

  void _applyPercent() {
    if (_expression.isEmpty) return;
    try {
      final val = _ExpressionParser(_expression).parse();
      _expression = _formatNumber(val / 100);
      _display = _expression;
    } catch (_) {}
  }

  String _formatNumber(double n) {
    if (n == n.truncateToDouble()) return n.toInt().toString();
    return double.parse(
      n.toStringAsFixed(10),
    ).toString().replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }
}

// ─── Main Page ────────────────────────────────────────────────────────────────

class CalculatorPage extends StatefulWidget {
  const CalculatorPage({super.key});

  @override
  State<CalculatorPage> createState() => _CalculatorPageState();
}

class _CalculatorPageState extends State<CalculatorPage>
    with SingleTickerProviderStateMixin {
  final _logic = CalculatorLogic();
  late final TabController _tabController;
  final ScrollController _historyScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _historyScroll.dispose();
    super.dispose();
  }

  void _onKey(String key) {
    setState(() => _logic.input(key));
    if (key == '=') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_historyScroll.hasClients) {
          _historyScroll.animateTo(
            _historyScroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F4F2),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 390),
            child: Column(
              children: [
                // ── Top Bar ────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.menu,
                        size: 22,
                        color: Color(0xFF1A1A1A),
                      ),
                    ],
                  ),
                ),

                // ── Tab Content ────────────────────────────────────────
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _CalculatorView(
                        logic: _logic,
                        historyScroll: _historyScroll,
                        onKey: _onKey,
                        tabController: _tabController,
                      ),
                      _ConverterPlaceholder(tabController: _tabController),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Calculator Tab View ──────────────────────────────────────────────────────

class _CalculatorView extends StatelessWidget {
  const _CalculatorView({
    required this.logic,
    required this.historyScroll,
    required this.onKey,
    required this.tabController,
  });

  final CalculatorLogic logic;
  final ScrollController historyScroll;
  final ValueChanged<String> onKey;
  final TabController tabController;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final displayHeight = (constraints.maxHeight * 0.43).clamp(
            250.0,
            330.0,
          );

          return Column(
            children: [
              SizedBox(
                height: displayHeight,
                child: _DisplayPanel(
                  logic: logic,
                  scrollController: historyScroll,
                  tabController: tabController,
                ),
              ),
              const SizedBox(height: 2),
              Expanded(child: _GlassKeypad(onKey: onKey)),
            ],
          );
        },
      ),
    );
  }
}

// ─── Display Panel ────────────────────────────────────────────────────────────

class _DisplayPanel extends StatelessWidget {
  const _DisplayPanel({
    required this.logic,
    required this.scrollController,
    required this.tabController,
  });

  final CalculatorLogic logic;
  final ScrollController scrollController;
  final TabController tabController;

  String _displayExpression(String value) {
    return value
        .replaceAll('*', ' × ')
        .replaceAll('/', ' ÷ ')
        .replaceAll('-', ' − ')
        .replaceAll('×', ' × ')
        .replaceAll('÷', ' ÷ ')
        .replaceAll('−', ' − ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.58),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.86),
              width: 1.1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(26, 16, 26, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Center(child: _PillTabBar(controller: tabController)),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: logic.history.length,
                  padding: EdgeInsets.zero,
                  itemBuilder: (_, i) {
                    final line = _displayExpression(logic.history[i]);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        line,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.black.withValues(alpha: 0.26),
                          fontWeight: FontWeight.w400,
                          height: 1.3,
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (logic.expression.isNotEmpty &&
                  logic.expression != logic.display)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    _displayExpression(logic.expression),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.black.withValues(alpha: 0.74),
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  logic.hasResult
                      ? '= ${logic.display}'
                      : logic.display == '0' && logic.expression.isEmpty
                      ? ''
                      : _displayExpression(logic.display),
                  style: const TextStyle(
                    fontSize: 52,
                    fontWeight: FontWeight.w300,
                    color: Color(0xFF111111),
                    letterSpacing: 0,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Container(
                  width: 88,
                  height: 3,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Glass Keypad ─────────────────────────────────────────────────────────────

class _GlassKeypad extends StatelessWidget {
  const _GlassKeypad({required this.onKey});

  final ValueChanged<String> onKey;

  static const _buttons = [
    ['C', 'Del', '%', '/'],
    ['7', '8', '9', '×'],
    ['4', '5', '6', '−'],
    ['1', '2', '3', '+'],
    ['⌫', '0', '.', '='],
  ];

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.48),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.78),
              width: 1.1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 34,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 18),
          child: Column(
            children: [
              Expanded(
                child: Column(
                  children: _buttons.map((row) {
                    return Expanded(
                      child: Row(
                        children: row.map((key) {
                          return Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: _CalcButton(
                                label: key,
                                onTap: () => onKey(key),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: 124,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Individual Calculator Button ─────────────────────────────────────────────

class _CalcButton extends StatefulWidget {
  const _CalcButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<_CalcButton> createState() => _CalcButtonState();
}

class _CalcButtonState extends State<_CalcButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressCtrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
      reverseDuration: const Duration(milliseconds: 150),
    );
    _scale = Tween<double>(
      begin: 1.0,
      end: 0.9,
    ).animate(CurvedAnimation(parent: _pressCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    super.dispose();
  }

  bool get _isOperator => ['/', '×', '−', '+', '=', '%'].contains(widget.label);
  bool get _isAction => ['C', 'Del', '⌫'].contains(widget.label);

  Color get _textColor {
    if (widget.label == '=') return const Color(0xFF111111);
    if (_isOperator) return const Color(0xFF2B2B2B);
    if (_isAction) return const Color(0xFF1F1F1F);
    return const Color(0xFF111111);
  }

  double get _fontSize {
    if (widget.label == 'Del') return 29;
    return 31;
  }

  @override
  Widget build(BuildContext context) {
    final isEquals = widget.label == '=';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _pressCtrl.forward(),
      onTapUp: (_) {
        _pressCtrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _pressCtrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(vertical: 3),
          decoration: isEquals
              ? BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.42),
                    width: 0.8,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                )
              : null,
          child: Center(
            child: widget.label == '⌫'
                ? Icon(Icons.recycling_rounded, size: 27, color: _textColor)
                : Text(
                    widget.label,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: _fontSize,
                      fontWeight: FontWeight.w400,
                      color: _textColor,
                      letterSpacing: 0,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

// ─── Pill Tab Bar ─────────────────────────────────────────────────────────────

class _PillTabBar extends StatelessWidget {
  const _PillTabBar({required this.controller});

  final TabController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.8)),
          ),
          padding: const EdgeInsets.all(3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PillTab(
                label: 'calculator',
                selected: controller.index == 0,
                onTap: () => controller.animateTo(0),
              ),
              _PillTab(
                label: 'converter',
                selected: controller.index == 1,
                onTap: () => controller.animateTo(1),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PillTab extends StatelessWidget {
  const _PillTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? const Color(0xFF1A1A1A) : const Color(0xFF888888),
            letterSpacing: 0.1,
          ),
        ),
      ),
    );
  }
}

// ─── Converter Placeholder ────────────────────────────────────────────────────

class _ConverterPlaceholder extends StatelessWidget {
  const _ConverterPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Converter\ncoming soon',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Color(0xFFAAAAAA),
          fontSize: 18,
          fontWeight: FontWeight.w300,
        ),
      ),
    );
  }
}
