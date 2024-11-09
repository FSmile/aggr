module utils.logging;

import std.stdio;
import std.datetime;
import core.sync.mutex;
import core.interfaces : ILogger;
import core.types : LogLevel;
import std.format : format;

class FileLogger : ILogger {
    private {
        File logFile;
        shared Mutex mutex;
    }

    this(string path) {
        logFile = File(path, "w");
        mutex = new shared Mutex();
    }

    ~this() {
        synchronized(mutex) {
            if (logFile.isOpen) {
                logFile.close();
            }
        }
    }

    private void writeLog(LogLevel level, string message) {
        synchronized(mutex) {
            auto timestamp = Clock.currTime();
            logFile.writefln("%s [%s] %s", timestamp.toSimpleString(), level, message);
            logFile.flush();
        }
    }

    void log(LogLevel level, string message, string file = __FILE__, int line = __LINE__) {
        writeLog(level, format("%s(%d): %s", file, line, message));
    }

    void error(string message, Exception e = null) {
        if (e !is null) {
            writeLog(LogLevel.ERROR, format("%s: %s\n%s", message, e.msg, e.toString()));
        } else {
            writeLog(LogLevel.ERROR, message);
        }
    }

    void info(string message) {
        writeLog(LogLevel.INFO, message);
    }

    void debug_(string message) {
        writeLog(LogLevel.DEBUG, message);
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