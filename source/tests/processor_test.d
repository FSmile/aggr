module tests.processor_test;
import std.conv : ConvException;
unittest {
    auto config = Config();
    config.workerCount = 1;
    
    auto analyzer = new LogAnalyzerMock();
    auto processor = new DataProcessor(config, analyzer);
    
    auto testFile = File("test.log", "w");
    scope(exit) {
        testFile.close();
        remove("test.log");
    }
    
    // Записываем многострочный контекст
    testFile.writeln("40:33.299009-1515852,DBPOSTGRS,6,Context='");
    testFile.writeln("Line 1");
    testFile.writeln("Line 2");
    testFile.writeln("Line 3'");
    testFile.close();
    
    config.inputPath = "test.log";
    processor.start();
    
    assert(analyzer.getProcessedLines() == 1);
    assert(analyzer.getLastContext().indexOf("Line 1") != -1);
    assert(analyzer.getLastContext().indexOf("Line 2") != -1);
    assert(analyzer.getLastContext().indexOf("Line 3") != -1);
} 

 