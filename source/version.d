module version_info;

import std.conv : to;
import std.json;
import std.file;

//enum VERSION = mixin("import(\"version\");");
enum BUILD_DATE = __TIMESTAMP__;
enum COMPILER_VERSION = to!string(__VERSION__);

struct VersionInfo {
    string version_;
    string buildDate;
    string compiler;
    
    static VersionInfo current() {
        return VersionInfo(getVersion, BUILD_DATE, COMPILER_VERSION);
    }
    
    string toString() const {
        import std.format : format;
        return format("Log Aggregator v%s\nBuild: %s\nCompiler: v%s", 
            version_, buildDate, compiler);
    }

    private static string getVersion() {
        auto jsonContent = readText("dub.json");
        auto json = parseJSON(jsonContent);
        return json["version"].to!string();
    }
}

