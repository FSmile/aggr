module config.settings;

import core.time : Duration;
import std.string : empty;
import utils.errors : ConfigException;
import std.conv : to;
import core.time : seconds;

struct Config {
    string inputPath;
    string outputPath;
    string logPath;
    int workerCount;
    Duration timeout;

    static Config fromArgs(string[] args) {
        Config config;
        
        // Простая реализация для примера
        if (args.length >= 4) {
            config.inputPath = args[1];
            config.outputPath = args[2];
            config.logPath = args[3];
            config.workerCount = args.length > 4 ? args[4].to!int : 1;
            config.timeout = 5.seconds;
        } else {
            throw new ConfigException("Not enough arguments");
        }
        
        config.validate();
        return config;
    }

    void validate() {
        // Валидация конфигурации
    }
} 

 