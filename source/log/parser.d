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
import std.string;

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
        line = removeBOM(line);
        
        // Парсим Duration (всегда первое поле до запятой)
        auto durationEnd = line.indexOf(",");
        if (durationEnd == -1) return Nullable!(string[string]).init;
        
        auto durationStr = line[0..durationEnd].strip();
        if (durationStr.indexOf("-") != -1) {
            auto durationParts = durationStr.split("-");
            if (durationParts.length == 2) {
                result["Duration"] = durationParts[1];
            }
        } else {
            result["Duration"] = durationStr;
        }

        // Ищем начало многострочного поля
        foreach (field; multilineFields) {
            auto fieldStart = line.indexOf(field ~ "='");
            if (fieldStart != -1) {
                // Находим конец многострочного значения (последняя кавычка в строке)
                auto valueStart = fieldStart + field.length + 2; // +2 для "='"
                auto valueEnd = line.lastIndexOf("'");
                
                if (valueEnd > valueStart) {
                    string value = line[valueStart..valueEnd];
                    result[field] = parseMultilineValue(value);               
                }
            }
        }

        // Парсим обычные поля только если не нашли многострочное
        foreach (part; line[durationEnd + 1..$].split(",")) {
            auto kv = part.strip().split("=");
            if (kv.length == 2 && groupFields.canFind(kv[0].strip)) {
                auto fieldName = kv[0].strip;
                auto fieldValue = kv[1].strip;
                
                if (fieldValue.startsWith("'") && fieldValue.endsWith("'")) {
                    fieldValue = fieldValue[1..$-1];
                }
                
                result[fieldName] = fieldValue;
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
        // Заменяем двойные кавычки на одинарные
        value = value.replace("''", "'");
        return value;
    }
}

class CsvWriter : IResultWriter {
    private File outputFile;
    private shared Mutex mutex;
    private Config config;
    private ILogger logger;
    private bool isInitialized;
    private bool headerWritten;

    this(string path, Config config) {
        outputFile = File(path, "w");
        mutex = new shared Mutex();
        this.config = config;
        this.logger = config.logger;
        this.isInitialized = true;
        this.headerWritten = false;
        
        // Записываем заголовок при создании
        writeHeader();
    }

    private void writeHeader() {
        if (!headerWritten) {
            string header = "Total(ms),Avg(ms),Max(ms),Count";
            foreach(field; config.groupBy) {
                header ~= "," ~ field;
            }
            outputFile.writeln(header);
            headerWritten = true;
            logger.debug_("Wrote header: " ~ header);
        }
    }

    void write(LogLine[] results) {
        synchronized(mutex) {
            if (!isInitialized) {
                logger.error("Attempt to write to closed file");
                return;
            }
            
            scope(exit) outputFile.flush();
            
            if (results.length == 0) {
                logger.debug_("No results to write");
                return;
            }
            
            logger.debug_("Writing " ~ results.length.to!string ~ " results to CSV");
            
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
                            value = lines[$ - 1].strip();
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

    void close() @safe {
        synchronized(mutex) {
            if (isInitialized) {
                outputFile.close();
                isInitialized = false;
            }
        }
    }

    ~this() {
        close();
    }
}

