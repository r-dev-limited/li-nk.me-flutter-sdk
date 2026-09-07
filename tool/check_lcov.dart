import 'dart:io';

const minimumLineCoverage = 75.0;

void main() {
  final file = File('coverage/lcov.info');
  if (!file.existsSync()) {
    stderr.writeln('coverage/lcov.info is missing; run flutter test --coverage first');
    exitCode = 1;
    return;
  }

  var found = 0;
  var hit = 0;
  for (final line in file.readAsLinesSync()) {
    if (line.startsWith('LF:')) {
      found += int.tryParse(line.substring(3)) ?? 0;
    } else if (line.startsWith('LH:')) {
      hit += int.tryParse(line.substring(3)) ?? 0;
    }
  }
  final percent = found == 0 ? 0.0 : hit * 100 / found;
  stdout.writeln(
    'Flutter line coverage: ${percent.toStringAsFixed(2)}% ($hit/$found)',
  );
  if (percent < minimumLineCoverage) {
    stderr.writeln(
      'Flutter line coverage is below the ${minimumLineCoverage.toStringAsFixed(0)}% minimum.',
    );
    exitCode = 1;
  }
}
