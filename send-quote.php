<?php
/**
 * Quote form handler — emails leads from your domain.
 *
 * Reliable delivery on DreamHost: copy smtp-config.example.php → smtp-config.php
 * and set the SMTP password for a real mailbox (same settings as Apple Mail / Outlook).
 * Without smtp-config.php this script falls back to PHP mail(), which often never arrives.
 *
 * Every valid lead is also saved under data/leads/*.json (not web-accessible) so nothing
 * is lost if SMTP fails. Check that folder via FTP/SFTP if emails stop arriving.
 */
declare(strict_types=1);

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    header('Location: /quotes', true, 303);
    exit;
}

/** Office inbox — also receives a copy of every sales-associate lead. */
const OFFICE_TO = 'info@robertjonesroofing.com';

/** Whitelist: never trust client-supplied email addresses for "To". */
const ROUTES = [
    'general' => [
        'to'       => 'info@robertjonesroofing.com',
        'subject'  => 'Website Lead Form Submitted',
        'thank_qs' => '',
        'error_to' => '/quotes',
    ],
    'chris' => [
        'to'       => 'chris@robertjonesroofing.com',
        'subject'  => "Chris's Website Lead Form Submitted",
        'thank_qs' => '?rep=chris',
        'error_to' => '/quote-chris',
    ],
    'jason' => [
        'to'       => 'jason@robertjonesroofing.com',
        'subject'  => "Jason's Website Lead Form Submitted",
        'thank_qs' => '?rep=jason',
        'error_to' => '/quote-jason',
    ],
    'jake' => [
        'to'       => 'jake@robertjonesroofing.com',
        'subject'  => "Jake's Website Lead Form Submitted",
        'thank_qs' => '?rep=jake',
        'error_to' => '/quote-jake',
    ],
];

/** Use a real mailbox @ your domain for deliverability (DreamHost). */
$fromAddress = OFFICE_TO;
$fromLabel   = 'Robert Jones Roofing Website';

function field(string $key): string
{
    if (!isset($_POST[$key]) || !is_string($_POST[$key])) {
        return '';
    }
    $v = trim($_POST[$key]);
    $v = str_replace(["\r\n", "\r"], "\n", $v);
    return $v;
}

function strip_header_injection(string $s): string
{
    return str_replace(["\r", "\n", '%0a', '%0d', '%0A', '%0D'], '', $s);
}

function lead_storage_dir(): string
{
    $d = __DIR__ . '/data/leads';
    if (!is_dir($d)) {
        @mkdir($d, 0755, true);
    }
    return $d;
}

/** Backup copy of the lead on disk (JSON). Safe if email fails. */
function write_lead_file(string $path, array $data): void
{
    $json = json_encode($data, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT);
    if ($json === false) {
        error_log('send-quote.php: could not json_encode lead backup');
        return;
    }
    if (@file_put_contents($path, $json, LOCK_EX) === false) {
        error_log('send-quote.php: could not write lead backup: ' . $path);
    }
}

/**
 * Sends mail via SMTP if smtp-config.php exists; otherwise falls back to mail().
 * On DreamHost, SMTP (real mailbox login) is much more reliable than mail().
 *
 * @return array{ok: bool, error?: string}
 */
function send_quote_mail(
    string $toList,
    string $subject,
    string $bodyPlain,
    string $fromAddress,
    string $fromLabel,
    ?string $replyTo
): array {
    $smtpPath = __DIR__ . '/smtp-config.php';
    if (is_readable($smtpPath)) {
        /** @var array{host: string, port: int, username: string, password: string, secure?: string} $cfg */
        $cfg = require $smtpPath;
        foreach (['host', 'port', 'username', 'password'] as $k) {
            if (empty($cfg[$k])) {
                error_log('send-quote.php: smtp-config.php missing key: ' . $k);
                return ['ok' => false, 'error' => 'incomplete smtp config'];
            }
        }

        require_once __DIR__ . '/lib/phpmailer/Exception.php';
        require_once __DIR__ . '/lib/phpmailer/PHPMailer.php';
        require_once __DIR__ . '/lib/phpmailer/SMTP.php';

        $mail = new \PHPMailer\PHPMailer\PHPMailer(true);
        try {
            $mail->isSMTP();
            $mail->Host = $cfg['host'];
            $mail->SMTPAuth = true;
            $mail->Username = $cfg['username'];
            $mail->Password = $cfg['password'];
            $mail->Port = (int) $cfg['port'];
            $secure = $cfg['secure'] ?? 'tls';
            if ($secure === 'tls') {
                $mail->SMTPSecure = \PHPMailer\PHPMailer\PHPMailer::ENCRYPTION_STARTTLS;
            } elseif ($secure === 'ssl') {
                $mail->SMTPSecure = \PHPMailer\PHPMailer\PHPMailer::ENCRYPTION_SMTPS;
            } else {
                $mail->SMTPAutoTLS = false;
            }
            $mail->CharSet = 'UTF-8';
            $mail->Timeout = 45;
            $mail->SMTPOptions = [
                'ssl' => [
                    'verify_peer'       => true,
                    'verify_peer_name'  => true,
                    'allow_self_signed' => false,
                ],
            ];
            $mail->setFrom($fromAddress, $fromLabel);
            foreach (array_map('trim', explode(',', $toList)) as $addr) {
                if ($addr !== '') {
                    $mail->addAddress($addr);
                }
            }
            if ($replyTo !== null && $replyTo !== '') {
                $mail->addReplyTo($replyTo);
            }
            $mail->Subject = $subject;
            $mail->Body = $bodyPlain;
            $mail->isHTML(false);
            $mail->send();
            return ['ok' => true];
        } catch (\Throwable $e) {
            error_log('send-quote.php SMTP error: ' . $e->getMessage());
            return ['ok' => false, 'error' => $e->getMessage()];
        }
    }

    error_log('send-quote.php: smtp-config.php not found; using mail() (often does not deliver on shared hosting — add smtp-config.php).');

    $headers  = "MIME-Version: 1.0\r\n";
    $headers .= "Content-Type: text/plain; charset=UTF-8\r\n";
    $headers .= 'From: ' . $fromLabel . ' <' . $fromAddress . ">\r\n";
    if ($replyTo !== null && $replyTo !== '') {
        $headers .= 'Reply-To: ' . $replyTo . "\r\n";
    }
    $extraParams = '-f' . $fromAddress;
    $encodedSubject = '=?UTF-8?B?' . base64_encode($subject) . '?=';
    $ok = @mail($toList, $encodedSubject, $bodyPlain, $headers, $extraParams);
    if (!$ok) {
        return ['ok' => false, 'error' => 'mail() returned false'];
    }
    return ['ok' => true];
}

// Honeypot (hidden field — bots often fill it)
if (field('company') !== '') {
    header('Location: /thank-you', true, 303);
    exit;
}

$routeKey = field('quote_route');
if ($routeKey === '' || !isset(ROUTES[$routeKey])) {
    header('Location: /quotes?form=invalid', true, 303);
    exit;
}
$route = ROUTES[$routeKey];
$errBase = $route['error_to'];

$first   = field('first_name');
$last    = field('last_name');
$phone   = field('phone');
$email   = field('email');
$address = field('address');
$city    = field('city');
$work    = field('type_of_work');
$details = field('details');
$assoc   = field('sales_associate');

if ($first === '' || $last === '' || $phone === '' || $address === '' || $city === '' || $work === '') {
    header('Location: ' . $errBase . '?form=incomplete', true, 303);
    exit;
}

if (strlen($details) > 8000) {
    $details = substr($details, 0, 8000) . "\n… (truncated)";
}

$lines = [
    "New quote request from the website",
    "------------------------",
    "Name:        $first $last",
    "Phone:       $phone",
    "Email:       " . ($email !== '' ? $email : '(not provided)'),
    "Address:     $address",
    "City:        $city",
    "Type of work: $work",
];
if ($assoc !== '') {
    $lines[] = "Sales associate (form): $assoc";
}
$lines[] = "------------------------";
$lines[] = "Details:";
$lines[] = $details !== '' ? $details : '(none)';
$lines[] = "------------------------";
$lines[] = "Submitted: " . gmdate('Y-m-d H:i:s') . ' UTC';
$lines[] = "IP: " . strip_header_injection($_SERVER['REMOTE_ADDR'] ?? 'unknown');

$body = implode("\n", $lines);
$body = str_replace("\r\n", "\n", $body);

$to = $route['to'];
if ($routeKey !== 'general') {
    $to .= ', ' . OFFICE_TO;
}
$subject = $route['subject'];

$reply = strip_header_injection($email);
$replyTo = ($reply !== '' && filter_var($reply, FILTER_VALIDATE_EMAIL)) ? $reply : null;

$leadPath = lead_storage_dir() . '/' . gmdate('Y-m-d\THis') . '_' . bin2hex(random_bytes(4)) . '.json';
$leadData = [
    'saved_at_utc'    => gmdate('c'),
    'route'           => $routeKey,
    'mail_to'         => $to,
    'subject'         => $subject,
    'first_name'      => $first,
    'last_name'       => $last,
    'phone'           => $phone,
    'email'           => $email,
    'address'         => $address,
    'city'            => $city,
    'type_of_work'    => $work,
    'details'         => $details,
    'sales_associate' => $assoc !== '' ? $assoc : null,
    'ip'              => strip_header_injection($_SERVER['REMOTE_ADDR'] ?? ''),
    'user_agent'      => substr((string) ($_SERVER['HTTP_USER_AGENT'] ?? ''), 0, 400),
    'email_ok'        => null,
    'email_error'     => null,
];
write_lead_file($leadPath, $leadData);

$result = send_quote_mail($to, $subject, $body, $fromAddress, $fromLabel, $replyTo);

$leadData['email_ok'] = $result['ok'];
$leadData['email_error'] = $result['ok'] ? null : ($result['error'] ?? 'unknown');
write_lead_file($leadPath, $leadData);

if ($result['ok']) {
    error_log('send-quote.php: email sent route=' . $routeKey . ' to=' . $to);
} else {
    error_log(
        'send-quote.php: EMAIL FAILED route=' . $routeKey . ' file=' . basename($leadPath)
        . ' err=' . ($result['error'] ?? '')
    );
}

$loc = '/thank-you' . $route['thank_qs'];
header('Location: ' . $loc, true, 303);
exit;
