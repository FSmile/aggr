module log.parser;

import std.stdio : File;
import std.typecons : Nullable;
import std.algorithm : map, sum, canFind;
import std.array : array;
import std.string : replace, indexOf, strip, startsWith, endsWith;
import core.sync.mutex : Mutex;
import core.interfaces : IResultWriter, ILogger, ILogParser;
import core.types : LogLine;
import std.regex;
import std.array : split;
import std.conv : to;
import std.encoding : getBOM, BOM, BOMSeq;
import std.algorithm : canFind,startsWith, endsWith;
import config.settings : Config;

class LogParser : ILogParser {
    private ILogger logger;
    private string[] groupFields;
    private string[] multilineFields;

    this(ILogger logger, Config config) {
        this.logger = logger;
        this.groupFields = config.groupBy;
        this.multilineFields = config.multilineFields;
    }

    private string removeBOM(string input) {
        // UTF-8 BOM sequence
        immutable ubyte[] UTF8_BOM = [0xEF, 0xBB, 0xBF];
        
        // Проверяем, начинается ли строка с UTF-8 BOM
        if (input.length >= 3 && 
            (cast(const(ubyte)[])input)[0..3] == UTF8_BOM) {
            return input[3..$];
        }
        return input;
    }

    Nullable!(string[string]) parse(string line) {
        string[string] result;
        
        // Удаляем BOM если он есть
        auto originalLine = line;
        line = removeBOM(line);
        if (line != originalLine) {
            logger.debug_("BOM removed from line");
        }
        
        logger.debug_("Parsing line: " ~ line);
        
        // Парсим Duration
        auto parts = line.split(",");
        if (parts.length >= 1) {
            auto durationStr = parts[0].strip();
            logger.debug_("Duration string: " ~ durationStr);
            
            // Поддержка обоих форматов: "time-duration" и просто "duration"
            if (durationStr.indexOf("-") != -1) {
                auto durationParts = durationStr.split("-");
                if (durationParts.length == 2) {
                    result["Duration"] = durationParts[1];
                    logger.debug_("Parsed Duration from time-duration: " ~ durationParts[1]);
                }
            } else {
                result["Duration"] = durationStr;
                logger.debug_("Parsed Duration direct: " ~ durationStr);
            }
        }

        // Парсим обычные поля
        foreach (part; parts[1..$]) {
            auto kv = part.strip().split("=");
            if (kv.length == 2) {
                auto fieldName = kv[0].strip;
                auto fieldValue = kv[1].strip;
                
                // Пропускаем пустые значения
                if (fieldValue.length == 0) {
                    logger.debug_("Skipping empty value for field: " ~ fieldName);
                    continue;
                }
                
                logger.debug_("Found field: " ~ fieldName ~ " = " ~ fieldValue);
                
                if (groupFields.canFind(fieldName)) {
                    result[fieldName] = fieldValue;
                    logger.debug_("Added field to result: " ~ fieldName);
                }
            }
        }

        // Отдельно обрабатываем многострочный контекст
        if (line.indexOf("Context='") != -1 && groupFields.canFind("Context")) {
            auto contextStart = line.indexOf("Context='") + "Context='".length;
            result["Context"] = parseMultilineValue(line[contextStart..$]);
        }

        if ("Duration" !in result) {
            return Nullable!(string[string]).init;
        }

        if (result.length > 0) {
            foreach (key, value; result) {
                logger.debug_("Parsed field: " ~ key ~ " = " ~ value);
            }
        }

        return Nullable!(string[string])(result);
    }

    private string parseMultilineValue(string value) {
        // Удаляем начальные и конечные кавычки
        if (value.startsWith("'")) {
            value = value[1..$];
        }
        if (value.endsWith("'")) {
            value = value[0..$-1];
        }
        return value;
    }
}

class CsvWriter : IResultWriter {
    private File outputFile;
    private shared Mutex mutex;
    private Config config;
    private ILogger logger;

    this(string path, Config config) {
        outputFile = File(path, "w");
        mutex = new shared Mutex();
        this.config = config;
        this.logger = config.logger;
    }

    void write(LogLine[] results) {
        synchronized(mutex) {
            scope(exit) outputFile.flush();
            
            if (results.length == 0) {
                logger.debug_("No results to write");
                return;
            }
            
            logger.debug_("Writing " ~ results.length.to!string ~ " results to CSV");
            
            // Формируем заголовок динамически
            string header = "Total(ms),Avg(ms),Max(ms),Count";
            foreach(field; config.groupBy) {
                header ~= "," ~ field;
            }
            outputFile.writeln(header);
            logger.debug_("Wrote header: " ~ header);
            
            // Записываем данные
            foreach(item; results) {
                logger.debug_("Writing item with fields: " ~ item.fields.keys.to!string);
                // Записываем статистику
                outputFile.writef("%d,%d,%d,%d",
                    item.sum / 1000,
                    item.avg() / 1000,
                    item.max / 1000,
                    item.count
                );
                
                // Записываем значения полей группировки
                foreach(field; config.groupBy) {
                    auto value = field in item.fields ? 
                        item.fields[field] : "";
                    
                    // Для многострочных полей берем только последнюю строку
                    if (config.multilineFields.canFind(field) && value.length > 0) {
                        auto lines = value.split("\n");
                        if (lines.length > 0) {
                            value = lines[$-1].strip();
                        }
                    }
                    
                    outputFile.writef(",\"%s\"",
                        value.replace("\"", "\"\"")
                             .strip()
                    );
                }
                outputFile.writeln();
            }
            
            // Статистика
            outputFile.writeln();
            outputFile.writefln("# Total entries: %d", results.length);
            outputFile.writefln("# Total lines processed: %d", 
                results.map!(r => r.count).sum());
        }
    }

    void close() {
        synchronized(mutex) {
            if (outputFile.isOpen) {
                outputFile.close();
            }
        }
    }
}

