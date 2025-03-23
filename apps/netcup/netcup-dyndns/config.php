<?php

function getRequiredEnv($name) {
    if (($value = getenv($name)) === false) {
        echo "Error: Required environment variable '$name' is not set.\n";
        exit(1);
    }
    return $value;
}

function getBoolEnv($name, $default) {
    $value = getenv($name);
    return $value !== false ? ($value == "true") : $default;
}

// Required environment variables
define("CUSTOMERNR", getRequiredEnv("CUSTOMERNR"));
define("APIPASSWORD", getRequiredEnv("APIPASSWORD"));
define("APIKEY", getRequiredEnv("APIKEY"));
define("DOMAINLIST", getRequiredEnv("DOMAINLIST"));

// Optional environment variables with defaults
define("IPV4_ADDRESS_URL", getenv("IPV4_ADDRESS_URL") ?: "https://get-ipv4.steck.cc");
define("IPV4_ADDRESS_URL_FALLBACK", getenv("IPV4_ADDRESS_URL_FALLBACK") ?: "https://ipv4.seeip.org");
define("IPV6_ADDRESS_URL", getenv("IPV6_ADDRESS_URL") ?: "https://get-ipv6.steck.cc");
define("IPV6_ADDRESS_URL_FALLBACK", getenv("IPV6_ADDRESS_URL_FALLBACK") ?: "https://v6.ident.me");
define("USE_IPV4", getBoolEnv("USE_IPV4", true));
define("USE_IPV6", getBoolEnv("USE_IPV6", false));
define("CHANGE_TTL", getBoolEnv("CHANGE_TTL", true));
define("APIURL", getenv("APIURL") ?: "https://ccp.netcup.net/run/webservice/servers/endpoint.php?JSON");
