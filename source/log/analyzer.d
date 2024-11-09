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
import std.algorithm : map;

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
        string[] contextBuffer;
        shared Mutex contextMutex;
    }

    this(ILogParser parser, IResultWriter writer, ILogger logger, size_t workerCount = 1) {
        this.parser = parser;
        this.writer = writer;
        this.logger = logger;
        itemsMutex = new shared Mutex();
        dataMutex = new shared Mutex();
        outputMutex = new shared Mutex();
        contextMutex = new shared Mutex();
    }

    ~this() {
        synchronized(outputMutex) {  // Добавить синхонизацию
            if (outputFile.isOpen) {
                outputFile.close();
            }
        }
    }

    void processLine(string line, size_t workerId = 0) @trusted {
        auto trimmedLine = line.stripRight();
        synchronized(contextMutex) {
            logger.debug_("Processing line: " ~ line);
            logger.debug_("Trimmed line: " ~ trimmedLine);
            logger.debug_("Line length: " ~ trimmedLine.length.to!string);
            
            if (trimmedLine.indexOf("Context='") != -1) {
                logger.debug_("Found start of multiline context");
                contextBuffer = [line];
                return;
            }
            
            if (contextBuffer.length > 0) {
                logger.debug_("Context buffer length: " ~ contextBuffer.length.to!string);
                if (trimmedLine.endsWith("'")) {
                    logger.debug_("Found end of multiline context");
                    contextBuffer ~= trimmedLine[0..$-1];
                    auto fullContext = contextBuffer[0].strip();
                    if (contextBuffer.length > 1) {
                        fullContext ~= "\n" ~ contextBuffer[1..$].map!(line => line.strip()).join("\n");
                    }
                    logger.debug_("Full context: " ~ fullContext);
                    processFullContext(fullContext);
                    contextBuffer.length = 0;
                    atomicOp!"+="(lineCount, 1);
                } else {
                    logger.debug_("Adding line to context buffer");
                    contextBuffer ~= line;
                }
                return;
            }
            
            logger.debug_("Processing as single line");
            processFullContext(line);
        }
    }

    private void processFullContext(string fullContext) {
        synchronized(dataMutex) {
            try {
                logger.debug_("Processing full context: " ~ fullContext);
                auto result = parser.parse(fullContext);
                
                if (!result.isNull) {
                    logger.debug_("Parse result - Duration: " ~ result.get["Duration"] ~ 
                                ", Context: " ~ result.get["Context"]);
                    
                    auto hash = getFastHash(result.get["Context"]);
                    logger.debug_("Generated hash: " ~ hash);
                    
                    if (hash in items) {
                        logger.debug_("Updating existing item");
                        items[hash].updateStats(result.get["Duration"].to!long);
                    } else {
                        logger.debug_("Creating new item");
                        items[hash] = LogLine(
                            hash,
                            result.get["Context"],
                            result.get["Duration"].to!long
                        );
                    }
                    
                    logger.debug_("Items count: " ~ items.length.to!string);
                } else {
                    logger.debug_("Parser returned null result");
                }
            } catch (Exception e) {
                logger.error("Error processing context: " ~ e.msg ~ "\n" ~ e.toString());
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