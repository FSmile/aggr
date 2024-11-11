module utils.logging;

import std.stdio;
import std.datetime;
import core.sync.mutex;
import core.interfaces : ILogger;
import core.types : LogLevel;
import std.format : format;

class FileLogger : ILogger {
    private File logFile;
    private string logPath;

    this(string path) {
        logPath = path;
        logFile = File(path, "w");
    }

    void log(LogLevel level, string message, string file = __FILE__, int line = __LINE__) {
        auto timestamp = Clock.currTime();
        logFile.writefln("%s [%s] %s", timestamp, level, message);
        logFile.flush();
    }

    void error(string message, Exception e = null) {
        if (e !is null) {
            log(LogLevel.ERROR, message ~ ": " ~ e.msg);
            debug log(LogLevel.ERROR, e.toString());
        } else {
            log(LogLevel.ERROR, message);
        }
    }

    void warning(string message) {
        log(LogLevel.WARNING, message);
    }

    void info(string message) {
        log(LogLevel.INFO, message);
    }

    void debug_(string message) {
        log(LogLevel.DEBUG, message);
    }

    ~this() {
        if (logFile.isOpen) {
            logFile.close();
        }
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