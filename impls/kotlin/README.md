# Kotlin BMSSP

Build:

- Requires JDK and Kotlin compiler (`kotlinc`).
- Runner compiles to `impls/kotlin/bmssp_kotlin.jar`.

Manual build:

```sh
kotlinc src/main/kotlin/Main.kt -include-runtime -d bmssp_kotlin.jar
```

Run (example):

```sh
java -jar bmssp_kotlin.jar --json --trials 1 --k 4 --B 100 --seed 42 --maxw 100 --graph grid --rows 10 --cols 10
```
Kotlin BMSSP CLI

- Build: kotlinc src/main/kotlin/Main.kt -include-runtime -d bmssp_kotlin.jar
- Run: java -jar bmssp_kotlin.jar --json --graph grid --rows 50 --cols 50 --k 4 --B 100 --trials 1 --seed 1 --maxw 100
