// Frame timings of integration_test/ui_perf_test.dart, as a summary in
// build/ (average and worst build/raster times, missed frames).
//
//   flutter drive --profile -d windows --driver=test_driver/perf_driver.dart --target=integration_test/ui_perf_test.dart
import 'package:flutter_driver/flutter_driver.dart';
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
      responseDataCallback: (data) async {
        if (data == null) return;
        for (final key in data.keys) {
          final timeline = Timeline.fromJson(data[key] as Map<String, dynamic>);
          await TimelineSummary.summarize(timeline)
              .writeTimelineToFile(key, pretty: true, includeSummary: true);
        }
      },
    );
