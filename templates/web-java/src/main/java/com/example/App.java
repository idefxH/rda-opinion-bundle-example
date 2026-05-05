package com.example;

import com.sun.net.httpserver.HttpServer;
import com.sun.net.httpserver.HttpExchange;
import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.util.Map;
import java.util.TreeMap;

public class App {
    public static void main(String[] args) throws IOException {
        int port = Integer.parseInt(System.getenv().getOrDefault("PORT", "8080"));
        HttpServer server = HttpServer.create(new InetSocketAddress(port), 0);

        server.createContext("/", exchange -> {
            boolean hasCache = System.getenv().entrySet().stream()
                .anyMatch(e -> e.getKey().endsWith("_HOST") && e.getKey().toLowerCase().contains("cache"));
            String body = "{\"name\":\"{{ .Name }}\",\"status\":\"ok\"" +
                ",\"cache\":" + (hasCache ? "\"connected\"" : "\"not configured\"") +
                ",\"bindings\":" + discoverBindings() + "}";
            sendJson(exchange, body);
        });

        server.createContext("/health", exchange -> {
            sendJson(exchange, "{\"status\":\"ok\"}");
        });

        server.setExecutor(null);
        System.out.println("{{ .Name }} listening on :" + port);
        server.start();
    }

    private static void sendJson(HttpExchange exchange, String body) throws IOException {
        exchange.getResponseHeaders().set("Content-Type", "application/json");
        byte[] bytes = body.getBytes();
        exchange.sendResponseHeaders(200, bytes.length);
        try (OutputStream os = exchange.getResponseBody()) {
            os.write(bytes);
        }
    }

    private static String discoverBindings() {
        Map<String, Map<String, String>> bindings = new TreeMap<>();
        for (Map.Entry<String, String> e : System.getenv().entrySet()) {
            String key = e.getKey();
            if (key.endsWith("_HOST") || key.endsWith("_PORT") || key.endsWith("_DATABASE")) {
                int idx = key.lastIndexOf('_');
                String name = key.substring(0, idx).toLowerCase();
                String field = key.substring(idx + 1).toLowerCase();
                bindings.computeIfAbsent(name, k -> new TreeMap<>()).put(field, e.getValue());
            }
        }
        StringBuilder sb = new StringBuilder("{");
        boolean first = true;
        for (Map.Entry<String, Map<String, String>> b : bindings.entrySet()) {
            if (!first) sb.append(",");
            sb.append("\"").append(b.getKey()).append("\":{");
            boolean ff = true;
            for (Map.Entry<String, String> f : b.getValue().entrySet()) {
                if (!ff) sb.append(",");
                sb.append("\"").append(f.getKey()).append("\":\"").append(f.getValue()).append("\"");
                ff = false;
            }
            sb.append("}");
            first = false;
        }
        sb.append("}");
        return sb.toString();
    }
}
