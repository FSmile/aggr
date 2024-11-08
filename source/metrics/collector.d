module metrics.collector;

import core.sync.mutex : Mutex;
import core.time : Duration;
import core.atomic : atomicOp;
import core.interfaces : IMetricsCollector;
import core.types : MetricsSnapshot;

struct LogStatistics {
    long totalLines;
    long processedLines;
    long errorCount;
    Duration totalProcessingTime;
}

class MetricsCollector : IMetricsCollector {
    private {
        Duration totalProcessingTime;
        Duration maxProcessingTime;
        shared long processedLines = 0;
        shared long errorCount = 0;
        shared Mutex metricsMutex;
    }

    this() {
        metricsMutex = new shared Mutex();
    }

    void recordProcessedLine() {
        synchronized(metricsMutex) {
            atomicOp!"+="(processedLines, 1);
        }
    }

    void recordError() {
        synchronized(metricsMutex) {
            atomicOp!"+="(errorCount, 1);
        }
    }

    void recordProcessingTime(Duration duration) {
        synchronized(metricsMutex) {
            totalProcessingTime += duration;
            if (duration > maxProcessingTime) {
                maxProcessingTime = duration;
            }
        }
    }

    MetricsSnapshot getSnapshot() {
        synchronized(metricsMutex) {
            long lines = cast(long)(processedLines);
            Duration avg = lines > 0 ? (totalProcessingTime / lines) : Duration.zero;

            return MetricsSnapshot(
                lines,
                cast(long)(errorCount),
                avg,
                maxProcessingTime
            );
        }
    }
} 

 