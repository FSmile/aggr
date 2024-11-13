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
import core.time : msecs, Duration, seconds;
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

    void writeResults() @safe {
        // В mock-объекте ничего не делаем
    }

    LogStatistics getStatistics() @safe {
        synchronized(mutex) {
            return LogStatistics(
                atomicLoad(processedLines),  // totalLines
                atomicLoad(processedLines),  // processedLines
                0,                          // errorCount
                Duration.zero              // totalProcessingTime
            );
        }
    }
    
    int getLineCount() @safe {
        synchronized(mutex) {
            return atomicLoad(processedLines);
        }
    }

    void flushThreadBuffer(size_t workerId) @trusted {
        synchronized(mutex) {
            // В mock-объекте ничего не делаем
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

    void dispose() @safe {
        // В mock-объекте ничего не делаем
    }
}

class TestLogger : ILogger {
    private string[] messages;
    private shared Mutex mutex;

    this() {
        mutex = new shared Mutex();
    }

    void log(LogLevel level, string message, string file = __FILE__, int line = __LINE__) {
        synchronized(mutex) {
            messages ~= level.to!string ~ ": " ~ message;
        }
    }

    void error(string message, Exception e = null) {
        synchronized(mutex) {
            if (e !is null) {
                messages ~= "ERROR: " ~ message ~ " - " ~ e.msg;
            } else {
                messages ~= "ERROR: " ~ message;
            }
        }
    }

    void warning(string message) { log(LogLevel.WARNING, message); }
    void info(string message) { log(LogLevel.INFO, message); }
    void debug_(string message) { log(LogLevel.DEBUG, message); }

    string[] getMessages() {
        synchronized(mutex) {
            return messages.dup;
        }
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
    
    // Создаем временный файл с тестовыми данными
    auto tempFile = buildPath(tempDir, "test.log");
    writeln("Файл со��дан: ", tempFile);
    
    {
        auto file = File(tempFile, "w");
        file.writeln("40:33.299009-1515852,DBPOSTGRS,6,Context=TestContext,Duration=1234");
        file.close();
        writeln("Данные записаны в файл");
    }
    
    // Создаем конфигурацию
    auto config = Config();
    config.inputPath = tempFile;
    config.outputPath = "output.csv";
    config.logPath = "aggr.log";
    config.groupBy = ["Context"];
    config.durationField = "Duration";
    config.workerCount = 1;
    config.timeout = 5.seconds;
    config.logger = new TestLogger();
    config.multilineFields = ["Context"];
    
    writeln("Конфигурация создана: ", config);
    
    // Создаем анализатор, приложение и процессор
    auto analyzer = new LogAnalyzerMock();
    auto app = new MockApplication();
    auto processor = new DataProcessor(config, analyzer, app);
    writeln("Процессор создан");
    
    // Проверяем существование файла
    assert(tempFile.exists, "Файл не существует");
    writeln("Проверка существования файла: ", tempFile.exists);
    
    auto fileSize = getSize(tempFile);
    writeln("Размер файла: ", fileSize);
    assert(fileSize > 0, "Файл пустой");
    
    // Запускаем обработку и ждем завершения
    writeln("Начало обработки файла");
    processor.start();
    
    // Ждем завершения с таймаутом
    size_t attempts = 0;
    const size_t MAX_ATTEMPTS = 50; // 500ms максимум
    while (!processor.waitForCompletion() && attempts < MAX_ATTEMPTS) {
        Thread.sleep(10.msecs);
        attempts++;
    }
    
    if (attempts >= MAX_ATTEMPTS) {
        assert(false, "Timeout waiting for processor completion");
    }
    
    // Проверяем результаты
    auto processedLines = analyzer.getProcessedLines();
    assert(processedLines == 1, 
           "Неверное количество обработанных строк: " ~ processedLines.to!string);
           
    auto lastContext = analyzer.getLastContext();
    assert(lastContext == "40:33.299009-1515852,DBPOSTGRS,6,Context=TestContext,Duration=1234",
           "Неверное содержимое последней строки: " ~ lastContext);
    
    // Проверяем, что не было ошибок
    assert(!app.wasErrorReported(), "Была обнаружена ошибка в процессе обработки");
    
    // Очистка
    processor.shutdown();
    Thread.sleep(100.msecs);
    
    if (tempFile.exists) {
        remove(tempFile);
    }
} 

 