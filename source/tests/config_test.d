module tests.config_test;

import std.exception : assertThrown;
import config.settings;
import utils.errors;

unittest {
    // Тест: минимальный набор параметров
    {
        string[] args = ["aggr", "input.log"];
        auto config = Config.fromArgs(args, true);
        assert(config.inputPath == "input.log");
        assert(config.outputPath == "output.csv");
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
        
        auto config = Config.fromArgs(args, true);
        assert(config.inputPath == "input.log");
        assert(config.outputPath == "custom.csv");
        assert(config.logPath == "custom.log");
        assert(config.groupBy == ["Context", "Time"]);
        assert(config.aggregate == "Count");
        assert(config.workerCount == 4);
    }

    // Тест: проверка очистки значений по умолчанию при указании пользовательских полей группировки
    {
        string[] args = [
            "aggr",
            "input.log",
            "--group-by=Usr"
        ];
        
        auto config = Config.fromArgs(args, true);
        assert(config.groupBy == ["Usr"]);
        assert(config.groupBy.length == 1, "Should only contain user-specified field");
    }
} 

 