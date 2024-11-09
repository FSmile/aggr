module log.analyzer;

import std.stdio;
import std.string;
import std.conv;
import std.typecons : Nullable;
import std.traits : isNumeric;
import core.sync.mutex : Mutex;
import core.atomic : atomicLoad, atomicOp;
import core.time : Duration;

import core.interfaces : ILogAnalyzer, IResultWriter, ILogger;
import core.types : LogLine, LogStatistics;
import log.parser : ILogParser;

import std.array : array;
import std.algorithm : sort;
import utils.hash : getFastHash;
import std.format : format;

interface IResultWriter {
    void write(LogLine[] results);
}

class CsvResultWriter : IResultWriter {
    private string filePath;

    this(string path) {
        filePath = path;
    }

    void write(LogLine[] results) {
        // Реализация записи в CSV
    }

    void close() {
        // Ничего не делаем, так как файл закрывается после каждой записи
    }
}

class LogAnalyzer : ILogAnalyzer {

    private {
        LogLine[string] items;
        File outputFile;
        shared int lineCount = 0;
        shared Mutex itemsMutex;
        shared Mutex dataMutex;
        shared Mutex outputMutex;
        shared string currentLine = "";
        shared bool isMultiline = false;
        ILogParser parser;
        IResultWriter writer;
        ILogger logger;
    }

    this(ILogParser parser, IResultWriter writer, ILogger logger, size_t workerCount = 1) {
        this.parser = parser;
        this.writer = writer;
        this.logger = logger;
        itemsMutex = new shared Mutex();
        dataMutex = new shared Mutex();
        outputMutex = new shared Mutex();
    }

    ~this() {
        synchronized(outputMutex) {  // Добавить синхонизацию
            if (outputFile.isOpen) {
                outputFile.close();
            }
        }
    }

    void processLine(string line, size_t workerId = 0) @trusted {
        synchronized(dataMutex) {
            try {
                auto result = parser.parse(line);
                if (!result.isNull) {
                    auto hash = getFastHash(result.get["Context"]);
                    if (hash in items) {
                        items[hash].updateStats(result.get["Duration"].to!long);
                    } else {
                        items[hash] = LogLine(
                            hash,
                            result.get["Context"],
                            result.get["Duration"].to!long
                        );
                    }
                    
                    if (atomicOp!"+="(lineCount, 1) % 10000 == 0) {
                        try {
                            logger.info("Processed %d lines, unique contexts: %d"
                                .format(lineCount, items.length));
                        } catch (Exception) {} // Игнорируем ошибки логирования
                    }
                }
            } catch (Exception e) {
                try {
                    logger.error("Error processing line: " ~ line, e);
                } catch (Exception) {} // Игнорируем ошибки логирования
            }
        }
    }

    void writeResults() @trusted {
        synchronized(dataMutex) {
            auto sortedItems = items.values.array();
            sortedItems.sort!((a, b) => a.avg > b.avg);
            writer.write(sortedItems);
        }
    }

    LogStatistics getStatistics() {
        synchronized(dataMutex) {
            return LogStatistics(
                atomicLoad(lineCount),
                items.length,
                0, // errorCount
                Duration.zero // totalProcessingTime
            );
        }
    }

    int getLineCount() {
        return atomicLoad(lineCount);
    }


}