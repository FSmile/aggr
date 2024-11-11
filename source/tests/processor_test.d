module tests.processor_test;

import std.stdio : File, writeln;
import std.file : remove;
import std.string : indexOf;
import std.conv : ConvException;
import std.algorithm : sort;
import config.settings : Config;
import core.interfaces : ILogAnalyzer, ILogger, IApplication;
import core.types : LogStatistics, LogLevel;
import workers.processor : DataProcessor;
import std.path : buildPath;
import std.file : tempDir;
import std.conv : to;
import std.file : exists, getSize;
import core.sync.mutex : Mutex;
import core.thread : Thread;
import core.time : msecs;
import core.atomic : atomicLoad;

// Mock для LogAnalyzer
class LogAnalyzerMock : ILogAnalyzer {
    private {
        shared int processedLines;
        shared string lastContext;
        shared Mutex mutex;
    }

    this() {
        mutex = new shared Mutex();
    }

    void processLine(string line, size_t workerId = 0) @trusted {
        synchronized(mutex) {
            import core.atomic : atomicOp;
            atomicOp!"+="(processedLines, 1);
            lastContext = line.idup;
        }
    }

    void writeResults() @safe {}
    LogStatistics getStatistics() @safe { return LogStatistics.init; }
    
    int getLineCount() @safe { 
        synchronized(mutex) {
            return atomicLoad(processedLines);
        }
    }
    
    string getLastContext() { 
        synchronized(mutex) {
            return lastContext.idup;
        }
    }
    
    int getProcessedLines() { 
        synchronized(mutex) {
            return atomicLoad(processedLines);
        }
    }
}

class TestLogger : ILogger {
    void debug_(string msg) { writeln("DEBUG: ", msg); }
    void info(string msg) { writeln("INFO: ", msg); }
    void warning(string msg) { writeln("WARN: ", msg); }
    void error(string msg, Exception e = null) { 
        writeln("ERROR: ", msg);
        if (e !is null) writeln("Exception: ", e.toString());
    }
    void log(LogLevel level, string message, string file = __FILE__, int line = __LINE__) {
        writeln(level, ": ", message);
    }
}

class MockApplication : IApplication {
    private bool errorReported = false;
    
    void reportError() {
        errorReported = true;
    }
    
    bool wasErrorReported() {
        return errorReported;
    }
}

unittest {
    // Устанавливаем UTF-8 для консоли
    version(Windows) {
        import core.sys.windows.windows;
        SetConsoleOutputCP(CP_UTF8);
    }
    
    writeln("Начало теста");
    
    // Создаём более простой тестовый файл для начала
    string testFilePath = buildPath(tempDir(), "test.log");
    File testFile;
    
    try {
        testFile = File(testFilePath, "w");
        writeln("Файл создан: ", testFilePath);
        
        // Записываем более простые тестовые данные
        testFile.writeln("40:33.299009-1515852,DBPOSTGRS,6,Context='Simple test'");
        testFile.flush();
        testFile.close();
        
        writeln("Данные записаны в файл");
    } catch (Exception e) {
        assert(false, "Ошибка при записи в файл: " ~ e.msg);
    }
    
    scope(exit) {
        if (exists(testFilePath)) {
            remove(testFilePath);
        }
    }
    
    auto logger = new TestLogger();
    auto config = Config.fromArgs(["aggr", testFilePath], true);
    config.workerCount = 1;
    config.logger = logger;
    writeln("Конфигурация создана: ", config);
    
    auto analyzer = new LogAnalyzerMock();
    auto mockApp = new MockApplication();
    auto processor = new DataProcessor(config, analyzer, mockApp);
    writeln("Процессор создан");
    
    try {
        writeln("Проверка существования файла: ", exists(testFilePath));
        writeln("Размер файла: ", getSize(testFilePath));
        
        writeln("Начало обработки файла");
        processor.start();
        Thread.sleep(100.msecs);
        writeln("Обработка файла завершена");
        
        auto processedLines = analyzer.getProcessedLines();
        writeln("Обработано строк: ", processedLines);
        assert(processedLines == 1, "Неверное количество обработанных строк");
        
    } catch (Exception e) {
        writeln("Ошибка при обработке файла: ", e.toString());
        assert(false, "Ошибка при обработке файла: " ~ e.msg);
    }
} 

 