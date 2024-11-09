module workers.processor;

import core.interfaces : ILogger;
import core.types;
import core.queue;
import utils.logging;

import std.parallelism : TaskPool, task;
import core.interfaces : ILogger, ILogAnalyzer;
import config.settings : Config;
import core.buffer : InputBuffer;
import vibe.core.core;
import std.stdio : stdin, File;

class DataProcessor {
    private {
        ILogger logger;
        shared Queue!string queue;
        TaskPool processors;
        ILogAnalyzer analyzer;
        InputBuffer buffer;
        string inputPath;
    }

    this(Config config, ILogAnalyzer analyzer) {
        this.logger = new FileLogger("processor.log");
        this.queue = cast(shared)new Queue!string(this.logger);
        this.processors = new TaskPool(config.workerCount);
        this.analyzer = analyzer;
        this.buffer = new InputBuffer();
        this.inputPath = config.inputPath;
    }

    private void processLines(string[] lines) @trusted {
        foreach (line; lines) {
            analyzer.processLine(line);
        }
    }

    private void processInput(File input) @trusted {
        try {
            char[] buf;
            while (input.readln(buf)) {
                string lineStr = buf.idup;
                if (!buffer.push(lineStr)) {
                    auto lines = buffer.flush();
                    processors.put(task(() @trusted => processLines(lines)));
                }
            }
            auto remainingLines = buffer.flush();
            if (remainingLines.length > 0) {
                processors.put(task(() @trusted => processLines(remainingLines)));
            }
        } catch (Exception e) {
            debug try { logger.error("Error processing input"); } catch (Exception) {}
        }
    }

    void start() {
        runTask(() nothrow @system {
            try {
                if (inputPath == "-") {
                    // Читаем из stdin если указан "-"
                    processInput(stdin);
                } else {
                    // Читаем из файла
                    auto file = File(inputPath, "r");
                    scope(exit) file.close();
                    processInput(file);
                }
            } catch (Exception) {
                // Игнорируем ошибки
            }
        });
        runEventLoop();
    }

    void shutdown() @trusted {
        processors.finish();
        analyzer.writeResults();
    }
} 

 