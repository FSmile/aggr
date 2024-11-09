module factories.analyzer_factory;

import core.interfaces : ILogger;
import log.analyzer : LogAnalyzer;
import log.parser : LogParser, CsvWriter;

class AnalyzerFactory {
    private ILogger logger;

    this(ILogger logger) {
        this.logger = logger;
    }

    LogAnalyzer createAnalyzer(string outputPath, size_t workerCount = 1) {
        auto parser = new LogParser(logger);
        auto writer = new CsvWriter(outputPath);
        return new LogAnalyzer(parser, writer, logger, workerCount);
    }
}