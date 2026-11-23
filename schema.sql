-- Drives the JPMC stub. One row = "when a card ending in card_last4 reaches this step, do this and answer with this JSON".
-- card_last4 = '*' is the DEFAULT row used for every card that has no row of its own (do not delete it).
-- response_json is the COMPLETE response body. ${name} placeholders are filled in by the stub:
--   transactionId requestId paymentRequestId authorizationId approvalCode now captureTime
--   transactionState paymentRequestStatus authStatusCode captureMethod currency
--   amount approvedAmount requestedAmount captureAmount totalAuthorizedAmount remainingAuthAmount remainingRefundableAmount
--   isAmountFinal cardType cardTypeName maskedAccountNumber
-- Numbers/booleans are unquoted ("amount": ${approvedAmount}); strings are quoted ("requestId": "${requestId}").
-- effect: AUTHORIZE -> APPROVE (record an authorization) | DECLINE (record a closed, denied one) | NONE (record nothing)
--         CAPTURE   -> APPLY   (apply the capture)      | NONE (apply nothing)
--         REFUND    -> APPLY   (refund the money)       | DECLINE (issuer declines the refund) | NONE (refund nothing)
-- REFUND templates can also use: transactionReferenceId remainingRefundableAmount hostReferenceId transactionDate
--   (transactionId is the refund's own id, amount the refunded amount). A refund is looked up by the ORIGINAL payment's card.
--   http_status >= 400 with APPROVE/APPLY = "lost response": the work is recorded/applied, the caller sees the error.
--   response_json NULL = use the default row's JSON.
-- Runs at every start (spring.sql.init.mode=always); safe to repeat; never overwrites rows you edited.
-- If you already deployed an older version (the step CHECK changed to allow REFUND) run:  DROP TABLE jpm_stub_scenario;  once.
CREATE TABLE IF NOT EXISTS jpm_stub_scenario (
    card_last4       VARCHAR(4)   NOT NULL,
    step             VARCHAR(10)  NOT NULL CHECK (step IN ('AUTHORIZE','CAPTURE','REFUND')),
    effect           VARCHAR(10)  NOT NULL CHECK (effect IN ('APPROVE','DECLINE','APPLY','NONE')),
    http_status      INTEGER      NOT NULL DEFAULT 200 CHECK (http_status BETWEEN 100 AND 599),
    approved_percent INTEGER      NOT NULL DEFAULT 100 CHECK (approved_percent BETWEEN 1 AND 100),
    delay_ms         INTEGER      NOT NULL DEFAULT 0 CHECK (delay_ms BETWEEN 0 AND 60000),
    response_json    TEXT,
    note             VARCHAR(200),
    updated_at       TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (card_last4, step)
);

INSERT INTO jpm_stub_scenario (card_last4, step, effect, http_status, approved_percent, delay_ms, response_json, note)
SELECT '*', 'AUTHORIZE', 'APPROVE', 200, 100, 0, '{
  "transactionId": "${transactionId}",
  "requestId": "${requestId}",
  "transactionState": "${transactionState}",
  "responseStatus": "SUCCESS",
  "responseCode": "APPROVED",
  "responseMessage": "Transaction approved by Issuer",
  "captureMethod": "${captureMethod}",
  "isVoid": false,
  "approvalCode": "${approvalCode}",
  "amount": ${approvedAmount},
  "currency": "${currency}",
  "remainingAuthAmount": ${remainingAuthAmount},
  "remainingRefundableAmount": ${remainingRefundableAmount},
  "paymentMethodType": {
    "card": {
      "cardType": "${cardType}",
      "cardTypeName": "${cardTypeName}",
      "maskedAccountNumber": "${maskedAccountNumber}"
    }
  },
  "merchant": { "merchantId": "stub-merchant", "merchantCategoryCode": "5999" },
  "paymentRequest": {
    "paymentRequestId": "${paymentRequestId}",
    "paymentRequestStatus": "${paymentRequestStatus}",
    "authorizations": [
      {
        "authorizationId": "${authorizationId}",
        "amount": ${approvedAmount},
        "transactionStatusCode": "${authStatusCode}",
        "authorizationType": "AUTHORIZATION"
      }
    ]
  }
}', 'DEFAULT for every card: normal approval (used when no card row exists)'
WHERE NOT EXISTS (SELECT 1 FROM jpm_stub_scenario WHERE card_last4 = '*' AND step = 'AUTHORIZE');

INSERT INTO jpm_stub_scenario (card_last4, step, effect, http_status, approved_percent, delay_ms, response_json, note)
SELECT '*', 'CAPTURE', 'APPLY', 200, 100, 0, '{
  "transactionId": "${transactionId}",
  "requestId": "${requestId}",
  "transactionState": "${transactionState}",
  "responseStatus": "SUCCESS",
  "responseCode": "ACCEPTED",
  "responseMessage": "Transaction accepted",
  "captureMethod": "${captureMethod}",
  "isVoid": false,
  "approvalCode": "${approvalCode}",
  "amount": ${captureAmount},
  "currency": "${currency}",
  "isAmountFinal": ${isAmountFinal},
  "totalAuthorizedAmount": ${totalAuthorizedAmount},
  "remainingAuthAmount": ${remainingAuthAmount},
  "remainingRefundableAmount": ${remainingRefundableAmount},
  "paymentMethodType": {
    "card": {
      "cardType": "${cardType}",
      "cardTypeName": "${cardTypeName}",
      "maskedAccountNumber": "${maskedAccountNumber}"
    }
  },
  "merchant": { "merchantId": "stub-merchant", "merchantCategoryCode": "5999" },
  "paymentRequest": {
    "paymentRequestId": "${paymentRequestId}",
    "paymentRequestStatus": "${paymentRequestStatus}",
    "authorizations": [
      {
        "authorizationId": "${authorizationId}",
        "amount": ${approvedAmount},
        "transactionStatusCode": "${authStatusCode}",
        "authorizationType": "AUTHORIZATION"
      }
    ]
  }
}', 'DEFAULT for every capture: ACCEPTED'
WHERE NOT EXISTS (SELECT 1 FROM jpm_stub_scenario WHERE card_last4 = '*' AND step = 'CAPTURE');

INSERT INTO jpm_stub_scenario (card_last4, step, effect, http_status, approved_percent, delay_ms, response_json, note)
SELECT '0002', 'AUTHORIZE', 'DECLINE', 200, 100, 0, '{
  "transactionId": "${transactionId}",
  "requestId": "${requestId}",
  "transactionState": "CLOSED",
  "responseStatus": "DENIED",
  "responseCode": "DECLINED",
  "responseMessage": "Transaction declined by Issuer",
  "captureMethod": "${captureMethod}",
  "isVoid": false,
  "amount": 0,
  "currency": "${currency}",
  "remainingAuthAmount": 0,
  "remainingRefundableAmount": 0,
  "paymentMethodType": {
    "card": {
      "cardType": "${cardType}",
      "cardTypeName": "${cardTypeName}",
      "maskedAccountNumber": "${maskedAccountNumber}"
    }
  },
  "merchant": { "merchantId": "stub-merchant", "merchantCategoryCode": "5999" },
  "paymentRequest": { "paymentRequestId": "${paymentRequestId}", "paymentRequestStatus": "CLOSED" }
}', 'Generic decline'
WHERE NOT EXISTS (SELECT 1 FROM jpm_stub_scenario WHERE card_last4 = '0002' AND step = 'AUTHORIZE');

INSERT INTO jpm_stub_scenario (card_last4, step, effect, http_status, approved_percent, delay_ms, response_json, note)
SELECT '0051', 'AUTHORIZE', 'DECLINE', 200, 100, 0, '{
  "transactionId": "${transactionId}",
  "requestId": "${requestId}",
  "transactionState": "CLOSED",
  "responseStatus": "DENIED",
  "responseCode": "INSUFFICIENT_FUNDS",
  "responseMessage": "Insufficient funds",
  "captureMethod": "${captureMethod}",
  "isVoid": false,
  "amount": 0,
  "currency": "${currency}",
  "remainingAuthAmount": 0,
  "remainingRefundableAmount": 0,
  "paymentMethodType": {
    "card": {
      "cardType": "${cardType}",
      "cardTypeName": "${cardTypeName}",
      "maskedAccountNumber": "${maskedAccountNumber}"
    }
  },
  "merchant": { "merchantId": "stub-merchant", "merchantCategoryCode": "5999" },
  "paymentRequest": { "paymentRequestId": "${paymentRequestId}", "paymentRequestStatus": "CLOSED" }
}', 'Decline: no funds'
WHERE NOT EXISTS (SELECT 1 FROM jpm_stub_scenario WHERE card_last4 = '0051' AND step = 'AUTHORIZE');

INSERT INTO jpm_stub_scenario (card_last4, step, effect, http_status, approved_percent, delay_ms, response_json, note)
SELECT '0054', 'AUTHORIZE', 'DECLINE', 200, 100, 0, '{
  "transactionId": "${transactionId}",
  "requestId": "${requestId}",
  "transactionState": "CLOSED",
  "responseStatus": "DENIED",
  "responseCode": "CARD_EXPIRED",
  "responseMessage": "Card expired",
  "captureMethod": "${captureMethod}",
  "isVoid": false,
  "amount": 0,
  "currency": "${currency}",
  "remainingAuthAmount": 0,
  "remainingRefundableAmount": 0,
  "paymentMethodType": {
    "card": {
      "cardType": "${cardType}",
      "cardTypeName": "${cardTypeName}",
      "maskedAccountNumber": "${maskedAccountNumber}"
    }
  },
  "merchant": { "merchantId": "stub-merchant", "merchantCategoryCode": "5999" },
  "paymentRequest": { "paymentRequestId": "${paymentRequestId}", "paymentRequestStatus": "CLOSED" }
}', 'Decline: expired card'
WHERE NOT EXISTS (SELECT 1 FROM jpm_stub_scenario WHERE card_last4 = '0054' AND step = 'AUTHORIZE');

INSERT INTO jpm_stub_scenario (card_last4, step, effect, http_status, approved_percent, delay_ms, response_json, note)
SELECT '0036', 'AUTHORIZE', 'APPROVE', 200, 50, 0, '{
  "transactionId": "${transactionId}",
  "requestId": "${requestId}",
  "transactionState": "${transactionState}",
  "responseStatus": "SUCCESS",
  "responseCode": "PARTIAL_APPROVAL",
  "responseMessage": "Transaction partially approved by issuer",
  "captureMethod": "${captureMethod}",
  "isVoid": false,
  "approvalCode": "${approvalCode}",
  "amount": ${approvedAmount},
  "currency": "${currency}",
  "remainingAuthAmount": ${remainingAuthAmount},
  "remainingRefundableAmount": ${remainingRefundableAmount},
  "partialAuthorization": true,
  "paymentMethodType": {
    "card": {
      "cardType": "${cardType}",
      "cardTypeName": "${cardTypeName}",
      "maskedAccountNumber": "${maskedAccountNumber}"
    }
  },
  "merchant": { "merchantId": "stub-merchant", "merchantCategoryCode": "5999" },
  "paymentRequest": {
    "paymentRequestId": "${paymentRequestId}",
    "paymentRequestStatus": "${paymentRequestStatus}",
    "authorizations": [
      {
        "authorizationId": "${authorizationId}",
        "amount": ${approvedAmount},
        "transactionStatusCode": "${authStatusCode}",
        "authorizationType": "AUTHORIZATION"
      }
    ]
  }
}', 'Approves 50 percent, needs partialAuthorizationSupport=SUPPORTED, else the default row applies'
WHERE NOT EXISTS (SELECT 1 FROM jpm_stub_scenario WHERE card_last4 = '0036' AND step = 'AUTHORIZE');

INSERT INTO jpm_stub_scenario (card_last4, step, effect, http_status, approved_percent, delay_ms, response_json, note)
SELECT '0119', 'AUTHORIZE', 'APPROVE', 500, 100, 0, '{
  "responseStatus": "ERROR",
  "responseCode": "SERVER_ERROR",
  "responseMessage": "simulated lost response (transaction was recorded)",
  "requestId": "${requestId}"
}', 'Recorded, caller sees HTTP 500 (tests recovery by request-id)'
WHERE NOT EXISTS (SELECT 1 FROM jpm_stub_scenario WHERE card_last4 = '0119' AND step = 'AUTHORIZE');

INSERT INTO jpm_stub_scenario (card_last4, step, effect, http_status, approved_percent, delay_ms, response_json, note)
SELECT '0408', 'AUTHORIZE', 'NONE', 504, 100, 0, '{
  "responseStatus": "ERROR",
  "responseCode": "TIMEOUT",
  "responseMessage": "simulated timeout (nothing recorded)",
  "requestId": "${requestId}"
}', 'Gateway timeout, nothing recorded'
WHERE NOT EXISTS (SELECT 1 FROM jpm_stub_scenario WHERE card_last4 = '0408' AND step = 'AUTHORIZE');

INSERT INTO jpm_stub_scenario (card_last4, step, effect, http_status, approved_percent, delay_ms, response_json, note)
SELECT '0503', 'AUTHORIZE', 'NONE', 503, 100, 0, '{
  "responseStatus": "ERROR",
  "responseCode": "SERVICE_UNAVAILABLE",
  "responseMessage": "simulated service unavailable (nothing recorded)",
  "requestId": "${requestId}"
}', 'HTTP 503, nothing recorded'
WHERE NOT EXISTS (SELECT 1 FROM jpm_stub_scenario WHERE card_last4 = '0503' AND step = 'AUTHORIZE');

INSERT INTO jpm_stub_scenario (card_last4, step, effect, http_status, approved_percent, delay_ms, response_json, note)
SELECT '0900', 'AUTHORIZE', 'APPROVE', 200, 100, 5000, NULL, 'Normal approval after a 5 second delay (json empty = default row)'
WHERE NOT EXISTS (SELECT 1 FROM jpm_stub_scenario WHERE card_last4 = '0900' AND step = 'AUTHORIZE');

INSERT INTO jpm_stub_scenario (card_last4, step, effect, http_status, approved_percent, delay_ms, response_json, note)
SELECT '0777', 'CAPTURE', 'NONE', 400, 100, 0, '{
  "responseStatus": "ERROR",
  "responseCode": "VALIDATION_ERROR",
  "responseMessage": "capture rejected (stub scenario)",
  "requestId": "${requestId}"
}', 'Capture refused, authorization stays usable'
WHERE NOT EXISTS (SELECT 1 FROM jpm_stub_scenario WHERE card_last4 = '0777' AND step = 'CAPTURE');

INSERT INTO jpm_stub_scenario (card_last4, step, effect, http_status, approved_percent, delay_ms, response_json, note)
SELECT '0778', 'CAPTURE', 'APPLY', 500, 100, 0, '{
  "responseStatus": "ERROR",
  "responseCode": "SERVER_ERROR",
  "responseMessage": "simulated lost response (capture was applied)",
  "requestId": "${requestId}"
}', 'Capture applied, caller sees HTTP 500'
WHERE NOT EXISTS (SELECT 1 FROM jpm_stub_scenario WHERE card_last4 = '0778' AND step = 'CAPTURE');

INSERT INTO jpm_stub_scenario (card_last4, step, effect, http_status, approved_percent, delay_ms, response_json, note)
SELECT '*', 'REFUND', 'APPLY', 200, 100, 0, '{
  "transactionId": "${transactionId}",
  "requestId": "${requestId}",
  "transactionState": "AUTHORIZED",
  "transactionReferenceId": "${transactionReferenceId}",
  "responseStatus": "SUCCESS",
  "responseCode": "APPROVED",
  "responseMessage": "Transaction approved by Issuer",
  "amount": ${amount},
  "currency": "${currency}",
  "remainingRefundableAmount": ${remainingRefundableAmount},
  "approvalCode": "${approvalCode}",
  "hostReferenceId": "${hostReferenceId}",
  "transactionDate": "${transactionDate}",
  "merchant": { "merchantId": "stub-merchant", "merchantCategoryCode": "5999" },
  "paymentMethodType": {
    "card": {
      "cardType": "${cardType}",
      "cardTypeName": "${cardTypeName}",
      "maskedAccountNumber": "${maskedAccountNumber}"
    }
  },
  "paymentRequest": {
    "paymentRequestId": "${paymentRequestId}",
    "paymentRequestStatus": "CLOSED",
    "refunds": [
      { "refundId": "${transactionId}", "amount": ${amount}, "transactionStatusCode": "CLOSED" }
    ]
  }
}', 'DEFAULT for every refund: approved'
WHERE NOT EXISTS (SELECT 1 FROM jpm_stub_scenario WHERE card_last4 = '*' AND step = 'REFUND');

INSERT INTO jpm_stub_scenario (card_last4, step, effect, http_status, approved_percent, delay_ms, response_json, note)
SELECT '0881', 'REFUND', 'DECLINE', 200, 100, 0, '{
  "transactionId": "${transactionId}",
  "requestId": "${requestId}",
  "transactionState": "CLOSED",
  "transactionReferenceId": "${transactionReferenceId}",
  "responseStatus": "DENIED",
  "responseCode": "DECLINED",
  "responseMessage": "Refund declined by Issuer",
  "amount": 0,
  "currency": "${currency}",
  "remainingRefundableAmount": ${remainingRefundableAmount}
}', 'Refund declined, nothing refunded'
WHERE NOT EXISTS (SELECT 1 FROM jpm_stub_scenario WHERE card_last4 = '0881' AND step = 'REFUND');

INSERT INTO jpm_stub_scenario (card_last4, step, effect, http_status, approved_percent, delay_ms, response_json, note)
SELECT '0882', 'REFUND', 'NONE', 504, 100, 0, '{
  "responseStatus": "ERROR",
  "responseCode": "TIMEOUT",
  "responseMessage": "simulated refund timeout (nothing refunded)",
  "requestId": "${requestId}"
}', 'Refund times out, nothing refunded'
WHERE NOT EXISTS (SELECT 1 FROM jpm_stub_scenario WHERE card_last4 = '0882' AND step = 'REFUND');

INSERT INTO jpm_stub_scenario (card_last4, step, effect, http_status, approved_percent, delay_ms, response_json, note)
SELECT '0883', 'REFUND', 'APPLY', 500, 100, 0, '{
  "responseStatus": "ERROR",
  "responseCode": "SERVER_ERROR",
  "responseMessage": "simulated lost response (refund was applied)",
  "requestId": "${requestId}"
}', 'Refund applied, caller sees HTTP 500'
WHERE NOT EXISTS (SELECT 1 FROM jpm_stub_scenario WHERE card_last4 = '0883' AND step = 'REFUND');
