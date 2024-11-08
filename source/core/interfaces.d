module core.interfaces;

import core.time : Duration;
import core.types : LogLevel, LogLine, LogStatistics, MetricsSnapshot;

// Интерфейс для анализатора логов
interface ILogAnalyzer {
    void processLine(string line);
    void writeResults();
    LogStatistics getStatistics();
    int getLineCount();
}

// Интерфейс для логирования
interface ILogger {
    void log(LogLevel level, string message, string file = __FILE__, int line = __LINE__);
    void error(string message, Exception e = null);
    void info(string message);
    void debug_(string message);
}

// Интерфейс для обработки результатов
interface IResultWriter {
    void write(LogLine[] results);
    void close();
}

// Интерфейс для сборщика метрик
interface IMetricsCollector {
    void recordProcessingTime(Duration duration);
    void recordError();
    void recordProcessedLine();
    MetricsSnapshot getSnapshot();
} 

 