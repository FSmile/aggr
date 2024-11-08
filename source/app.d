module app;

import std.stdio;
import std.string;
import std.path;

import config.settings : Config;
import core.interfaces : ILogger, ILogAnalyzer;

import log.analyzer : LogAnalyzer;
import workers.processor : DataProcessor;
import utils.logging : FileLogger;
import metrics.collector : MetricsCollector;
import log.parser : LogParser, CsvWriter;
import utils.errors : ApplicationException;
import core.queue : Queue;
import vibe.core.core;
import vibe.core.concurrency;
import std.stdio : stdin;

import core.buffer : InputBuffer;
import std.parallelism : TaskPool, task;

class Application {
    private ILogger logger;
    private Config config;
    private DataProcessor processor;

    this(string[] args) {
        config = Config.fromArgs(args);
        logger = new FileLogger(config.logPath);
        auto analyzer = new LogAnalyzer(
            new LogParser(), 
            new CsvWriter(config.outputPath), 
            logger
        );
        processor = new DataProcessor(config, analyzer);
    }

    void run() {
        try {
            processor.start();
        } catch (Exception e) {
            logger.error("Application error", e);
        } finally {
            processor.shutdown();
        }
    }
}

void main(string[] args) {
    auto app = new Application(args);
    app.run();
}

