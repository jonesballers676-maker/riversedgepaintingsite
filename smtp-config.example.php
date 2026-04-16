<?php
/**
 * Copy this file to smtp-config.php (same folder as send-quote.php) and fill in values.
 * Do not commit smtp-config.php — it contains your mailbox password.
 *
 * DreamHost (panel “Email Client Setup”): SMTP smtp.dreamhost.com, port 587, TLS.
 * Username = full email address, e.g. info@robertjonesroofing.com
 *
 * @see https://help.dreamhost.com/hc/en-us/articles/216140597-Send-PHP-mail-via-SMTP
 */
declare(strict_types=1);

return [
    'host'     => 'smtp.dreamhost.com',
    'port'     => 587,
    'username' => 'info@robertjonesroofing.com',
    'password' => 'YOUR_MAILBOX_PASSWORD_HERE',
    'secure'   => 'tls',
];
