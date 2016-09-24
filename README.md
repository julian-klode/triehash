# Order-preserving minimal perfect hash function generator

Build order-preserving minimal perfect hash functions.

## Performance

Performance evaluation of an APT Packages file recognizer, times in
nanoseconds, averaged over 100,000,000 runs:

amd64:

word                |perfect| gperf |djbhash|alphaha
--------------------|-------|-------|-------|-------
Package             |      9|     11|     10|      9
PACKAGE             |      9|     11|     10|      9
NotExisting         |      2|      5|     16|      9
Installed-Size      |     14|     18|     20|      9

arm64:

word                |perfect| gperf |djbhash|alphaha
--------------------|-------|-------|-------|-------
Package             |     14|     20|     15|     13
PACKAGE             |     12|     20|     14|     13
NotExisting         |      4|      8|     17|     12
Installed-Size      |     22|     29|     21|     12

armhf:

word                |perfect| gperf |djbhash|alphaha
--------------------|-------|-------|-------|-------
Package             |     14|     23|     14|     11
PACKAGE             |     12|     23|     14|     11
NotExisting         |      4|      7|     18|     13
Installed-Size      |     22|     35|     21|     11
