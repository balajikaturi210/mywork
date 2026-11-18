-- Drives the JPMC stub. ONE ROW PER CARD (last four digits). card_last4 = '*' is the default row for every other card.
--
-- The stub builds each response in two parts:
--   1. fields taken from the REQUEST / the stored transaction: transactionId, requestId, transactionState, captureMethod,
--      amount, currency, remaining amounts, card type and masked number, merchantId, paymentRequest (with captures and
--      refunds) ...
--   2. the remaining fields from the JSON stored here (auth_json / capture_json / refund_json): responseStatus,
--      responseCode, responseMessage and anything else you want to add (partialAuthorization, hostMessage ...).
-- If a field name appears in the stored JSON it REPLACES the request-based one (e.g. put "amount": 500 to force it).
-- auth_json / capture_json / refund_json NULL = use the default row's JSON.
-- For a refund the card is the card of the ORIGINAL payment (referenced refund) or the card in the request (standalone).
--
--   *_http_status    : status sent to the caller (400+ = error; the stored JSON is the error body)
--   approved_percent : below 100 = partial approval, only when the request sends partialAuthorizationSupport=SUPPORTED
--   lost_response    : 'Y' = the work is done (authorization recorded / capture or refund applied) even though an error is returned
--   delay_ms         : wait before answering
-- A stored responseStatus of DENIED makes an authorization or a refund a decline (nothing reserved / refunded).
-- Runs at every start (spring.sql.init.mode=always); safe to repeat; never overwrites rows you edited.
-- An older table (v5, without refund columns) is upgraded in place by the ALTER statements below.
CREATE TABLE IF NOT EXISTS jpm_stub_scenario (
    card_last4          VARCHAR(4)  NOT NULL PRIMARY KEY,
    auth_http_status    INTEGER     NOT NULL DEFAULT 200 CHECK (auth_http_status BETWEEN 100 AND 599),
    auth_json           TEXT,
    approved_percent    INTEGER     NOT NULL DEFAULT 100 CHECK (approved_percent BETWEEN 1 AND 100),
    capture_http_status INTEGER     NOT NULL DEFAULT 200 CHECK (capture_http_status BETWEEN 100 AND 599),
    capture_json        TEXT,
    refund_http_status  INTEGER     NOT NULL DEFAULT 200 CHECK (refund_http_status BETWEEN 100 AND 599),
    refund_json         TEXT,
    lost_response       CHAR(1)     NOT NULL DEFAULT 'N' CHECK (lost_response IN ('Y','N')),
    delay_ms            INTEGER     NOT NULL DEFAULT 0 CHECK (delay_ms BETWEEN 0 AND 60000),
    note                VARCHAR(200),
    updated_at          TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE jpm_stub_scenario ADD COLUMN IF NOT EXISTS refund_http_status INTEGER NOT NULL DEFAULT 200;
ALTER TABLE jpm_stub_scenario ADD COLUMN IF NOT EXISTS refund_json TEXT;

INSERT INTO jpm_stub_scenario (card_last4, auth_http_status, auth_json, approved_percent, capture_http_status, capture_json, refund_http_status, refund_json, lost_response, delay_ms, note)
SELECT '*', 200, '{"responseStatus": "SUCCESS", "responseCode": "APPROVED", "responseMessage": "Transaction approved by Issuer"}', 100, 200, '{"responseStatus": "SUCCESS", "responseCode": "ACCEPTED", "responseMessage": "Transaction accepted"}', 200, '{"responseStatus": "SUCCESS", "responseCode": "APPROVED", "responseMessage": "Transaction approved by Issuer"}', 'N', 0, 'DEFAULT for every card without its own row (keep it)'
WHERE NOT EXISTS (SELECT 1 FROM jpm_stub_scenario WHERE card_last4 = '*');

INSERT INTO jpm_stub_scenario (card_last4, auth_http_status, auth_json, approved_percent, capture_http_status, capture_json, refund_http_status, refund_json, lost_response, delay_ms, note)
SELECT '0002', 200, '{"responseStatus": "DENIED", "responseCode": "DECLINED", "responseMessage": "Transaction declined by Issuer"}', 100, 200, NULL, 200, NULL, 'N', 0, 'Generic decline'
WHERE NOT EXISTS (SELECT 1 FROM jpm_stub_scenario WHERE card_last4 = '0002');

INSERT INTO jpm_stub_scenario (card_last4, auth_http_status, auth_json, approved_percent, capture_http_status, capture_json, refund_http_status, refund_json, lost_response, delay_ms, note)
SELECT '0051', 200, '{"responseStatus": "DENIED", "responseCode": "INSUFFICIENT_FUNDS", "responseMessage": "Insufficient funds"}', 100, 200, NULL, 200, NULL, 'N', 0, 'Decline: no funds'
WHERE NOT EXISTS (SELECT 1 FROM jpm_stub_scenario WHERE card_last4 = '0051');

INSERT INTO jpm_stub_scenario (card_last4, auth_http_status, auth_json, approved_percent, capture_http_status, capture_json, refund_http_status, refund_json, lost_response, delay_ms, note)
SELECT '0054', 200, '{"responseStatus": "DENIED", "responseCode": "CARD_EXPIRED", "responseMessage": "Card expired"}', 100, 200, NULL, 200, NULL, 'N', 0, 'Decline: expired card'
WHERE NOT EXISTS (SELECT 1 FROM jpm_stub_scenario WHERE card_last4 = '0054');

INSERT INTO jpm_stub_scenario (card_last4, auth_http_status, auth_json, approved_percent, capture_http_status, capture_json, refund_http_status, refund_json, lost_response, delay_ms, note)
SELECT '0036', 200, '{"responseStatus": "SUCCESS", "responseCode": "PARTIAL_APPROVAL", "responseMessage": "Transaction partially approved by issuer", "partialAuthorization": true}', 50, 200, NULL, 200, NULL, 'N', 0, 'Approves 50 percent when the request sends partialAuthorizationSupport=SUPPORTED'
WHERE NOT EXISTS (SELECT 1 FROM jpm_stub_scenario WHERE card_last4 = '0036');

INSERT INTO jpm_stub_scenario (card_last4, auth_http_status, auth_json, approved_percent, capture_http_status, capture_json, refund_http_status, refund_json, lost_response, delay_ms, note)
SELECT '0119', 500, '{"responseStatus": "ERROR", "responseCode": "SERVER_ERROR", "responseMessage": "simulated lost response (transaction was recorded)"}', 100, 200, NULL, 200, NULL, 'Y', 0, 'Authorization recorded, caller sees HTTP 500 (recovery by request-id)'
WHERE NOT EXISTS (SELECT 1 FROM jpm_stub_scenario WHERE card_last4 = '0119');

INSERT INTO jpm_stub_scenario (card_last4, auth_http_status, auth_json, approved_percent, capture_http_status, capture_json, refund_http_status, refund_json, lost_response, delay_ms, note)
SELECT '0408', 504, '{"responseStatus": "ERROR", "responseCode": "TIMEOUT", "responseMessage": "simulated timeout (nothing recorded)"}', 100, 200, NULL, 200, NULL, 'N', 0, 'Gateway timeout, nothing recorded'
WHERE NOT EXISTS (SELECT 1 FROM jpm_stub_scenario WHERE card_last4 = '0408');

INSERT INTO jpm_stub_scenario (card_last4, auth_http_status, auth_json, approved_percent, capture_http_status, capture_json, refund_http_status, refund_json, lost_response, delay_ms, note)
SELECT '0503', 503, '{"responseStatus": "ERROR", "responseCode": "SERVICE_UNAVAILABLE", "responseMessage": "simulated service unavailable (nothing recorded)"}', 100, 200, NULL, 200, NULL, 'N', 0, 'HTTP 503, nothing recorded'
WHERE NOT EXISTS (SELECT 1 FROM jpm_stub_scenario WHERE card_last4 = '0503');

INSERT INTO jpm_stub_scenario (card_last4, auth_http_status, auth_json, approved_percent, capture_http_status, capture_json, refund_http_status, refund_json, lost_response, delay_ms, note)
SELECT '0900', 200, NULL, 100, 200, NULL, 200, NULL, 'N', 5000, 'Normal approval after a 5 second delay'
WHERE NOT EXISTS (SELECT 1 FROM jpm_stub_scenario WHERE card_last4 = '0900');

INSERT INTO jpm_stub_scenario (card_last4, auth_http_status, auth_json, approved_percent, capture_http_status, capture_json, refund_http_status, refund_json, lost_response, delay_ms, note)
SELECT '0777', 200, NULL, 100, 400, '{"responseStatus": "ERROR", "responseCode": "VALIDATION_ERROR", "responseMessage": "capture rejected (stub scenario)"}', 200, NULL, 'N', 0, 'Authorize fine, capture refused (authorization stays usable)'
WHERE NOT EXISTS (SELECT 1 FROM jpm_stub_scenario WHERE card_last4 = '0777');

INSERT INTO jpm_stub_scenario (card_last4, auth_http_status, auth_json, approved_percent, capture_http_status, capture_json, refund_http_status, refund_json, lost_response, delay_ms, note)
SELECT '0778', 200, NULL, 100, 500, '{"responseStatus": "ERROR", "responseCode": "SERVER_ERROR", "responseMessage": "simulated lost response (capture was applied)"}', 200, NULL, 'Y', 0, 'Authorize fine, capture applied but caller sees HTTP 500'
WHERE NOT EXISTS (SELECT 1 FROM jpm_stub_scenario WHERE card_last4 = '0778');

INSERT INTO jpm_stub_scenario (card_last4, auth_http_status, auth_json, approved_percent, capture_http_status, capture_json, refund_http_status, refund_json, lost_response, delay_ms, note)
SELECT '0881', 200, NULL, 100, 200, NULL, 200, '{"responseStatus": "DENIED", "responseCode": "DECLINED", "responseMessage": "Refund declined by Issuer"}', 'N', 0, 'Authorize and capture fine, refund declined'
WHERE NOT EXISTS (SELECT 1 FROM jpm_stub_scenario WHERE card_last4 = '0881');

INSERT INTO jpm_stub_scenario (card_last4, auth_http_status, auth_json, approved_percent, capture_http_status, capture_json, refund_http_status, refund_json, lost_response, delay_ms, note)
SELECT '0882', 200, NULL, 100, 200, NULL, 504, '{"responseStatus": "ERROR", "responseCode": "TIMEOUT", "responseMessage": "simulated refund timeout (nothing recorded)"}', 'N', 0, 'Refund times out, nothing recorded'
WHERE NOT EXISTS (SELECT 1 FROM jpm_stub_scenario WHERE card_last4 = '0882');

INSERT INTO jpm_stub_scenario (card_last4, auth_http_status, auth_json, approved_percent, capture_http_status, capture_json, refund_http_status, refund_json, lost_response, delay_ms, note)
SELECT '0883', 200, NULL, 100, 200, NULL, 500, '{"responseStatus": "ERROR", "responseCode": "SERVER_ERROR", "responseMessage": "simulated lost response (refund was applied)"}', 'Y', 0, 'Refund applied but caller sees HTTP 500'
WHERE NOT EXISTS (SELECT 1 FROM jpm_stub_scenario WHERE card_last4 = '0883');

-- a default row created by v5 has no refund JSON yet
UPDATE jpm_stub_scenario SET refund_json = '{"responseStatus": "SUCCESS", "responseCode": "APPROVED", "responseMessage": "Transaction approved by Issuer"}' WHERE card_last4 = '*' AND refund_json IS NULL;
