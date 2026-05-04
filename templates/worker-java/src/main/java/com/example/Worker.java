package com.example;

import java.util.Map;
import java.util.TreeMap;

public class Worker {
    public static void main(String[] args) throws InterruptedException {
        System.out.println("{{ .Name }} worker starting");

        Map<String, String> bindings = new TreeMap<>();
        for (Map.Entry<String, String> e : System.getenv().entrySet()) {
            if (e.getKey().endsWith("_HOST") || e.getKey().endsWith("_PORT")) {
                bindings.put(e.getKey(), e.getValue());
            }
        }
        bindings.forEach((k, v) -> System.out.printf("  binding: %s=%s%n", k, v));

        Runtime.getRuntime().addShutdownHook(new Thread(() ->
            System.out.println("shutting down")));

        while (true) {
            System.out.printf("[%s] heartbeat%n", java.time.Instant.now());
            Thread.sleep(10_000);
        }
    }
}
