module workers.processor;

import core.interfaces : ILogger;
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

class DataProcessor {
    private {
        ILogAnalyzer analyzer;
        TaskPool processors;
        InputBuffer buffer;
        string inputPath;
        ILogger logger;
    }

    this(Config config, ILogAnalyzer analyzer) {
        this.analyzer = analyzer;
        this.processors = new TaskPool(config.workerCount);
        this.buffer = new InputBuffer();
        this.inputPath = config.inputPath;
        this.logger = config.logger;
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
        }
    }

    private void processInput(File input) {
        enum BATCH_SIZE = 1000;
        string[] batch;
        batch.reserve(BATCH_SIZE);
        
        char[] buf;
        while (input.readln(buf)) {
            batch ~= buf.idup;
            if (batch.length >= BATCH_SIZE) {
                auto lines = batch.dup;
                processors.put(task(() {
                    foreach(line; lines) {
                        try {
                            analyzer.processLine(line);
                        } catch (Exception e) {
                            logger.error("Error processing line batch", e);
                        }
                    }
                }));
                batch.length = 0;
            }
        }
        
        if (batch.length > 0) {
            processors.put(task(() {
                foreach(line; batch) {
                    try {
                        analyzer.processLine(line);
                    } catch (Exception e) {
                        logger.error("Error processing line batch", e);
                    }
                }
            }));
        }
        
        processors.finish(true);
    }

    void shutdown() {
        try {
            processors.finish(true);
        } finally {
            processors.stop();
        }
    }
} 

 