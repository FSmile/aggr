module log.parser;

import std.stdio : File;
import std.typecons : Nullable;
import std.algorithm : map, sum;
import std.array : array;
import std.string : replace;
import core.sync.mutex : Mutex;
import core.interfaces : IResultWriter;
import core.types : LogLine;
import std.regex;
import std.array : split;
import std.string : strip;

interface ILogParser {
    Nullable!(string[string]) parse(string line) @safe;
}

class LogParser : ILogParser {
    Nullable!(string[string]) parse(string line) @safe {
        auto parts = line.split(",");
        if (parts.length < 2) return Nullable!(string[string]).init;

        string[string] result;
        
        try {
            auto durationParts = parts[0].split("-");
            if (durationParts.length == 2) {
                result["Duration"] = durationParts[1];
            }
        } catch (Exception) {
            return Nullable!(string[string]).init;
        }

        foreach (part; parts[1..$]) {
            auto kv = part.split("=");
            if (kv.length == 2) {
                result[kv[0].strip] = kv[1].strip;
            } else {
                result["Group"] = part.strip;
            }
        }

        return Nullable!(string[string])(result);
    }
}

class CsvWriter : IResultWriter {
    private File outputFile;
    private shared Mutex mutex;

    this(string path) {
        outputFile = File(path, "w");
        mutex = new shared Mutex();
    }

    void write(LogLine[] results) @safe {
        synchronized(mutex) {
            scope(exit) outputFile.flush();
            
            // Записываем заголовок
            outputFile.writeln("Context,Count,Total(ms),Avg(ms),Max(ms)");
            
            // Записываем данные
            foreach(item; results) {
                outputFile.writefln("\"%s\",%d,%d,%d,%d",
                    item.lastContext.replace("\n", " ").replace("\"", "\"\""),
                    item.count,
                    item.sum / 1000,      // мкс -> мс
                    item.avg() / 1000,    // мкс -> мс
                    item.max / 1000       // мкс -> мс
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

