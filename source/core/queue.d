module core.queue;

import std.container.dlist;
import core.sync.mutex;
import core.time;
import core.interfaces : ILogger;

class Queue(T) {
    private {
        DList!T items;
        shared Mutex mutex;
        ILogger logger;
        bool closed;
    }

    this(ILogger logger) {
        mutex = new shared Mutex();
        items = DList!T();
        this.logger = logger;
        closed = false;
    }

    bool push(T item) {
        synchronized(mutex) {
            if (closed) {
                logger.debug_("Queue is closed, cannot push items");
                return false;
            }
            
            try {
                items.insertBack(item);
                logger.debug_("Item pushed to queue");
                return true;
            } catch (Exception e) {
                logger.error("Failed to push item to queue", e);
                return false;
            }
        }
    }

    T pop() {
        synchronized(mutex) {
            if (items.empty) {
                return T.init;
            }
            
            try {
                auto front = items.front;
                items.removeFront();
                logger.debug_("Item popped from queue");
                return front;
            } catch (Exception e) {
                logger.error("Failed to pop item from queue", e);
                return T.init;
            }
        }
    }

    void close() {
        synchronized(mutex) {
            closed = true;
            items.clear();
            logger.info("Queue closed");
        }
    }

    @property bool empty() {
        synchronized(mutex) {
            return items.empty;
        }
    }

    @property size_t length() {
        synchronized(mutex) {
            size_t count = 0;
            foreach(item; items) {
                count++;
            }
            return count;
        }
    }
}