module config.settings;
import std.conv : ConvException;
import core.time : Duration, seconds;
import std.string : empty;
import utils.errors : ConfigException;
import std.conv : to;
import std.getopt;
import std.path : setExtension, baseName;
import std.file : exists;
import std.format : format;
import core.interfaces : ILogger;

import std.algorithm : canFind;
import std.array : split;
struct Config {
    string inputPath;
    string outputPath = "output.csv";
    string logPath = "aggr.log";
    string[] groupBy = ["Context"];     
    string aggregate = "Duration";
    string durationField = "Duration";         
    int workerCount = 1;                
    Duration timeout = 5.seconds;
    ILogger logger;
    string[] multilineFields = ["Context"];             

    static Config fromArgs(string[] args, bool skipValidation = false) {
        Config config;
        
        try {
            config.groupBy = [];
            config.multilineFields = []; // Очищаем значения по умолчанию
            
            auto helpInformation = getopt(
                args,
                "group-by|g",  "Fields to group by (default: Context)", (string opt, string value) {
                    config.groupBy = value.split(",");
                    // Если Context в списке группировки, добавляем его в многострочные поля
                    if (config.groupBy.canFind("Context")) {
                        config.multilineFields ~= "Context";
                    }
                },
                "aggregate|a", "Field to aggregate (default: Duration)", &config.aggregate,
                "worker|w",    "Number of worker threads (default: 1)", &config.workerCount,
                "output|o", "Output file path (default: output.csv)", &config.outputPath,
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
            if (config.groupBy.length == 0) {
                config.groupBy = ["Context"];
                config.multilineFields = ["Context"];  // Добавляем Context в multiline только если он используется по умолчанию
            }
            if (config.outputPath.empty) {
                config.outputPath = "output.csv";
            }
            if (config.logPath.empty) {
                config.logPath = "aggr.log";
            }
            
            if (!skipValidation) {
                config.validate();
            }
            
        } catch (GetOptException e) {
            throw new ConfigException("Invalid command line arguments: " ~ e.msg);
        } catch (ConvException e) {
            throw new ConfigException("Invalid worker count value");
        }
        
        return config;
    }

    void validate() {
        if (inputPath.empty || (inputPath != "-" && !exists(inputPath))) {
            throw new ConfigException("Input file '%s' does not exist".format(inputPath));
        }
        if (workerCount < 1 || workerCount > 32) {
            throw new ConfigException("Worker count must be between 1 and 32, got: %d"
                .format(workerCount));
        }
        foreach (field; multilineFields) {
            if (!groupBy.canFind(field)) {
                throw new ConfigException("Multiline field '" ~ field ~ "' must be included in group-by fields");
            }
        }
    }
} 

 