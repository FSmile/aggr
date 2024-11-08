module utils.logging;

import std.stdio;
import std.datetime;
import std.string;
import core.sync.mutex : Mutex;
import core.interfaces : ILogger;
import core.types : LogLevel;
import std.string : format;
import std.stdio : File;

class FileLogger : ILogger {
    private string filePath;
    private shared Mutex mutex;

    this(string path) {
        filePath = path;
        mutex = new shared Mutex();
    }

    void log(LogLevel level, string message, string file = __FILE__, int line = __LINE__) {
        synchronized(mutex) {
            auto timestamp = Clock.currTime().toISOExtString();
            auto logMessage = format("%s [%s] %s (%s:%d)\n", 
                timestamp, level, message, file, line);
            
            auto logFile = File(filePath, "a");
            scope(exit) logFile.close();
            logFile.write(logMessage);
        }
    }

    void error(string message, Exception e = null) {
        if (e !is null) {
            log(LogLevel.ERROR, message ~ ": " ~ e.msg);
        } else {
            log(LogLevel.ERROR, message);
        }
    }

    void info(string message) {
        log(LogLevel.INFO, message);
    }

    void debug_(string message) {
        log(LogLevel.DEBUG, message);
    }
}

void logToFile(string level, string message) {
    synchronized {
        auto timestamp = Clock.currTime().toISOExtString();
        auto logMessage = format("%s [%s] %s\n", timestamp, level, message);
        auto logFile = File("analyzer.log", "a");
        scope(exit) logFile.close();
        logFile.write(logMessage);
    }
}