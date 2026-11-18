package com.zbp.chasepay.stub;

import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Optional;

/**
 * Reads and writes the jpm_stub_scenario table: ONE ROW PER CARD (last four digits); card '*' is the default row.
 * The row holds only what the request cannot supply: HTTP statuses (authorize / capture / refund) and the JSON fragments (responseStatus,
 * responseCode, responseMessage, ...) that are added to the request-based response. Read on every request.
 */
@Repository
@ConditionalOnProperty(name = "chase.stub.enabled", havingValue = "true", matchIfMissing = true)
public class ScenarioRepository {

    /** the card_last4 of the default row */
    public static final String DEFAULT_CARD = "*";

    /** authJson / captureJson / refundJson: a JSON object with the response fields not taken from the request; null = default row's */
    public record Scenario(String cardLast4, int authHttpStatus, String authJson, int approvedPercent,
                           int captureHttpStatus, String captureJson, int refundHttpStatus, String refundJson,
                           boolean lostResponse, int delayMs, String note) {

        public Scenario {
            if (cardLast4 == null || !(cardLast4.equals(DEFAULT_CARD) || cardLast4.matches("\\d{4}"))) {
                throw new IllegalArgumentException("card_last4 must be 4 digits (or * for the default row)");
            }
            if (authHttpStatus < 100 || authHttpStatus > 599 || captureHttpStatus < 100 || captureHttpStatus > 599
                    || refundHttpStatus < 100 || refundHttpStatus > 599) {
                throw new IllegalArgumentException("http status must be 100-599");
            }
            if (approvedPercent < 1 || approvedPercent > 100) {
                throw new IllegalArgumentException("approvedPercent must be 1-100");
            }
            if (delayMs < 0 || delayMs > 60000) {
                throw new IllegalArgumentException("delayMs must be 0-60000");
            }
            checkJson(authJson, "authJson");
            checkJson(captureJson, "captureJson");
            checkJson(refundJson, "refundJson");
            if (cardLast4.equals(DEFAULT_CARD) && (isBlank(authJson) || isBlank(captureJson) || isBlank(refundJson))) {
                throw new IllegalArgumentException("the default row needs authJson, captureJson and refundJson");
            }
            if (authHttpStatus >= 400 && isBlank(authJson)) {
                throw new IllegalArgumentException("authJson is required when authHttpStatus is an error");
            }
            if (captureHttpStatus >= 400 && isBlank(captureJson)) {
                throw new IllegalArgumentException("captureJson is required when captureHttpStatus is an error");
            }
            if (refundHttpStatus >= 400 && isBlank(refundJson)) {
                throw new IllegalArgumentException("refundJson is required when refundHttpStatus is an error");
            }
        }

        private static boolean isBlank(String s) {
            return s == null || s.isBlank();
        }

        private static void checkJson(String s, String name) {
            if (!isBlank(s) && !(s.strip().startsWith("{") && s.strip().endsWith("}"))) {
                throw new IllegalArgumentException(name + " must be a JSON object ({ ... })");
            }
        }
    }

    private static final String COLUMNS = """
            card_last4, auth_http_status, auth_json, approved_percent, capture_http_status, capture_json,
            refund_http_status, refund_json, lost_response, delay_ms, note
            """;

    private final JdbcTemplate jdbcTemplate;

    // NOTE: with a single DataSource remove @Qualifier (Boot's default bean is named "jdbcTemplate").
    public ScenarioRepository(@Qualifier("postgresJdbcTemplate") JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }

    /** the row for a card, or empty */
    public Optional<Scenario> find(String cardLast4) {

        String sql = "SELECT " + COLUMNS + " FROM jpm_stub_scenario WHERE card_last4 = ?";

        List<Scenario> rows = jdbcTemplate.query(sql, (rs, rowNum) -> map(rs), cardLast4);
        return rows.isEmpty() ? Optional.empty() : Optional.of(rows.get(0));
    }

    public List<Scenario> findAll() {

        String sql = "SELECT " + COLUMNS + " FROM jpm_stub_scenario ORDER BY card_last4";

        return jdbcTemplate.query(sql, (rs, rowNum) -> map(rs));
    }

    /** insert the row, or replace it when the card is already there */
    @Transactional
    public void upsert(Scenario s) {

        String updateSql = """
                UPDATE jpm_stub_scenario
                SET auth_http_status = ?,
                    auth_json = ?,
                    approved_percent = ?,
                    capture_http_status = ?,
                    capture_json = ?,
                    refund_http_status = ?,
                    refund_json = ?,
                    lost_response = ?,
                    delay_ms = ?,
                    note = ?,
                    updated_at = CURRENT_TIMESTAMP
                WHERE card_last4 = ?
                """;

        int updated = jdbcTemplate.update(updateSql,
                s.authHttpStatus(), s.authJson(), s.approvedPercent(), s.captureHttpStatus(), s.captureJson(),
                s.refundHttpStatus(), s.refundJson(), s.lostResponse() ? "Y" : "N", s.delayMs(), s.note(), s.cardLast4());

        if (updated == 0) {
            String insertSql = """
                    INSERT INTO jpm_stub_scenario (
                        card_last4, auth_http_status, auth_json, approved_percent, capture_http_status,
                        capture_json, refund_http_status, refund_json, lost_response, delay_ms, note, updated_at
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
                    """;

            jdbcTemplate.update(insertSql,
                    s.cardLast4(), s.authHttpStatus(), s.authJson(), s.approvedPercent(), s.captureHttpStatus(),
                    s.captureJson(), s.refundHttpStatus(), s.refundJson(), s.lostResponse() ? "Y" : "N", s.delayMs(),
                    s.note());
        }
    }

    /** @return true if a row was removed */
    @Transactional
    public boolean delete(String cardLast4) {

        String sql = """
                DELETE FROM jpm_stub_scenario
                WHERE card_last4 = ?
                """;

        return jdbcTemplate.update(sql, cardLast4) > 0;
    }

    private static Scenario map(java.sql.ResultSet rs) throws java.sql.SQLException {
        return new Scenario(
                rs.getString("card_last4"),
                rs.getInt("auth_http_status"),
                rs.getString("auth_json"),
                rs.getInt("approved_percent"),
                rs.getInt("capture_http_status"),
                rs.getString("capture_json"),
                rs.getInt("refund_http_status"),
                rs.getString("refund_json"),
                "Y".equals(rs.getString("lost_response")),
                rs.getInt("delay_ms"),
                rs.getString("note"));
    }
}
