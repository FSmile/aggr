module version_info;

import std.conv : to;

enum VERSION = "0.0.1";
enum BUILD_DATE = __TIMESTAMP__;
enum COMPILER_VERSION = to!string(__VERSION__);

struct VersionInfo {
    string version_;
    string buildDate;
    string compiler;
    
    static VersionInfo current() {
        return VersionInfo(VERSION, BUILD_DATE, COMPILER_VERSION);
    }
    
    string toString() const {
        import std.format : format;
        return format("Log Aggregator v%s\nBuild: %s\nCompiler: v%s", 
            version_, buildDate, compiler);
    }
}

