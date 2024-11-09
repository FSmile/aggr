module app;

import std.stdio;
import std.string;
import std.path;
import std.conv : ConvException;

import config.settings : Config;
import core.interfaces : ILogger, ILogAnalyzer;
import utils.errors : ConfigException;

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
            logger,
            config.workerCount
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
    try {
        auto app = new Application(args);
        app.run();
    } catch (ConfigException e) {
<<<<<<< Updated upstream
        writeln("Ошибка конфигурации: ", e.msg);
        writeln("Использование: app input.log output.csv app.log [worker_count]");
=======
        stderr.writeln("Configuration error: ", e.msg);
        writeln("Использование: app input.log output.csv aggr.log [worker_count]");
>>>>>>> Stashed changes
        writeln("  input.log    - входной файл логов");
        writeln("  output.csv   - выходной файл статистики");
        writeln("  aggr.log     - файл логов приложения");
        writeln("  worker_count - количество потоков (по умолчанию 1)");
        return;
    } catch (Exception e) {
        writeln("Критическая ошибка: ", e.msg);
        debug writeln(e.toString());
        return;
    }
}

