module app;

import std.stdio;
import std.string;
import std.path;
import std.conv : to;

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
//import vibe.core.core;
//import vibe.core.concurrency;
import std.stdio : stdin;

import core.buffer : InputBuffer;
import std.parallelism : TaskPool, task;

import factories.analyzer_factory;

import version_info : VersionInfo;

class Application {
    private ILogger logger;
    private Config config;
    private DataProcessor processor;

    this(string[] args) {
        config = Config.fromArgs(args);
        logger = new FileLogger(config.logPath);
        logger.info("Group by: " ~ config.groupBy.to!string);
        logger.info("Starting initialization...");
        
        config.logger = logger;
        config.validate();
        
        logger.info("Creating analyzer...");
        auto factory = new AnalyzerFactory(logger);
        auto analyzer = factory.createAnalyzer(config);
        
        logger.info("Creating processor...");
        processor = new DataProcessor(config, analyzer);
        logger.info("Initialization completed");
    }

    void run() {
        try {
            logger.info("Starting application...");
            processor.start();
            processor.waitForCompletion();
            logger.info("Application finished");
        } catch (Exception e) {
            logger.error("Application error", e);
        } finally {
            processor.shutdown();
        }
    }
}

int main(string[] args) {
    try {
        auto version_ = VersionInfo.current();
        writeln(version_.toString());
        
        auto app = new Application(args);
        app.run();
        return 0;
    } catch (ConfigException e) {
        writeln("Ошибка конфигурации: ", e.msg);
        stderr.writeln("Configuration error: ", e.msg);
        writeln("Usage: aggr [options] input_file");
        writeln("Options:");
        writeln("  --group-by|-g    Fields to group by (default: Context)");
        writeln("  --aggregate|-a   Field to aggregate (default: Duration)");
        writeln("  --worker|-w      Number of worker threads (default: 1)");
        writeln("  --output|-o      Output file path (default: output.csv)");
        writeln("  --log|-l         Log file path (default: aggr.log)");
        return 1;
    } catch (Exception e) {
        writeln("Критическая ошибка: ", e.msg);
        debug writeln(e.toString());
        return 1;
    }
}

