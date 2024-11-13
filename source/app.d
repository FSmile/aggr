module app;

import std.stdio;
import std.string;
import std.path;
import std.conv : to;

import config.settings : Config;
import core.interfaces : ILogger, ILogAnalyzer, IApplication;
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

import core.thread : Thread;
import core.time : msecs;
import std.process : thisProcessID;
import core.thread : Thread, ThreadID;
class Application : IApplication {
    private {
        DataProcessor processor;
        ILogger logger;
        ILogAnalyzer analyzer;
        bool hasError;
    }

    this(string[] args) {
        logger = new FileLogger("aggr.log");
        auto config = Config.fromArgs(args);
        
            // Логируем все параметры конфигурации
        logger.info("Configuration parameters:");
        logger.info("  Input file: " ~ config.inputPath);
        logger.info("  Output file: " ~ config.outputPath);
        logger.info("  Log file: " ~ config.logPath);
        logger.info("  Group by fields: " ~ config.groupBy.to!string);
        logger.info("  Aggregate field: " ~ config.aggregate);
        logger.info("  Duration field: " ~ config.durationField);
        logger.info("  Worker count: " ~ config.workerCount.to!string);
        logger.info("  Timeout: " ~ config.timeout.toString());
        logger.info("  Multiline fields: " ~ config.multilineFields.to!string);

        //logger.info("Group by: " ~ config.groupBy.to!string);
        logger.info("Starting initialization...");
        
        config.logger = logger;
        config.validate();
        
        logger.info("Creating analyzer...");
        auto factory = new AnalyzerFactory(logger);
        analyzer = factory.createAnalyzer(config);
        
        logger.info("Creating processor...");
        processor = new DataProcessor(config, analyzer, this);
        logger.info("Initialization completed");
    }

    bool run() {
        try {
            logger.info("Starting application...");
            logger.info("Process ID: " ~ thisProcessID().to!string);
            logger.info("Thread ID: " ~ Thread.getThis().id.to!string);
            processor.start();
            
            if (!processor.waitForCompletion()) {
                logger.error("Failed to complete processing");
                return false;
            }
            
            analyzer.writeResults();
            logger.info("Application finished");
            return true;
        } catch (Exception e) {
            logger.error("Application error", e);
            return false;
        } finally {
            processor.shutdown();
            analyzer.dispose();
            Thread.sleep(50.msecs);
        }
    }

    void reportError() {
        hasError = true;
    }
}

int main(string[] args) {
    try {
        auto version_ = VersionInfo.current();
        writeln(version_.toString());
        
        auto app = new Application(args);
        bool success = app.run();
        return success ? 0 : 1;
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

