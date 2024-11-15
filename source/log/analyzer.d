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
import core.types : LogLine, LogStatistics, ThreadBuffer;

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

import core.thread : Thread;
import core.time : msecs;

class LogAnalyzer : ILogAnalyzer {

    private {
        ThreadBuffer[] threadBuffers;
        LogLine[string] globalBuffer;
        shared Mutex globalMutex;
        size_t workerCount;
        shared int lineCount = 0;
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
        contextMutex = new shared Mutex();
        
        workerCount = config.workerCount;
        threadBuffers = new ThreadBuffer[](workerCount);
        foreach(i; 0..workerCount) {
            threadBuffers[i] = ThreadBuffer(i, logger);
        }
        globalMutex = new shared Mutex();
        
        logger.info("Initialized LogAnalyzer with " ~ workerCount.to!string ~ " workers");
    }

    void processLine(string line, ulong workerId = 0) @trusted {
        import core.atomic : atomicOp;
        atomicOp!"+="(lineCount, 1);
        
        threadBuffers[workerId].startProcessing();
        logger.debug_("Worker " ~ workerId.to!string ~ " processing line");
        
        try {
            synchronized(contextMutex) {
                auto trimmedLine = line.strip();
                
                if (contextBuffer.length > 0) {
                    contextBuffer ~= line;
                    logger.debug_("Added line to context buffer: " ~ line);
                    
                    if (trimmedLine.endsWith("'") || trimmedLine.endsWith("'\n") || trimmedLine.endsWith("'\r\n")) {
                        auto fullContext = contextBuffer.join("\n");
                        logger.debug_("Processing complete context: " ~ fullContext);
                        processFullContext(fullContext, workerId);
                        contextBuffer.length = 0;
                        logger.debug_("Context buffer cleared");
                    }
                    return;
                }
                
                foreach (field; config.multilineFields) {
                    if (trimmedLine.indexOf(field ~ "='") != -1) {
                        contextBuffer = [line];
                        logger.debug_("Started multiline context: " ~ line);
                        return;
                    }
                }
                
                processFullContext(line, workerId);
            }
        } catch (Exception e) {
            logger.error("Error processing line: " ~ e.msg);
        }
    }

    private void processFullContext(string fullContext, size_t workerId) {
        try {
            logger.debug_("Fullcontext result: " ~ fullContext);
            auto result = parser.parse(fullContext);
            logger.debug_("Parse result: " ~ (result.isNull ? "null" : "not null"));
            
            if (!result.isNull) {
                logger.debug_("Fields: " ~ result.get.to!string);
                
                bool hasAllFields = true;
                foreach (field; config.groupBy) {
                    if (field !in result.get) {
                        hasAllFields = false;
                        logger.debug_("Missing field: " ~ field);
                        break;
                    }
                }
                
                if (!hasAllFields) {
                    logger.debug_("Skipping line - missing required fields");
                    return;
                }
                
                auto hash = generateGroupKey(result.get);
                logger.debug_("Generated hash: " ~ hash);
                
                if (hash.length > 0) {
                    auto line = LogLine(
                        hash,
                        result.get,
                        result.get["Duration"].to!long
                    );
                    threadBuffers[workerId].add(hash, line);
                    logger.debug_("Added to buffer: " ~ hash);
                }
            }
        } catch (Exception e) {
            logger.error("Error processing context: " ~ e.msg);
        } finally {
            threadBuffers[workerId].stopProcessing();
        }
    }

    void writeResults() @trusted {
       try {
        logger.info("Starting to write results"); 
        // Ждм завершения всех потоков и сливаем буферы
        foreach(i; 0..workerCount) {
             size_t attempts = 0;
            while(threadBuffers[i].isActive()) {
                Thread.sleep(50.msecs);
                attempts++;
                if (attempts > 100) {
                    logger.error("Thread " ~ i.to!string ~ " did not finish in 1000ms, skipping");
                    break;
                }
            }
            flushThreadBuffer(i);
        }

        // Записываем результаты батчами
        synchronized(globalMutex) {
            const size_t BATCH_SIZE = 1000;
            LogLine[] batch;
            size_t totalProcessed = 0;
            try {
            foreach(line; globalBuffer.byValue) {
                batch ~= line;
                if (batch.length >= BATCH_SIZE) {
                    writer.write(batch);
                    totalProcessed += batch.length;
                    logger.debug_("Wrote batch of " ~ batch.length.to!string ~ " lines. Total: " ~ totalProcessed.to!string);
                    batch = null;
                }
            }
            
            if (batch.length > 0) {
                writer.write(batch);
                totalProcessed += batch.length;
                logger.debug_("Wrote final batch of " ~ batch.length.to!string ~ " lines. Total: " ~ totalProcessed.to!string);
            }
            } catch (Exception e) {
                logger.error("Error writing results: " ~ e.msg);
            }
            logger.info("Completed writing results. Total lines: " ~ totalProcessed.to!string);
        }
        } catch (Exception e) {
            logger.error("Error writing results: " ~ e.msg);
        }
    }

    LogStatistics getStatistics() {
        synchronized(globalMutex) {
            return LogStatistics(
                atomicLoad(lineCount),
                globalBuffer.length,
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

    void flushThreadBuffer(size_t workerId) @trusted {
        auto lines = threadBuffers[workerId].flush();
        synchronized(globalMutex) {
            foreach(line; lines) {
                if (line.hash in globalBuffer) {
                    globalBuffer[line.hash].updateStats(line.duration);
                } else {
                    globalBuffer[line.hash] = line;
                }
            }
        }
    }

    void dispose() @trusted {
        if (writer !is null) {
            try {
                writer.close();
            } catch (Exception e) {
                logger.error("Error closing writer", e);
            }
        }
        
        foreach(ref buffer; threadBuffers) {
            buffer = ThreadBuffer.init;
        }
        
        globalBuffer.clear();
    }

}