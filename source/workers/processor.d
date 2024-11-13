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

class DataProcessor {
    private enum BATCH_SIZE = 10_000;
    private enum DEFAULT_TIMEOUT = 5.seconds;

    private {
        ILogAnalyzer analyzer;
        TaskPool processors;
        InputBuffer buffer;
        string inputPath;
        ILogger logger;
        IApplication app;
        Config config;
        shared size_t activeTaskCount = 0;
        shared Mutex taskMutex;
        shared Condition taskCondition;
        Duration timeout = DEFAULT_TIMEOUT;

        ThreadPool threadPool;
    }

    this(Config config, ILogAnalyzer analyzer, IApplication app = null) {
        this.config = config;
        this.analyzer = analyzer;
        this.processors = new TaskPool(config.workerCount);
        this.buffer = new InputBuffer();
        this.inputPath = config.inputPath;
        this.logger = config.logger;
        this.app = app;
        
        taskMutex = new shared Mutex();
        taskCondition = new shared Condition(taskMutex);

        threadPool = new ThreadPool(config.workerCount, analyzer);
    }

    private void incrementTaskCount() {
        synchronized(taskMutex) {
            atomicOp!"+="(activeTaskCount, 1);
        }
    }

    private void decrementTaskCount() {
        synchronized(taskMutex) {
            atomicOp!"-="(activeTaskCount, 1);
            if (activeTaskCount == 0) {
                taskCondition.notify();
            }
        }
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
        incrementTaskCount();
        processors.put(task(() {
            try {
                foreach(line; lines) {
                    try {
                        analyzer.processLine(line);
                    } catch (Exception e) {
                        logger.error("Error processing line: " ~ line, e);
                        if (app !is null) app.reportError();
                    }
                }
            } finally {
                decrementTaskCount();
            }
        }));
    }

    bool waitForCompletion() {
        logger.debug_("Waiting for tasks completion. Active tasks: " ~ activeTaskCount.to!string);
        
        size_t attempts = 0;
        const size_t MAX_ATTEMPTS = 100; // 1 секунда максимум
        
        while(activeTaskCount > 0 && attempts < MAX_ATTEMPTS) {
            Thread.sleep(10.msecs);
            attempts++;
        }
        
        if (attempts >= MAX_ATTEMPTS) {
            logger.error("Timeout waiting for tasks completion");
            return false;
        }
        
        logger.debug_("All tasks completed successfully");
        return true;
    }

    void shutdown() {
        try {
            if (!waitForCompletion()) {
                logger.warning("Forced shutdown with incomplete tasks");
            }
            
            if (analyzer !is null) {
                analyzer.dispose();
            }
            
            logger.debug_("Processor shutdown completed");
        } catch (Exception e) {
            logger.error("Error during shutdown", e);
        }
    }

    void processBuffer(DataBuffer buffer) {
        foreach(i, line; buffer.lines[buffer.startIdx..buffer.endIdx]) {
            threadPool.addTask(() {
                analyzer.processLine(line, i % config.workerCount);
            }, i % config.workerCount);
        }
    }
} 

 