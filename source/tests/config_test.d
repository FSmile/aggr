module tests.config_test;

import std.exception : assertThrown;
import config.settings;
import utils.errors;

unittest {
    // Тест: запуск без параметров
    {
        string[] args = ["app"];
        assertThrown!ConfigException(Config.fromArgs(args));
    }

    // Тест: неполный набор параметров
    {
        string[] args = ["app", "input.log", "output.csv"];
        assertThrown!ConfigException(Config.fromArgs(args));
    }

    // Тест: минимальный валидный набор параметров
    {
        string[] args = ["app", "input.log", "output.csv", "app.log"];
        auto config = Config.fromArgs(args);
        assert(config.inputPath == "input.log");
        assert(config.outputPath == "output.csv");
        assert(config.logPath == "app.log");
        assert(config.workerCount == 1); // дефолтное значение
    }

    // Тест: полный набор параметров
    {
        string[] args = ["app", "input.log", "output.csv", "app.log", "4"];
        auto config = Config.fromArgs(args);
        assert(config.inputPath == "input.log");
        assert(config.outputPath == "output.csv");
        assert(config.logPath == "app.log");
        assert(config.workerCount == 4);
    }

    // Тест: некорректное значение workerCount
    {
        string[] args = ["app", "input.log", "output.csv", "app.log", "invalid"];
        assertThrown!ConfigException(Config.fromArgs(args));
    }
} 

 