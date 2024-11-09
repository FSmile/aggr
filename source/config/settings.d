module config.settings;
import std.conv : ConvException;
import core.time : Duration, seconds;
import std.string : empty;
import utils.errors : ConfigException;
import std.conv : to;
import std.getopt;
import std.path : setExtension, baseName;

struct Config {
    string inputPath;
    string outputPath;
    string logPath;
    string[] groupBy = ["Context"];     
    string aggregate = "Duration";       
    int workerCount = 1;                
    Duration timeout = 5.seconds;

    static Config fromArgs(string[] args) {
        Config config;
        
        try {
            auto helpInformation = getopt(
                args,
                "group-by|g",  "Fields to group by (default: Context)", &config.groupBy,
                "aggregate|a", "Field to aggregate (default: Duration)", &config.aggregate,
                "worker|w",    "Number of worker threads (default: 1)", &config.workerCount,
                "output|o", "Output file path (default: input file name with .csv extension)", &config.outputPath,
                "log|l", "Log file path (default: aggr.log)", &config.logPath
            );

            if (helpInformation.helpWanted || args.length < 2) {
                defaultGetoptPrinter(
                    "Usage: aggr [options] input_file\n\nOptions:",
                    helpInformation.options
                );
                throw new ConfigException("Help requested");
            }

            config.inputPath = args[1];
            
            // Устанавливаем значения по умолчанию если не заданы
            if (config.outputPath.empty) {
                config.outputPath = config.inputPath.setExtension("csv");
            }
            if (config.logPath.empty) {
                config.logPath = "aggr.log";
            }
            
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
        if (workerCount < 1 || workerCount > 32) {
            throw new ConfigException("Worker count must be between 1 and 32");
        }
        if (groupBy.length == 0) {
            throw new ConfigException("At least one group-by field must be specified");
        }
    }
} 

 