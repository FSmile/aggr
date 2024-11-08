module utils.hash;

string getFastHash(string input) {
    if (input.length == 0) return "";
    
    // FNV-1a hash algorithm
    enum ulong FNV_PRIME = 1_099_511_628_211;
    enum ulong FNV_OFFSET_BASIS = 14_695_981_039_346_656_037;
    
    ulong hash = FNV_OFFSET_BASIS;
    
    foreach (ubyte c; input) {
        hash ^= c;
        hash *= FNV_PRIME;
    }
    
    // Преобразуем число в 16-символьную hex строку
    char[16] result;
    foreach_reverse (i; 0..16) {
        auto digit = hash & 0xF;
        result[i] = cast(char)(digit < 10 ? '0' + digit : 'A' + (digit - 10));
        hash >>= 4;
    }
    
    return result.idup;
}