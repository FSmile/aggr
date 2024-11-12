module factories.analyzer_factory;

import core.interfaces : ILogger;
import log.analyzer : LogAnalyzer;
import log.parser : LogParser, CsvWriter;
import config.settings  : Config;

class AnalyzerFactory {
    private ILogger logger;

    this(ILogger logger) {
        this.logger = logger;
    }

    LogAnalyzer createAnalyzer(Config config) {
        auto parser = new LogParser(logger, config);
        auto writer = new CsvWriter(config.outputPath, config);
        return new LogAnalyzer(parser, writer, logger, config);
    }
}