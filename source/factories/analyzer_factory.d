module factories.analyzer_factory;

import core.interfaces : ILogAnalyzer;
import config.settings : Config;
import log.analyzer : LogAnalyzer;
import log.parser : LogParser, CsvWriter;
import utils.logging : FileLogger;

class AnalyzerFactory {
    static ILogAnalyzer create(Config config) {
        auto logger = new FileLogger(config.logPath);
        auto parser = new LogParser();
        auto writer = new CsvWriter(config.outputPath);
        return new LogAnalyzer(parser, writer, logger);
    }
}