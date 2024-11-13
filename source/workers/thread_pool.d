module workers.thread_pool;

import core.thread;
import core.sync.mutex;
import core.sync.condition;
import std.container.dlist;
import core.atomic;
import std.range;
import core.interfaces : ILogAnalyzer;

class ThreadPool {
    private {
        Thread[] threads;
        DList!Task taskQueue;
        shared bool isRunning;
        shared Mutex mutex;
        shared Condition condition;
        shared size_t activeTaskCount;
        size_t threadCount;
        ILogAnalyzer logAnalyzer;
    }

    struct Task {
        void delegate() work;
        size_t workerId;
    }

    this(size_t count, ILogAnalyzer analyzer) {
        threadCount = count;
        logAnalyzer = analyzer;
        mutex = new shared Mutex();
        condition = new shared Condition(mutex);
        isRunning = true;
        activeTaskCount = 0;
        
        threads = new Thread[](threadCount);
        foreach(i; 0..threadCount) {
            threads[i] = new Thread(() => workerFunction(i));
            threads[i].start();
        }
    }

    private void workerFunction(size_t workerId) {
        while(atomicLoad(isRunning)) {
            Task task;
            bool hasTask = false;
            
            synchronized(mutex) {
                while(taskQueue.empty && atomicLoad(isRunning)) {
                    logAnalyzer.flushThreadBuffer(workerId);
                    condition.wait();
                }
                
                if(!taskQueue.empty) {
                    task = taskQueue.front;
                    taskQueue.removeFront();
                    hasTask = true;
                    atomicOp!"+="(activeTaskCount, 1);
                }
            }
            
            if(hasTask) {
                try {
                    task.work();
                } finally {
                    synchronized(mutex) {
                        atomicOp!"-="(activeTaskCount, 1);
                        if(activeTaskCount == 0) {
                            condition.notifyAll();
                        }
                    }
                }
            }
        }
        logAnalyzer.flushThreadBuffer(workerId);
    }

    void addTask(void delegate() work, size_t workerId) {
        synchronized(mutex) {
            taskQueue.insertBack(Task(work, workerId));
            condition.notify();
        }
    }

    void shutdown() {
        synchronized(mutex) {
            atomicStore(isRunning, false);
            condition.notifyAll();
        }
        
        foreach(thread; threads) {
            thread.join();
        }
    }

    bool waitForCompletion(Duration timeout = 5.seconds) {
        synchronized(mutex) {
            while(activeTaskCount > 0) {
                if(!condition.wait(timeout)) {
                    return false;
                }
            }
            return true;
        }
    }
}

