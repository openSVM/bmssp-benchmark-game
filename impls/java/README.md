# Java BMSSP

Build:

- Requires JDK 8 or later with `javac` and `java` commands.
- Runner compiles to `impls/java/bmssp_java.jar`.

Manual build:

```sh
javac src/main/java/Main.java -d build/
jar cfe bmssp_java.jar Main -C build/ .
```

Run (example):

```sh
java -jar bmssp_java.jar --json --trials 1 --k 4 --B 100 --seed 42 --maxw 100 --graph grid --rows 10 --cols 10
```

Java BMSSP CLI

- Build: javac src/main/java/Main.java -d build/ && jar cfe bmssp_java.jar Main -C build/ .
- Run: java -jar bmssp_java.jar --json --graph grid --rows 50 --cols 50 --k 4 --B 100 --trials 1 --seed 1 --maxw 100
