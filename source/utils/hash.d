module utils.hash;

import std.digest.murmurhash;
import std.string : representation;
import std.format : format;

string getFastHash(string input) @safe {
    if (input.length == 0) return "";
    
    // Используем MurmurHash3 из стандартной библиотеки
    auto hash = digest!(MurmurHash3!128)(input.representation);
    
    // Преобразуем в 16-символьную hex строку 
    return format("%016x", hash[0]);
}