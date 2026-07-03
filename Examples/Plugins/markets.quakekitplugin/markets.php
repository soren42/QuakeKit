<?php
$stdin = stream_get_contents(STDIN);
$symbols = getenv("QUAKEKIT_MARKET_SYMBOLS") ?: "AAPL,NVDA,MSFT";
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
            $rows[] = [
                "symbol" => strtoupper($symbol),
                "price" => round($price, 2),
                "change" => $change
            ];
            continue;
        }
    }
}

if (!$rows) {
    $rows = [
        ["symbol" => "AAPL", "price" => 214.12, "change" => 0.8],
        ["symbol" => "NVDA", "price" => 158.24, "change" => -0.4]
    ];
}

echo json_encode([
    "symbols" => $rows,
    "source" => count($rows) ? "markets.php" : "fallback"
]) . PHP_EOL;
