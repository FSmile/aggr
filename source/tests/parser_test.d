module tests.parser_test;

import std.typecons : Nullable;
import std.stdio : File;
import core.interfaces : ILogger;
import core.types : LogLevel;
import log.parser : LogParser;
import config.settings : Config;
import std.string;

// Mock-объект для логгера
class TestLogger : ILogger {
    void debug_(string msg) {}
    void info(string msg) {}
    void warning(string msg) {}
    void error(string msg, Exception e = null) {}
    void log(LogLevel level, string message, string file = __FILE__, int line = __LINE__) {}
}

unittest {
    // Подготовка
    auto logger = new TestLogger();
    
    // Создаем два набора тестов с разными конфигурациями
    {
        auto config = Config();
        config.groupBy = ["Usr", "RowsAffected"];
        config.multilineFields = [];
        auto parser = new LogParser(logger, config);

        // Тест 1: Парсинг Duration с временной меткой
        {
            auto result = parser.parse("40:33.299009-1515852,DBPOSTGRS,6,Usr=EventIntegrationWritingToKafka,RowsAffected=0");
            assert(!result.isNull);
            assert(result.get["Duration"] == "1515852");
            assert(result.get["Usr"] == "EventIntegrationWritingToKafka");
            assert(result.get["RowsAffected"] == "0");
        }

        // Тест 2: Парсинг Duration без временной метки
        {
            auto result = parser.parse("1515852,DBPOSTGRS,6,Usr=EventIntegrationWritingToKafka,RowsAffected=0");
            assert(!result.isNull);
            assert(result.get["Duration"] == "1515852");
        }

        // Тест 3: Парсинг с BOM
        {
            ubyte[] bom = [0xEF, 0xBB, 0xBF];
            string line = cast(string)bom ~ "40:33.299009-1515852,Usr=Test";
            auto result = parser.parse(line);
            assert(!result.isNull);
            assert(result.get["Duration"] == "1515852");
            assert(result.get["Usr"] == "Test");
        }

        // Тест 4: Парсинг полей с кавычками
        {
            auto result = parser.parse("1515852,Usr='TestUser',RowsAffected=0");
            assert(!result.isNull);
            assert(result.get["Usr"] == "TestUser");
        }
    }

    // Новый блок тестов для многострочных полей
    {
        auto config = Config();
        config.groupBy = ["Context"];
        config.multilineFields = ["Context"];
        auto parser = new LogParser(logger, config);

        // Тест 5: Парсинг многострочного Context из 1С
        {
            auto result = parser.parse("40:33.299009-1515852,DBPOSTGRS,6,Context='ОбщийМодуль.Сам_APIРегламентныеЗаданияСервер.Модуль : 161 : РегистрыСведений.Сам_APIПризнакиЗаданийГруппСобытий.УстановитьСнятьПризнак(ЗаданиеОтправкиСообщения, \"\", Ложь);\nРегистрСведений.Сам_APIПризнакиЗаданийГруппСобытий.МодульМенеджера : 14 : МенеджерЗаписи.Удалить();'");
            assert(!result.isNull);
            assert(result.get["Duration"] == "1515852");
            assert(result.get["Context"].indexOf("ОбщийМодуль") != -1);
        }

        // Тест 6: Парсинг пустого многострочного Context
        {
            auto result = parser.parse("1515852,DBPOSTGRS,6,Context=''");
            assert(!result.isNull);
            assert(result.get["Duration"] == "1515852");
            assert(result.get["Context"] == "");
        }
    }
}

