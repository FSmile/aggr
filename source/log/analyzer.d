module log.analyzer;

import std.stdio;
import std.string;
import std.conv;
import std.typecons : Nullable;
import std.traits : isNumeric;
import core.sync.mutex : Mutex;
import core.atomic : atomicLoad, atomicOp;
import core.time : Duration;
import config.settings : Config;

import core.interfaces : ILogAnalyzer, IResultWriter, ILogger, ILogParser;
import core.types : LogLine, LogStatistics;

import std.array : array;
import std.algorithm : sort;
import utils.hash : getFastHash;
import std.format : format;
import std.algorithm : map;

import std.conv : to;
import std.json : parseJSON;
import std.file : isFile;
import std.algorithm : any;
import std.algorithm : canFind;

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
        Config config;
    }

    this(ILogParser parser, IResultWriter writer, ILogger logger, Config config) {
        this.parser = parser;
        this.writer = writer;
        this.logger = logger;
        this.config = config;
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
        atomicOp!"+="(lineCount, 1);
        auto trimmedLine = line.stripRight();
        synchronized(contextMutex) {
            logger.debug_("Processing line: " ~ line);
            logger.debug_("Trimmed line: " ~ trimmedLine);
            logger.debug_("Line length: " ~ trimmedLine.length.to!string);
            
            if (config.multilineFields.length > 0 && 
                config.multilineFields.any!(field => 
                    config.groupBy.canFind(field) && 
                    trimmedLine.indexOf(field ~ "='") != -1
                )) {
                logger.debug_("Found start of multiline field that is used in grouping");
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
                auto result = parser.parse(fullContext);
                
                if (!result.isNull) {
                    // Проверяем наличие полей группировки
                    bool hasAllFields = true;
                    foreach (field; config.groupBy) {
                        if (field !in result.get) {
                            hasAllFields = false;
                            break;
                        }
                    }
                    
                    if (!hasAllFields) {
                        return;
                    }
                    
                    auto hash = generateGroupKey(result.get);
                    if (hash.length == 0) {
                        return;
                    }
                    
                    // Добавляем или обновляем элемент
                    if (hash in items) {
                        items[hash].updateStats(result.get["Duration"].to!long);
                    } else {
                        items[hash] = LogLine(
                            hash,
                            result.get,
                            result.get["Duration"].to!long
                        );
                    }
                }
            } catch (Exception e) {
                logger.error("Error processing context: " ~ e.msg);
            }
        }
    }

    void writeResults() @trusted {
        synchronized(dataMutex) {
            logger.debug_("Writing results, items count: " ~ items.length.to!string);
            if (items.length == 0) {
                logger.debug_("No items to write");
                return;
            }
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

    private string generateGroupKey(string[string] fields) {
        string key = "";
        foreach (field; config.groupBy) {
            if (field in fields) {
                key ~= fields[field] ~ "|";
            }
        }
        if (key.length == 0) {
            logger.debug_("Empty key generated for fields: " ~ fields.to!string);
            return "";
        }
        return getFastHash(key);
    }

}