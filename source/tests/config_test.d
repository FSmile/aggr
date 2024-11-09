module tests.config_test;

import std.exception : assertThrown;
import config.settings;
import utils.errors;

unittest {
    // Тест: минимальный набор параметров (только входной файл)
    {
        string[] args = ["aggr", "input.log"];
        auto config = Config.fromArgs(args);
        assert(config.inputPath == "input.log");
        assert(config.outputPath == "input.csv");
        assert(config.logPath == "aggr.log");
        assert(config.workerCount == 1);
    }

    // Тест: все параметры
    {
        string[] args = [
            "aggr",
            "input.log",
            "--output=custom.csv",
            "--log=custom.log",
            "--group-by=Context,Time",
            "--aggregate=Count",
            "--worker=4"
        ];
        
        auto config = Config.fromArgs(args);
        assert(config.inputPath == "input.log");
        assert(config.outputPath == "custom.csv");
        assert(config.logPath == "custom.log");
        assert(config.groupBy == ["Context", "Time"]);
        assert(config.aggregate == "Count");
        assert(config.workerCount == 4);
    }
} 

 