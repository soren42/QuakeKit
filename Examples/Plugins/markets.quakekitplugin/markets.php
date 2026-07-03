<?php
$stdin = stream_get_contents(STDIN);
echo json_encode([
    "symbols" => [
        ["symbol" => "AAPL", "price" => 214.12, "change" => 0.8],
        ["symbol" => "NVDA", "price" => 158.24, "change" => -0.4]
    ],
    "source" => "markets.php"
]) . PHP_EOL;
