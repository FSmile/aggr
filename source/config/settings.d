module config.settings;

import core.time : Duration, seconds;
import std.string : empty;
import utils.errors : ConfigException;
import std.conv : to;
import std.getopt;
import std.conv : ConvException;

struct Config {
    string inputPath;
    string outputPath;
    string logPath;
    string[] groupBy = ["Context"];     // поля для группировки
    string aggregate = "Duration";       // поле для агрегации
    int workerCount = 1;                // количество потоков
    Duration timeout = 5.seconds;

    static Config fromArgs(string[] args) {
        Config config;
        
        try {
            auto helpInformation = getopt(
                args,
                "group-by|g",  "Fields to group by (default: Context)", &config.groupBy,
                "aggregate|a", "Field to aggregate (default: Duration)", &config.aggregate,
                "worker|w",    "Number of worker threads (default: 1)", &config.workerCount
            );

            if (helpInformation.helpWanted) {
                defaultGetoptPrinter(
                    "Usage: app [options] input.log output.csv app.log\n\nOptions:",
                    helpInformation.options
                );
                throw new ConfigException("Help requested");
            }

            // Проверяем позиционные аргументы
            if (args.length < 4) {
                throw new ConfigException("Not enough arguments");
            }

            config.inputPath = args[1];
            config.outputPath = args[2];
            config.logPath = args[3];
            
            config.validate();
            
        } catch (GetOptException e) {
            throw new ConfigException("Invalid command line arguments: " ~ e.msg);
        } catch (ConvException e) {
            throw new ConfigException("Invalid worker count value");
        }
        
        return config;
    }

    void validate() {
        if (inputPath.empty) {
            throw new ConfigException("Input file not specified");
        }
        if (outputPath.empty) {
            throw new ConfigException("Output file not specified");
        }
        if (logPath.empty) {
            throw new ConfigException("Log file not specified");
        }
        if (workerCount < 1 || workerCount > 32) {
            throw new ConfigException("Worker count must be between 1 and 32");
        }
        if (groupBy.length == 0) {
            throw new ConfigException("At least one group-by field must be specified");
        }
    }
} 

 