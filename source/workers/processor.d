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
import std.conv : to;
import core.thread : Thread;
import core.time : msecs;

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
        try {
            if (input.size() == 0) {
                logger.error("Input file is empty or does not exist");
                return;
            }

            logger.info("Starting to read input file...");
            enum BATCH_SIZE = 1000;
            string[] batch;
            batch.reserve(BATCH_SIZE);
            
            char[] buf;
            size_t totalLines = 0;
            
            while (input.readln(buf)) {
                totalLines++;
                batch ~= buf.idup;
                if (batch.length >= BATCH_SIZE) {
                    logger.debug_("Processing batch of " ~ batch.length.to!string ~ " lines");
                    auto lines = batch.dup;
                    processors.put(task(() {
                        foreach(line; lines) {
                            try {
                                analyzer.processLine(line);
                            } catch (Exception e) {
                                logger.error("Error processing line: " ~ line, e);
                            }
                        }
                    }));
                    batch.length = 0;
                }
            }
            
            if (batch.length > 0) {
                logger.debug_("Processing final batch of " ~ batch.length.to!string ~ " lines");
                processors.put(task(() {
                    foreach(line; batch) {
                        try {
                            analyzer.processLine(line);
                        } catch (Exception e) {
                            logger.error("Error processing line: " ~ line, e);
                        }
                    }
                }));
            }
            
            logger.info("Finished reading input file. Total lines read: " ~ totalLines.to!string);
            processors.finish(true);
        } catch (Exception e) {
            logger.error("Error in processInput", e);
            throw e;
        }
    }

    void shutdown() {
        try {
            if (processors !is null) {
                processors.finish(true);
                processors.stop();
            }
        } catch (Exception e) {
            logger.error("Error during shutdown", e);
        }
    }

    void waitForCompletion() {
        if (processors !is null) {
            processors.finish(true);
        }
    }
} 

 