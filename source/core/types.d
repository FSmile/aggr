module core.types;

import core.time : Duration;
import std.exception : enforce;

// Уровни логирования
enum LogLevel {
    DEBUG,
    INFO,
    WARNING,
    ERROR
}

// Статистика обработки логов
struct LogStatistics {
    long totalLines;
    long processedLines;
    long errorCount;
    Duration totalProcessingTime;
}

// Метрики
struct MetricsSnapshot {
    long processedLines;
    long errorCount;
    Duration averageProcessingTime;
    Duration maxProcessingTime;
}

struct LogLine {
    string hash;
    string lastContext;
    long duration;
    int count = 1;
    long sum;
    long max;

    @property long avg() const { return sum / count; }

    this(string h, string c, long d) @safe {
        hash = h;
        lastContext = c;
        duration = d;
        sum = d;
        max = d;
    }

    void updateStats(long duration) {
        count++;
        sum += duration;
        if (duration > max) max = duration;
    }
}

struct DataBuffer {
    string[] lines;
    size_t startIdx;
    size_t endIdx;
}