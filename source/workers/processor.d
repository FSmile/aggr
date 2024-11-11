module workers.processor;

import core.interfaces : ILogger, ILogAnalyzer, IApplication;
import core.types;
import core.queue;
import utils.logging;

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
        
        shared size_t activeTaskCount = 0;
        shared Mutex taskMutex;
        shared Condition taskCondition;
        Duration timeout = DEFAULT_TIMEOUT;
    }

    this(Config config, ILogAnalyzer analyzer, IApplication app = null) {
        this.analyzer = analyzer;
        this.processors = new TaskPool(config.workerCount);
        this.buffer = new InputBuffer();
        this.inputPath = config.inputPath;
        this.logger = config.logger;
        this.app = app;
        
        taskMutex = new shared Mutex();
        taskCondition = new shared Condition(taskMutex);
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
                logger.info("Reading from stdin");
                processInput(stdin);
            } else {
                logger.info("Reading from file: " ~ inputPath);
                auto file = File(inputPath, "r");
                scope(exit) file.close();
                processInput(file);
            }
            logger.info("Processing completed");
            analyzer.writeResults();
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
        try {
            if (processors !is null) {
                logger.debug_("Waiting for tasks completion. Active tasks: " ~ activeTaskCount.to!string);
                
                // Ждем завершения всех задач с таймаутом
                bool completed = true;
                synchronized(taskMutex) {
                    if (activeTaskCount > 0) {
                        completed = taskCondition.wait(timeout);
                    }
                }
                
                if (!completed) {
                    logger.error("Timeout waiting for tasks completion");
                    return false;
                }
                
                // Завершаем пул потоков
                processors.finish(true);
                logger.debug_("All tasks completed successfully");
                return true;
            }
            return true;
        } catch (Exception e) {
            logger.error("Error during wait for completion", e);
            return false;
        }
    }

    void shutdown() {
        try {
            if (processors !is null) {
                // Пытаемся завершить корректно
                if (!waitForCompletion()) {
                    logger.warning("Forcing shutdown with incomplete tasks");
                }
                
                // Останавливаем пул в любом случае
                processors.stop();
                processors = null;
                
                logger.debug_("Processor shutdown completed");
            }
        } catch (Exception e) {
            logger.error("Error during shutdown", e);
        }
    }
} 

 