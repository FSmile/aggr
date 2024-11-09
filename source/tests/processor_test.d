module tests.processor_test;
import std.conv : ConvException;
unittest {
    // Тест параллельной обработки
    auto config = Config();
    config.workerCount = 2;
    config.timeout = 1.seconds;

    auto analyzer = new LogAnalyzerMock();
    auto processor = new DataProcessor(config, analyzer);

    // Имитируем входные данные
    auto testInput = ["line1", "line2", "line3"];
    foreach(line; testInput) {
        processor.buffer.push(line, config.timeout);
    }

    // Проверяем корректность параллельной обработки
    processor.start();
    Thread.sleep(100.msecs);
    processor.shutdown();

    assert(analyzer.getProcessedLines() == testInput.length);
} 

 