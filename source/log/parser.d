module log.parser;

import std.stdio : File;
import std.typecons : Nullable;
import std.algorithm : map, sum;
import std.array : array;
import std.string : replace, indexOf, strip, startsWith;
import core.sync.mutex : Mutex;
import core.interfaces : IResultWriter, ILogger;
import core.types : LogLine;
import std.regex;
import std.array : split;
import std.conv : to;
import std.encoding : getBOM, BOM, BOMSeq;

interface ILogParser {
    Nullable!(string[string]) parse(string line);
}

class LogParser : ILogParser {
    private ILogger logger;

    this(ILogger logger) {
        this.logger = logger;
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
        logger.debug_("Raw line length: " ~ line.length.to!string);
        line = removeBOM(line);
        logger.debug_("Line length after BOM removal: " ~ line.length.to!string);
        
        string[string] result;
        logger.debug_("Parsing line (after BOM removal): " ~ line);
        
        auto parts = line.split(",");
        logger.debug_("Split parts: " ~ parts.to!string);
        
        if (parts.length >= 1) {
            auto durationParts = parts[0].split("-");
            logger.debug_("Duration parts: " ~ durationParts.to!string);
            if (durationParts.length == 2) {
                result["Duration"] = durationParts[1];
                logger.debug_("Extracted Duration: " ~ result["Duration"]);
            }
        }

        if (line.indexOf("Context='") != -1) {
            logger.debug_("Found Context marker");
            auto contextStart = line.indexOf("Context='") + "Context='".length;
            result["Context"] = line[contextStart..$];
            logger.debug_("Extracted Context: " ~ result["Context"]);
            
            if ("Duration" !in result) {
                logger.debug_("No Duration found, returning null");
                return Nullable!(string[string]).init;
            }
            return Nullable!(string[string])(result);
        }

        foreach (part; parts[1..$]) {
            auto kv = part.split("=");
            if (kv.length == 2 && kv[0].strip == "Context") {
                result["Context"] = kv[1].strip.replace("'", "");
                logger.debug_("Found Context in parts: " ~ result["Context"]);
                if ("Duration" in result) {
                    return Nullable!(string[string])(result);
                }
            }
        }

        logger.debug_("No valid result found, returning null");
        return Nullable!(string[string]).init;
    }
}

class CsvWriter : IResultWriter {
    private File outputFile;
    private shared Mutex mutex;

    this(string path) {
        outputFile = File(path, "w");
        mutex = new shared Mutex();
    }

    void write(LogLine[] results) {
        synchronized(mutex) {
            scope(exit) outputFile.flush();
            
            // Записываем заголовок
            outputFile.writeln("Total(ms),Avg(ms),Max(ms),Count,Context");
            
            // Записываем данные
            foreach(item; results) {
                outputFile.writefln("%d,%d,%d,%d,\"%s\"",
                    item.sum / 1000,      // мкс -> мс
                    item.avg() / 1000,    // мкс -> мс
                    item.max / 1000,      // мкс -> мс
                    item.count,
                    item.lastContext.replace("\n", " ").replace("\"", "\"\"").strip()
                );
            }
            
            // Добавляем итоговую статистику
            outputFile.writeln();
            outputFile.writefln("# Total entries: %d", results.length);
            outputFile.writefln("# Total lines processed: %d", results.map!(r => r.count).sum());
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

