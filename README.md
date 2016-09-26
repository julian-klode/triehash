# Order-preserving minimal perfect hash function generator

Build order-preserving minimal perfect hash functions. It can also generate
functions for matching shortest or longest prefixes.

## Performance

Performance was evaluated against other hash functions. As an input set, the
fields of Debian Packages and Sources files was used, and each hash function
was run 1,000,000 times for each word. The table below shows the total time
per hash function, in nanoseconds for hashing these 82 words:


host     | arch     |Trie     |TrieCase |GPerfCase|GPerf    |DJBCase  |DJBCase2 |DJB      |APTCase  |APTCase2
---------|----------|---------|---------|---------|---------|---------|---------|---------|---------|----------
plummer  | ppc64el  |      540|      601|     1914|     2000|     1639|     1399|     1345|      798|      473
eller    | mipsel   |     4728|     5255|    12018|     7837|     6400|     4147|     4087|     3593|     3496
asachi   | arm64    |     1000|     1603|     4333|     2401|     2716|     2179|     1625|     1289|     1160
asachi   | armhf    |     1230|     1350|     5593|     5002|     2690|     1845|     1784|     1256|     1101
barriere | amd64    |      689|      950|     3218|     1982|     2191|     2049|     1776|     1101|      698
x230     | amd64    |      465|      504|     1200|      837|     1288|      970|      693|      766|      366

Legend:

* The case variants are case-insensitive
* DJBCase is a DJB Hash with lowercase conversion, DJBCase2 just ORs one
  bit into each value to get alphabetical characters to be lowercase
* APTCase is the AlphaHash function from APT which hashes the last 8 bytes in a
  word in a case-insensitive manner. APTCase2 is the same function unrolled.
* All hosts except the x230 are Debian porterboxes. The x230 has a Core i5-3320M,
  barriere has an Opteron 23xx.

Notes:

* The overhead is larger than needed on some platforms due to gcc inserting
  unneeded zero extend instructions, see:
  https://gcc.gnu.org/bugzilla/show_bug.cgi?id=77729
