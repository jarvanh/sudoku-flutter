import 'dart:ffi' as ffi;
import 'dart:io' show Directory;

import 'package:ffi/ffi.dart';
import 'package:logger/logger.dart' hide Level;
import 'package:path/path.dart' as path;
import 'package:sudoku/native/nativefl.dart';
import 'package:sudoku/native/sudoku.dart';

final _libraryPath = path.join(Directory.current.path, 'test', 'libsudoku.so');
final _dylib = ffi.DynamicLibrary.open(_libraryPath);
final _nf = Nativefl(_dylib);

List<int> nativeGenerate(int level) {
  final outputPointer = calloc.allocate<ffi.Void>(81);

  _nf.Generate(level, outputPointer);

  final sudokuChannel = outputPointer.cast<sudoku_channel>().ref;
  final isError = sudokuChannel.err != 0;

  if (isError) {
    log.e("native sudoku generate error");
    throw Exception("native sudoku generate error");
  }
  final matrix = sudokuChannel.matrix;
  final result = matrix.cast<ffi.Int8>().asTypedList(81);

  List<int> puzzle = [];
  for (var item in result) {
    puzzle.add(item);
  }
  calloc.free(outputPointer);

  return puzzle;
}

List<int> nativeSolve(List<int> puzzle, {bool isStrict = false}) {
  final inputPointer = calloc.allocate<ffi.Void>(81);
  final outputPointer = calloc.allocate<ffi.Void>(ffi.sizeOf<sudoku_channel>());

  inputPointer.cast<ffi.Int8>().asTypedList(81).setAll(0, puzzle);

  _nf.Solve(inputPointer, isStrict ? 1 : 0, outputPointer);

  final sudokuChannel = outputPointer.cast<sudoku_channel>().ref;
  final isError = sudokuChannel.err != 0;
  if (isError) {
    log.e("native sudoku solver error");
    throw Exception("native sudoku solver error");
  }

  final matrixPointer = sudokuChannel.matrix;
  var nativeSolution = matrixPointer.cast<ffi.Int8>().asTypedList(81);

  List<int> solution = [];
  for (var item in nativeSolution) {
    solution.add(item);
  }
  calloc.free(inputPointer);
  calloc.free(outputPointer);

  return solution;
}

Logger log = Logger();

void main() {
  var beginTime, endTime;

  // beginTime = DateTime.now();
  // var sudoku = Sudoku.generate(Level.expert);
  // endTime = DateTime.now();
  // log.d("dart sudoku generator");
  // log.d("total time : ${endTime.millisecondsSinceEpoch - beginTime.millisecondsSinceEpoch}'ms");

  beginTime = DateTime.now();
  // List<int> puzzle = SudokuNativeHelper.instance.generate(4);
  List<int> puzzle = nativeGenerate(4);
  endTime = DateTime.now();
  log.d("native sudoku generator");
  log.d(
      "total time : ${endTime.millisecondsSinceEpoch - beginTime.millisecondsSinceEpoch}'ms");

  print(puzzle);
  print("===");

  // List<int> solution = SudokuNativeHelper.instance.solve(puzzle,isStrict:true);
  List<int> solution = nativeSolve(puzzle, isStrict: true);

  print(puzzle);
  print(solution);
}
