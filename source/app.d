module app;

import std.stdio;
import std.string;
import std.path;
import std.parallelism : TaskPool, task;

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
    private ILogAnalyzer analyzer;
    private TaskPool processors;

    this(string[] args) {
        config = Config.fromArgs(args);
        logger = new FileLogger(config.logPath);
        analyzer = new LogAnalyzer(new LogParser(), new CsvWriter(config.outputPath), logger);
        processors = new TaskPool(config.workerCount);
    }

    private void processLines(string[] lines, ILogAnalyzer analyzer) {
        foreach (line; lines) {
            analyzer.processLine(line);
        }
    }

    void run() {
        try {
            auto buffer = new InputBuffer();
            
            runTask(() {
                try {
                    foreach (const char[] line; stdin.byLine) {
                        string lineStr = cast(string)line.idup;
                        if (!buffer.push(lineStr)) {
                            auto lines = buffer.flush();
                            processors.put(task(() => processLines(lines, analyzer)));
                        }
                    }
                    auto remainingLines = buffer.flush();
                    if (remainingLines.length > 0) {
                        processors.put(task(() => processLines(remainingLines, analyzer)));
                    }
                } catch (Exception) {
                    // Обработка ошибок
                }
            });

            runEventLoop();
        } catch (Exception e) {
            logger.error("Application error", e);
        }
    }
}

void main(string[] args) {
    auto app = new Application(args);
    app.run();
}

