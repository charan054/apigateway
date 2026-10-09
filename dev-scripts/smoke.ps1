<#
.SYNOPSIS
    Quick end-to-end check of the local stack - run it after start-all.ps1. Exits 0 when nothing failed, 1 otherwise.

.DESCRIPTION
    Checks that all five services are listening, that the public catalog answers directly and through the gateway,
    that the storefront and FAQ are served, that an anonymous caller is refused on a protected endpoint, and (when the
    service key is available) that OrderService's health board is green and that a CASH order can be placed and
    cancelled with the stock coming back exactly.

    The order check places a real order for a throwaway phone number (default 9000000999) and cancels it again, so
    it leaves one CANCELLED order row in the dev database. Use -SkipOrder to leave the database untouched.

    The service key is read, in order, from -ServiceKey, the INTERNAL_SERVICE_API_KEY environment variable, or
    OrderService\.env. It is only ever sent as a request header, never printed. Without one, the checks that need
    it are reported as SKIP.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File dev-scripts\smoke.ps1
    powershell -ExecutionPolicy Bypass -File dev-scripts\smoke.ps1 -SkipOrder
#>
param(
    [string]$ServiceKey,
    [string]$Phone = "9000000999",
    [switch]$SkipOrder
)
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "stack.ps1")

$Order = "http://localhost:8083"
$Gateway = "http://localhost:9000"
$script:Failed = 0
$script:Skipped = 0

function Write-Result([string]$State, [string]$Name, [string]$Detail) {
    $color = switch ($State) { "PASS" { "Green" } "FAIL" { "Red" } default { "DarkGray" } }
    $suffix = if ($Detail) { " - $Detail" } else { "" }
    Write-Host ("  {0}  {1}{2}" -f $State, $Name, $suffix) -ForegroundColor $color
}

# Runs a check. The body throws to fail, or returns a short detail string to show next to PASS.
function Test-Step([string]$Name, [scriptblock]$Body) {
    try {
        $detail = & $Body
        Write-Result "PASS" $Name ([string]$detail)
        return $true
    } catch {
        $script:Failed++
        Write-Result "FAIL" $Name $_.Exception.Message
        return $false
    }
}

function Skip-Step([string]$Name, [string]$Why) {
    $script:Skipped++
    Write-Result "SKIP" $Name $Why
}

# Status code and body without throwing on 4xx/5xx (Windows PowerShell 5.1 throws on them, and its error bodies
# come back empty, so only the status is dependable).
function Get-Http([string]$Url, [string]$Method = "GET", $Headers = @{}, [string]$Body = $null) {
    $request = @{ Uri = $Url; Method = $Method; Headers = $Headers; UseBasicParsing = $true; TimeoutSec = 20 }
    if ($Body) { $request.Body = $Body; $request.ContentType = "application/json" }
    try {
        $r = Invoke-WebRequest @request
        return [pscustomobject]@{ Status = [int]$r.StatusCode; Body = $r.Content }
    } catch {
        $resp = $_.Exception.Response
        if ($resp) { return [pscustomobject]@{ Status = [int]$resp.StatusCode; Body = "" } }
        throw "no answer from $Url ($($_.Exception.Message))"
    }
}

# Windows PowerShell 5.1 hands a JSON array back as ONE object, so `@($text | ConvertFrom-Json).Count` is always 1.
# Piping through ForEach-Object unrolls it into its elements.
function ConvertFrom-JsonArray([string]$Text) {
    $parsed = $Text | ConvertFrom-Json
    return , @($parsed | ForEach-Object { $_ })
}

function Assert-Status($Response, [int]$Expected, [string]$What) {
    if ($Response.Status -ne $Expected) { throw "$What answered $($Response.Status), expected $Expected" }
}

function Read-ServiceKey {
    if ($ServiceKey) { return $ServiceKey }
    if ($env:INTERNAL_SERVICE_API_KEY) { return $env:INTERNAL_SERVICE_API_KEY }
    $envFile = Join-Path (Join-Path $StackRoot "OrderService") ".env"
    if (Test-Path $envFile) {
        $line = Get-Content $envFile | Where-Object { $_ -match '^\s*INTERNAL_SERVICE_API_KEY\s*=' } | Select-Object -First 1
        if ($line) { return ($line -replace '^\s*INTERNAL_SERVICE_API_KEY\s*=\s*', '').Trim().Trim('"').Trim("'") }
    }
    return $null
}

Write-Host "Smoke test of the local stack" -ForegroundColor Cyan

# ---- 1. every service is listening ----
foreach ($svc in $StackServices) {
    Test-Step "$($svc.Name) is listening on :$($svc.Port)" {
        if (-not (Get-ListeningPid $svc.Port)) { throw "nothing is listening - start it with start-all.ps1" }
    } | Out-Null
}

# ---- 2. public catalog, directly and through the gateway ----
$directCount = $null
Test-Step "Catalog answers directly (OrderService /cart/display)" {
    $r = Get-Http "$Order/cart/display"
    Assert-Status $r 200 "/cart/display"
    $items = (ConvertFrom-JsonArray $r.Body)
    if ($items.Count -lt 1) { throw "the catalog is empty" }
    $script:directCount = $items.Count
    "$($items.Count) products"
} | Out-Null

Test-Step "Catalog answers through the gateway (/cart/display)" {
    $r = Get-Http "$Gateway/cart/display"
    Assert-Status $r 200 "gateway /cart/display"
    $count = (ConvertFrom-JsonArray $r.Body).Count
    if ($script:directCount -and $count -ne $script:directCount) { throw "gateway returned $count products, direct returned $($script:directCount)" }
    "$count products"
} | Out-Null

Test-Step "ProductService answers through the gateway (/product/all)" {
    Assert-Status (Get-Http "$Gateway/product/all") 200 "gateway /product/all"
} | Out-Null

Test-Step "Help / FAQ answers through the gateway (/faq)" {
    Assert-Status (Get-Http "$Gateway/faq") 200 "gateway /faq"
} | Out-Null

Test-Step "Pincode check answers through the gateway (/pincodes/check)" {
    Assert-Status (Get-Http "$Gateway/pincodes/check?pincode=411001") 200 "gateway /pincodes/check"
} | Out-Null

Test-Step "Gateway keeps protected endpoints protected (/giftcards, /admin/accounts)" {
    Assert-Status (Get-Http "$Gateway/giftcards") 401 "gateway /giftcards without a key"
    Assert-Status (Get-Http "$Gateway/admin/accounts") 401 "gateway /admin/accounts without a key"
} | Out-Null

# ---- 3. static pages and public endpoints ----
Test-Step "Storefront page is served (/shop.html)" {
    Assert-Status (Get-Http "$Order/shop.html") 200 "/shop.html"
} | Out-Null

Test-Step "Help / FAQ answers (/faq)" {
    $r = Get-Http "$Order/faq"
    Assert-Status $r 200 "/faq"
    "$((ConvertFrom-JsonArray $r.Body).Count) entries"
} | Out-Null

# ---- 4. security is wired: anonymous callers are refused ----
Test-Step "Anonymous caller is refused on a protected endpoint (/cart/all)" {
    Assert-Status (Get-Http "$Order/cart/all") 401 "/cart/all without a key"
} | Out-Null

# ---- 5. checks that need the service key ----
$key = Read-ServiceKey
if (-not $key) {
    Skip-Step "Health board is green" "no service key (set INTERNAL_SERVICE_API_KEY or pass -ServiceKey)"
    Skip-Step "CASH order can be placed and cancelled" "no service key"
} else {
    $auth = @{ "X-Service-Key" = $key }

    Test-Step "Health board is green (/cart/health)" {
        $r = Get-Http "$Order/cart/health" "GET" $auth
        Assert-Status $r 200 "/cart/health"
        $down = @((ConvertFrom-JsonArray $r.Body) | Where-Object { $_.status -ne "UP" } | ForEach-Object { $_.name })
        if ($down.Count -gt 0) { throw ("down: " + ($down -join ", ")) }
        "all services UP"
    } | Out-Null

    if ($SkipOrder) {
        Skip-Step "CASH order can be placed and cancelled" "-SkipOrder"
    } else {
        $orderId = $null
        $stockBefore = $null
        $productId = $null
        $placed = Test-Step "CASH order can be placed (phone $Phone)" {
            $catalog = (ConvertFrom-JsonArray (Get-Http "$Order/cart/display").Body)
            # The cheapest well-stocked product (never the last units of anything), so a new phone number stays under the cash-on-delivery limit.
            $product = $catalog | Where-Object { $_.productStock -ge 10 } | Sort-Object productPrice | Select-Object -First 1
            if (-not $product) { throw "no product with at least 10 in stock to order" }
            $script:productId = $product.productId
            $script:stockBefore = $product.productStock
            $body = @{
                customerName  = "Smoke Test"
                customerPhno  = [long]$Phone
                paymentMethod = "CASH"
                orderItems    = @(@{ productId = $product.productId; productQuantity = 1 })
            } | ConvertTo-Json -Depth 5
            $r = Get-Http "$Order/cart/checkout" "POST" $auth $body
            Assert-Status $r 200 "/cart/checkout"
            $created = $r.Body | ConvertFrom-Json
            if (-not $created.orderId) { throw "no order id in the response" }
            $script:orderId = $created.orderId
            "order #$($created.orderId), product $($product.productId), status $($created.status)"
        }
        if ($placed) {
            Test-Step "Order can be cancelled again" {
                $r = Get-Http "$Order/cart/$($script:orderId)/cancel?reason=OTHER&note=smoke-test" "POST" $auth
                Assert-Status $r 200 "cancel"
                $status = ($r.Body | ConvertFrom-Json).status
                if ($status -ne "CANCELLED") { throw "status is $status, expected CANCELLED" }
                "order #$($script:orderId) CANCELLED"
            } | Out-Null
            Test-Step "Stock came back exactly" {
                $after = ((ConvertFrom-JsonArray (Get-Http "$Order/cart/display").Body) | Where-Object { $_.productId -eq $script:productId }).productStock
                if ($after -ne $script:stockBefore) { throw "product $($script:productId) stock was $($script:stockBefore), is now $after" }
                "product $($script:productId) back to $after"
            } | Out-Null
        }
    }
}

Write-Host ""
if ($script:Failed -gt 0) {
    Write-Host "$($script:Failed) check(s) FAILED, $($script:Skipped) skipped." -ForegroundColor Red
    exit 1
}
Write-Host "All checks passed ($($script:Skipped) skipped)." -ForegroundColor Green
exit 0
