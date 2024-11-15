module core.types;

import core.time : Duration;
import std.exception : enforce;
import std.conv : to;
import workers.thread_pool;
import core.sync.mutex : Mutex;
import core.sync.condition : Condition;
import core.interfaces : ILogger;
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
    if (count == 0) {
        return 0;
    }
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
    
    this(string[] lines) {
        this.lines = lines;
    }
}

struct FieldInfo {
    string name;
    string value;
    bool isMultiline;
}

struct ThreadBuffer {
    private {
        LogLine[string] items;  // hash -> LogLine
        shared Mutex mutex;
        size_t workerId;
        bool isProcessing;
        ILogger logger;
    }
    
    this(size_t id, ILogger logger) {
        mutex = new shared Mutex();
        workerId = id;
        isProcessing = false;
        this.logger = logger;
    }
    
    void startProcessing() {
        synchronized(mutex) {
            isProcessing = true;
        }
    }
    
    void stopProcessing() {
        synchronized(mutex) {
            isProcessing = false;
        }
    }
    
    bool isActive() {
        synchronized(mutex) {
            return isProcessing;
        }
    }
    
    void add(string hash, LogLine line) {
        synchronized(mutex) {
            logger.debug_("Adding to buffer " ~ workerId.to!string ~ ": " ~ hash);
            if (hash in items) {
                items[hash].updateStats(line.duration);
                logger.debug_("Updated existing record in buffer " ~ workerId.to!string);
            } else {
                items[hash] = line;
                logger.debug_("Added new record to buffer " ~ workerId.to!string);
            }
        }
    }
    
    LogLine[] flush() @trusted {
        synchronized(mutex) {
            LogLine[] result;
            foreach(line; items.byValue) {
                result ~= line;
            }
            items.clear();
            return result;
        }
    }
}
