module core.types;

import core.time : Duration;
import std.exception : enforce;
import std.conv : to;

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
    string[string] fields;  // Хранение всех полей группировки
    long duration;
    int count = 1;
    long sum;
    long max;

    long avg() const @safe {
        return sum / count;
    }

    this(string h, string[string] f, long d) @safe {
        hash = h;
        fields = f;
        fields["Duration"] = d.to!string;
        duration = d;
        sum = d;
        max = d;
    }

    void updateStats(long duration) @safe {
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

struct FieldInfo {
    string name;
    string value;
    bool isMultiline;
}
