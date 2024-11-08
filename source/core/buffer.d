module core.buffer;

import core.sync.mutex;
import std.container : DList;
import core.memory : GC;
import std.array : array;

class InputBuffer {
    private {
        DList!string lines;
        shared Mutex mutex;
        size_t capacity;
        size_t currentSize;
    }

    this(size_t initialCapacity = 16 * 1024 * 1024) { // 16MB
        mutex = new shared Mutex();
        capacity = initialCapacity;
        currentSize = 0;
        lines = DList!string();
    }

    bool push(string line) @safe {
        synchronized(mutex) {
            if (currentSize + line.length > capacity) {
                return false;
            }
            lines.insertBack(line);
            currentSize += line.length;
            return true;
        }
    }

    string[] flush() @safe {
        synchronized(mutex) {
            auto result = lines[].array;
            lines.clear();
            currentSize = 0;
            return result;
        }
    }
}

