import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'dart:ffi';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:sudoku/ml/yolov8/yolov8_output.dart';
import 'package:sudoku/native/sudoku.dart';
import 'package:sudoku/page/ai_detection_painter.dart';
import 'package:sudoku_dart/sudoku_dart.dart';

Logger log = Logger();

/// just define magic -1 to SUDOKU_EMPTY_DIGIT , make code easier to read and know
const int SUDOKU_EMPTY_DIGIT = -1;

/// Detect Ref
///
///
class DetectRef {
  /// puzzle index
  final int index;

  /// puzzle value of index
  final int value;

  /// puzzle value of index from detect box
  final YoloV8DetectionBox box;

  const DetectRef({
    required this.index,
    required this.value,
    required this.box,
  });
}

class AIDetectionMainWidget extends StatefulWidget {
  final List<DetectRef?> detectRefs;
  final ui.Image image;
  final Uint8List imageBytes;
  final double widthScale;
  final double heightScale;
  final YoloV8Output output;

  const AIDetectionMainWidget({
    Key? key,
    required this.detectRefs,
    required this.image,
    required this.imageBytes,
    required this.widthScale,
    required this.heightScale,
    required this.output,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() => _AIDetectionMainWidgetState();
}

class _AIDetectionMainWidgetState extends State<AIDetectionMainWidget> {
  /// amendable cell edit on this "amendPuzzle"
  ///
  /// when amendPuzzle[index] != SUDOKU_EMPTY_DIGIT (-1) , grid cell of index will show value with blue color text
  late List<int> amendPuzzle;

  late List<int> solution;
  late String solveMessage;
  bool? oneSolution;
  int? selectedBox = null;

  /// cacheable widgets
  /// _aiDetectionPainter cache instance
  var _aiDetectionPainter;

  @override
  void initState() {
    super.initState();

    amendPuzzle = _emptyMatrix();
    solution = _emptyMatrix();
    solveMessage = "";

    /// 初始化 AIDetectionPainter
    _aiDetectionPainter = AIDetectionPainter(
      image: widget.image,
      output: widget.output,
      offset: ui.Offset(0, 0),
      widthScale: widget.widthScale,
      heightScale: widget.heightScale,
    );
  }

  _emptyMatrix() {
    return List.generate(81, (_) => SUDOKU_EMPTY_DIGIT);
  }

  _solveSudoku() {
    log.d("solve sudoku puzzle ...");
    try {
      // merge puzzle from detectRefs and amendPuzzle
      final List<int> puzzle = _emptyMatrix();
      for (var index = 0; index < puzzle.length; ++index) {
        DetectRef? detectRef = widget.detectRefs[index];
        if (amendPuzzle[index] != SUDOKU_EMPTY_DIGIT) {
          puzzle[index] = amendPuzzle[index];
        } else if (detectRef != null && detectRef.value != SUDOKU_EMPTY_DIGIT) {
          puzzle[index] = detectRef.value;
        }
      }

      final sudoku = Sudoku(puzzle);

      // one solution check
      var isOneSolutionSudoku = true;
      try {
        var beginCheckTime = DateTime.now();
        // Sudoku(puzzle, strict: true);
        List<int> solution =
            SudokuNativeHelper.instance!.solve(puzzle, isStrict: true);
        var endCheckTime = DateTime.now();
        log.d(
            "check one solution time: ${endCheckTime.difference(beginCheckTime)}");
        log.d("solution : $solution");
      } catch (e, stacktrace) {
        // puzzle is not one-solution sudoku
        log.e(e, stackTrace: stacktrace);
        isOneSolutionSudoku = false;
      }

      setState(() {
        solution = sudoku.solution;
        solveMessage = "";
        oneSolution = isOneSolutionSudoku;
      });
    } catch (e) {
      // seem this puzzle can't be solve because is wrong puzzle
      log.e(e);
      if (e.runtimeType == StateError) {
        final errorMessage = (e as StateError).message;
        setState(() {
          solution = _emptyMatrix();
          solveMessage = errorMessage;
        });
      }
    }
  }

  /// _notDetectedWidget instance
  final _notDetectedWidget = const Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: const [
      Icon(
        Icons.block,
        size: 128,
        color: Colors.white,
        shadows: [ui.Shadow(blurRadius: 1.68)],
      ),
      Center(
        child: Text("Not Detected",
            style: TextStyle(
              fontSize: 36,
              color: Colors.white,
              shadows: [ui.Shadow(blurRadius: 1.68)],
            )),
      ),
    ],
  );

  /// build detected widget function
  ///
  /// with amendable gridview
  _buildDetectedWidget() {
    final detectRefs = widget.detectRefs;
    return GridView.builder(
      padding: EdgeInsets.zero,
      physics: NeverScrollableScrollPhysics(),
      shrinkWrap: false,
      itemCount: 81,
      gridDelegate:
          SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 9),
      itemBuilder: ((BuildContext context, int index) {
        DetectRef? detectRef = detectRefs[index];

        // default cell text/style/border style
        // detected by AI , color with yellow
        // amend of cell by user , color with blue
        // solutions from Sudoku Solver , color with white
        var cellTextColor =
            detectRef != null && detectRef.value != SUDOKU_EMPTY_DIGIT
                ? Colors.yellow
                : Colors.white;
        var cellText = "";
        var cellBorder = Border.all(color: Colors.amber, width: 1.5);
        String? fontFamily = null;

        if (amendPuzzle[index] != SUDOKU_EMPTY_DIGIT) {
          // 修正的谜题
          // if this cell of puzzle been amend , change cell text color to blue
          cellText = amendPuzzle[index].toString();
          cellTextColor = Colors.blue;
        } else if (detectRef != null && detectRef.value != SUDOKU_EMPTY_DIGIT) {
          // 检测关联的谜题
          cellText = detectRef.value.toString();
          cellTextColor = Colors.yellow;
        } else if (solution[index] != SUDOKU_EMPTY_DIGIT) {
          // solutions
          cellText = solution[index].toString();
          cellTextColor = Colors.white;
          fontFamily = "handwriting_digits";
        }

        if (index == selectedBox) {
          // if choose cell , change the border color to blue
          cellBorder = Border.all(color: Colors.blue, width: 2.0);
        }

        var _cellText = Text(
          cellText,
          style: TextStyle(
              fontFamily: fontFamily,
              shadows: [
                ui.Shadow(blurRadius: 1.18),
                ui.Shadow(blurRadius: 3.68),
                ui.Shadow(blurRadius: 5.38)
              ],
              fontSize: 26,
              color: cellTextColor),
        );

        var _cellContainer = Container(
          decoration: BoxDecoration(
            border: cellBorder,
          ),
          child: Container(
            child: _cellText,
            margin: EdgeInsets.only(left: 5.0),
          ),
        );

        return GestureDetector(
          child: _cellContainer,
          onTap: () => _selectedBoxSwitch(index),
        );
      }),
    );
  }

  _selectedBoxSwitch(index) {
    setState(() {
      if (index == selectedBox) {
        selectedBox = null;
        // cancel selectedBox
      } else {
        selectedBox = index;
        // @TODO here should show dialog to input amend value from user
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final uiImage = widget.image;

    // 主画面控件
    var _mainWidget;

    var hasDetectionSudoku = widget.output.boxes.isNotEmpty;
    if (!hasDetectionSudoku) {
      _mainWidget = _notDetectedWidget;
    } else {
      _mainWidget = _buildDetectedWidget();
    }

    var _drawWidget = CustomPaint(
      isComplex: true,
      willChange: true,
      child: _mainWidget,
      painter: _aiDetectionPainter,
    );

    var _btnWidget = Offstage(
      offstage: !hasDetectionSudoku,
      child: IconButton(
        icon: Icon(Icons.visibility),
        iconSize: 36,
        onPressed: _solveSudoku,
      ),
    );

    var _bodyWidget = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // show solve message output
        Center(
          child: Text(
            solveMessage,
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
          ),
        ),
        Center(
            child: Text(
          oneSolution == null
              ? ""
              : oneSolution!
                  ? "✅one solution puzzle"
                  : "❌this puzzle is not one solution",
          style: TextStyle(
            color:
                oneSolution != null && oneSolution! ? Colors.green : Colors.red,
          ),
        )),
        Center(
          child: SizedBox(
              width: uiImage.width.toDouble(),
              height: uiImage.height.toDouble(),
              child: _drawWidget),
        ),
        Center(child: _btnWidget),
      ],
    );

    return Scaffold(
      appBar: AppBar(title: Text("Detection Result")),
      body: _bodyWidget,
    );
  }
}
