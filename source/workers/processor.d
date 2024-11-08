module workers.processor;

import core.interfaces : ILogger;
import core.types;
import core.queue;
import utils.logging;

class DataProcessor {
    private {
        ILogger logger;
        shared Queue!string queue;
        int workerCount;
    }

    this(int workerCount) {
        this.logger = new FileLogger("processor.log");
        this.queue = cast(shared)new Queue!string(this.logger);
        this.workerCount = workerCount;
    }
    // ... реализация ...
} 

 