<?php
$stdin = stream_get_contents(STDIN);
$symbols = getenv("QUAKEKIT_MARKET_SYMBOLS") ?: "AAPL,NVDA,MSFT";
$displayMode = getenv("QUAKEKIT_MARKET_DISPLAY_MODE") ?: "compact";
$rows = [];

foreach (array_slice(array_map("trim", explode(",", $symbols)), 0, 6) as $symbol) {
    if ($symbol === "") {
        continue;
    }
    $url = "https://query1.finance.yahoo.com/v8/finance/chart/" . rawurlencode($symbol) . "?range=1d&interval=1d";
    $json = @file_get_contents($url);
    if ($json !== false) {
        $data = json_decode($json, true);
        $result = $data["chart"]["result"][0] ?? null;
        $meta = $result["meta"] ?? [];
        $price = $meta["regularMarketPrice"] ?? $meta["previousClose"] ?? null;
        $previous = $meta["chartPreviousClose"] ?? $meta["previousClose"] ?? null;
        if ($price !== null) {
            $change = ($previous !== null) ? round($price - $previous, 2) : 0;
            $changePercent = ($previous !== null && $previous != 0) ? round(($change / $previous) * 100, 2) : 0;
            $rows[] = [
                "symbol" => strtoupper($symbol),
                "price" => round($price, 2),
                "change" => $change,
                "changePercent" => $changePercent,
                "currency" => $meta["currency"] ?? "USD",
                "exchange" => $meta["exchangeName"] ?? "",
                "sparkline" => [round($price - 1.4, 2), round($price - 0.8, 2), round($price - 0.2, 2), round($price, 2)]
            ];
            continue;
        }
    }
}

if (!$rows) {
    $rows = [
        ["symbol" => "AAPL", "price" => 214.12, "change" => 0.8, "changePercent" => 0.37, "currency" => "USD", "exchange" => "NASDAQ", "sparkline" => [211.2, 212.8, 213.4, 214.12]],
        ["symbol" => "NVDA", "price" => 158.24, "change" => -0.4, "changePercent" => -0.25, "currency" => "USD", "exchange" => "NASDAQ", "sparkline" => [159.1, 158.9, 158.4, 158.24]],
        ["symbol" => "MSFT", "price" => 497.48, "change" => 1.22, "changePercent" => 0.25, "currency" => "USD", "exchange" => "NASDAQ", "sparkline" => [494.8, 495.9, 496.6, 497.48]]
    ];
    $dataSource = "fallback";
} else {
    $dataSource = "yahoo";
}

echo json_encode([
    "ok" => true,
    "symbols" => $rows,
    "mode" => $displayMode,
    "updatedAt" => gmdate("c"),
    "actions" => [
        ["id" => "markets.refresh", "title" => "Refresh Watchlist", "enabled" => true],
        ["id" => "markets.openChart", "title" => "Open Chart", "enabled" => true, "dryRun" => true]
    ],
    "rows" => array_map(function ($row) {
        $direction = ($row["change"] ?? 0) >= 0 ? "up" : "down";
        return [
            "title" => $row["symbol"],
            "value" => number_format((float)$row["price"], 2),
            "detail" => $direction . " " . number_format((float)$row["change"], 2) . " (" . number_format((float)($row["changePercent"] ?? 0), 2) . "%) · " . ($row["exchange"] ?? "")
        ];
    }, $rows),
    "source" => $dataSource
]) . PHP_EOL;
