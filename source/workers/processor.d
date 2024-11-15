module workers.processor;

import core.interfaces : ILogger, ILogAnalyzer, IApplication;
import core.types;
import core.queue;
import utils.logging;
import std.file : exists;

import std.parallelism : TaskPool, task;
import core.interfaces : ILogger, ILogAnalyzer;
import config.settings : Config;
import core.buffer : InputBuffer;
import std.stdio : stdin, File;
import std.array : array;
import core.time : Duration;
import std.conv : to;
import core.thread : Thread;
import core.time : msecs;
import core.sync.mutex : Mutex;
import core.sync.condition : Condition;
import core.atomic : atomicOp;
import core.time : seconds;

import workers.thread_pool;
import config.settings : Config;
import std.array;
class DataProcessor {
    private enum BATCH_SIZE = 10_000;
    private enum DEFAULT_TIMEOUT = 5.seconds;

    private {
        ILogAnalyzer analyzer;
        InputBuffer buffer;
        string inputPath;
        ILogger logger;
        IApplication app;
        Config config;
        Duration timeout = DEFAULT_TIMEOUT;

        ThreadPool threadPool;
        Mutex mutex;
    }

    this(Config config, ILogAnalyzer analyzer, IApplication app = null) {
        this.config = config;
        this.analyzer = analyzer;
        this.buffer = new InputBuffer();
        this.inputPath = config.inputPath;
        this.logger = config.logger;
        this.app = app;
        
        threadPool = new ThreadPool(config.workerCount, analyzer);
        mutex = new Mutex();
    }

    void start() {
        try {
            logger.info("Starting processing...");
            if (inputPath == "-") {
                processInput(stdin);
            } else {
                logger.info("Reading from file: " ~ inputPath);
                if (!exists(inputPath)) {
                    logger.error("File does not exist: " ~ inputPath);
                    throw new Exception("Input file not found: " ~ inputPath);
                }
                auto file = File(inputPath, "r");
                scope(exit) file.close();
                processInput(file);
            }
            logger.info("Processing completed");
            
            // Ждем завершения всех задач
            if (!waitForCompletion()) {
                logger.error("Failed to complete all tasks");
                return;
            }   
        } catch (Exception e) {
            logger.error("Processing failed", e);
            if (app !is null) {
                app.reportError();
            }
        }
    }

    private void processInput(File input) {
        try {
            string[] batch;
            size_t totalLines;

            logger.info("Starting to read input file...");
            
            foreach (line; input.byLine) {
                batch ~= line.idup;
                totalLines++;
                
                if (batch.length >= BATCH_SIZE) {
                    processBatch(batch);
                    batch.length = 0;
                }
            }
            
            if (batch.length > 0) {
                logger.debug_("Processing final batch of " ~ batch.length.to!string ~ " lines");
                processBatch(batch);
            }
            
            logger.info("Finished reading input file. Total lines read: " ~ totalLines.to!string);
        } catch (Exception e) {
            logger.error("Error in processInput", e);
            if (app !is null) app.reportError();
            throw e;
        }
    }

    private void processBatch(string[] lines) {
        DataBuffer[] records;
        size_t startIdx = 0;
        
        logger.debug_("Processing batch of " ~ lines.length.to!string ~ " lines");
        
        // Собираем записи
        for(size_t i = 0; i < lines.length; i++) {
            if (isNewRecord(lines[i])) {
                if (i > startIdx) {
                    records ~= DataBuffer(lines[startIdx..i]);
                    logger.debug_("Found record from " ~ startIdx.to!string ~ " to " ~ i.to!string);
                }
                startIdx = i;
            }
        }
        
        // Добавляем последнюю запись
        if (startIdx < lines.length) {
            records ~= DataBuffer(lines[startIdx..lines.length]);
            logger.debug_("Found final record from " ~ startIdx.to!string);
        }
        
        logger.debug_("Found " ~ records.length.to!string ~ " records in batch");
        
        // Отправляем записи в потоки
        foreach(i, record; records) {
            string fullRecord = record.lines.join("\n");
            logger.debug_("Sending record to thread " ~ (i % config.workerCount).to!string);
            threadPool.addTask(() {
                analyzer.processLine(fullRecord, i % config.workerCount);
            }, i % config.workerCount);
        }
        
        threadPool.waitForCompletion(1.seconds);
    }

    private bool isNewRecord(string line) {
        import std.regex;
        return !line.matchFirst(r"^\d{2}:\d{2}\.\d{6}").empty;
    }

    bool waitForCompletion() {
        return threadPool.waitForCompletion(timeout);
    }

    void shutdown() {
        try {
            if (!waitForCompletion()) {
                logger.warning("Forced shutdown with incomplete tasks");
            }
            
            threadPool.shutdown();

            if (analyzer !is null) {
                analyzer.dispose();
            }
            
            logger.debug_("Processor shutdown completed");
        } catch (Exception e) {
            logger.error("Error during shutdown", e);
        }
    }
} 

 