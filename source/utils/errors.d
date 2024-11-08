// source/utils/errors.d
module utils.errors;

class ApplicationException : Exception {
    this(string msg, Exception cause = null) {
        super(msg, cause);
    }
}

class ConfigException : Exception {
    this(string msg) {
        super(msg);
    }
}

class LogParserException : ApplicationException {
    this(string msg, Exception cause = null) {
        super(msg, cause);
    }
}