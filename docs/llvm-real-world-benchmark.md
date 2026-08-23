# LLVM real-world folder benchmark

GrapeCompare 1.0.5 was exercised against the official LLVM 21.1.8 and 22.1.8 source archives. GitHub's published SHA-256 digests were verified before extraction.

| Input | Files and symbolic links | Extracted size |
| --- | ---: | ---: |
| LLVM 21.1.8 | 160,123 | 2.1 GiB |
| LLVM 22.1.8 | 169,029 | 2.3 GiB |

Three cross-version runs completed in 9.60–9.67 seconds with approximately 218 MB maximum resident memory. Every run returned the same result:

| Result | Count |
| --- | ---: |
| Same | 125,964 |
| Different | 32,386 |
| Left only | 1,773 |
| Right only | 10,679 |

An independent, single-threaded chunk comparator reproduced all four counts exactly and took 27.78 seconds. A worst-I/O self-comparison of the 2.3 GiB LLVM 22.1.8 tree completed in 8.30 seconds and classified all 169,029 leaves as identical.

Results were recorded on the project development machine and will vary with storage, CPU, filesystem cache state, and thermal conditions. Reproduce the comparison with any two extracted trees:

```bash
bash macos/Benchmarks/run-real-folder-benchmark.sh /path/to/llvm-21.1.8 /path/to/llvm-22.1.8
```
