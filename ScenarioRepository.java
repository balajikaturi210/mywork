package com.zbp.chasepay.stub;

import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Optional;

/**
 * Reads and writes the jpm_stub_scenario table. One row = what the stub does, and the complete JSON it answers
 * with, when a card ending in card_last4 reaches a step (AUTHORIZE or CAPTURE); card '*' is the default row. The stub reads the table on every request, so a changed row
 * takes effect at once and is shared by all pods.
 */
@Repository
@ConditionalOnProperty(name = "chase.stub.enabled", havingValue = "true", matchIfMissing = true)
public class ScenarioRepository {

    public enum Step { AUTHORIZE, CAPTURE, REFUND }

    /** AUTHORIZE: APPROVE | DECLINE | NONE;  CAPTURE: APPLY | NONE;  REFUND: APPLY | DECLINE | NONE */
    public enum Effect { APPROVE, DECLINE, APPLY, NONE }

    /** the card_last4 that holds the default (every other card) rows */
    public static final String DEFAULT_CARD = "*";

    /**
     * one table row. responseJson is the COMPLETE response body (with ${placeholders}); null = use the default row's.
     */
    public record Scenario(String cardLast4, Step step, Effect effect, int httpStatus, int approvedPercent,
                           int delayMs, String responseJson, String note) {

        public Scenario {
            if (cardLast4 == null || !(cardLast4.equals(DEFAULT_CARD) || cardLast4.matches("\\d{4}"))) {
                throw new IllegalArgumentException("card_last4 must be 4 digits (or * for the default row)");
            }
            if (step == null || effect == null) {
                throw new IllegalArgumentException("step (AUTHORIZE|CAPTURE|REFUND) and effect are required");
            }
            boolean ok = switch (step) {
                case AUTHORIZE -> effect == Effect.APPROVE || effect == Effect.DECLINE || effect == Effect.NONE;
                case CAPTURE -> effect == Effect.APPLY || effect == Effect.NONE;
                case REFUND -> effect == Effect.APPLY || effect == Effect.DECLINE || effect == Effect.NONE;
            };
            if (!ok) {
                throw new IllegalArgumentException(switch (step) {
                    case AUTHORIZE -> "effect for AUTHORIZE must be APPROVE, DECLINE or NONE";
                    case CAPTURE -> "effect for CAPTURE must be APPLY or NONE";
                    case REFUND -> "effect for REFUND must be APPLY, DECLINE or NONE";
                });
            }
            if (httpStatus < 100 || httpStatus > 599) {
                throw new IllegalArgumentException("httpStatus must be 100-599");
            }
            if (approvedPercent < 1 || approvedPercent > 100) {
                throw new IllegalArgumentException("approvedPercent must be 1-100");
            }
            if (delayMs < 0 || delayMs > 60000) {
                throw new IllegalArgumentException("delayMs must be 0-60000");
            }
            if (responseJson != null && !responseJson.isBlank()) {
                String t = responseJson.strip();
                if (!t.startsWith("{") || !t.endsWith("}")) {
                    throw new IllegalArgumentException("responseJson must be a JSON object ({ ... })");
                }
            } else if (effect == Effect.DECLINE || effect == Effect.NONE || httpStatus >= 400) {
                throw new IllegalArgumentException("responseJson is required for DECLINE, NONE and error rows");
            }
        }
    }

    private static final String COLUMNS = """
            card_last4, step, effect, http_status, approved_percent, delay_ms, response_json, note
            """;

    private final JdbcTemplate jdbcTemplate;

    // NOTE: with a single DataSource remove @Qualifier (Boot's default bean is named "jdbcTemplate").
    public ScenarioRepository(@Qualifier("postgresJdbcTemplate") JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }

    /** the scenario for a card at a step, or empty = normal approval */
    public Optional<Scenario> find(String cardLast4, Step step) {

        String sql = "SELECT " + COLUMNS + " FROM jpm_stub_scenario WHERE card_last4 = ? AND step = ?";

        List<Scenario> rows = jdbcTemplate.query(sql, (rs, rowNum) -> map(rs), cardLast4, step.name());
        return rows.isEmpty() ? Optional.empty() : Optional.of(rows.get(0));
    }

    public List<Scenario> findAll() {

        String sql = "SELECT " + COLUMNS + " FROM jpm_stub_scenario ORDER BY card_last4, step";

        return jdbcTemplate.query(sql, (rs, rowNum) -> map(rs));
    }

    /** insert the row, or replace it when the card/step is already there */
    @Transactional
    public void upsert(Scenario s) {

        String updateSql = """
                UPDATE jpm_stub_scenario
                SET effect = ?,
                    http_status = ?,
                    approved_percent = ?,
                    delay_ms = ?,
                    response_json = ?,
                    note = ?,
                    updated_at = CURRENT_TIMESTAMP
                WHERE card_last4 = ?
                  AND step = ?
                """;

        int updated = jdbcTemplate.update(updateSql,
                s.effect().name(), s.httpStatus(), s.approvedPercent(), s.delayMs(), s.responseJson(), s.note(),
                s.cardLast4(), s.step().name());

        if (updated == 0) {
            String insertSql = """
                    INSERT INTO jpm_stub_scenario (
                        card_last4, step, effect, http_status, approved_percent, delay_ms, response_json, note,
                        updated_at
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
                    """;

            jdbcTemplate.update(insertSql,
                    s.cardLast4(), s.step().name(), s.effect().name(), s.httpStatus(), s.approvedPercent(),
                    s.delayMs(), s.responseJson(), s.note());
        }
    }

    /** @return true if a row was removed */
    @Transactional
    public boolean delete(String cardLast4, Step step) {

        String sql = """
                DELETE FROM jpm_stub_scenario
                WHERE card_last4 = ?
                  AND step = ?
                """;

        return jdbcTemplate.update(sql, cardLast4, step.name()) > 0;
    }

    private static Scenario map(java.sql.ResultSet rs) throws java.sql.SQLException {
        return new Scenario(
                rs.getString("card_last4"),
                Step.valueOf(rs.getString("step")),
                Effect.valueOf(rs.getString("effect")),
                rs.getInt("http_status"),
                rs.getInt("approved_percent"),
                rs.getInt("delay_ms"),
                rs.getString("response_json"),
                rs.getString("note"));
    }
}
