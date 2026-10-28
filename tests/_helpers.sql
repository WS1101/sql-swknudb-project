\encoding UTF8
-- _helpers.sql : 테스트 공통 보조 함수 (각 테스트 파일이 BEGIN 직후 \ir 로 불러온다)
--   모두 임시 객체라 테스트 마지막 ROLLBACK과 함께 사라진다.
--   t_check(항목, 조건, 상세)              조건이 참이면 PASS
--   t_expect_error(항목, SQL, SQLSTATE)    SQL이 해당 SQLSTATE로 거부되면 PASS
--                                          SQLSTATE를 NULL로 주면 어떤 에러든 PASS
--   t_expect_ok(항목, SQL)                 SQL이 에러 없이 실행되면 PASS
--   자주 쓰는 SQLSTATE
--     23505 UNIQUE·PK 위반      23503 FK 위반         23514 CHECK 위반 (트리거도 이 코드 사용)
--     23502 NOT NULL 위반       23P01 EXCLUDE 위반    42501 권한 없음 (fn_assert_*)
--     P0001 업무 함수의 RAISE EXCEPTION (코드 지정 없음)

CREATE TEMP TABLE t_result (
    no      serial PRIMARY KEY,
    item    text    NOT NULL,
    pass    boolean NOT NULL,
    detail  text
) ON COMMIT DROP;

CREATE FUNCTION pg_temp.t_check(p_item text, p_ok boolean, p_detail text DEFAULT NULL)
RETURNS void AS $f$
BEGIN
    INSERT INTO t_result (item, pass, detail)
    VALUES (p_item, COALESCE(p_ok, false), p_detail);
END;
$f$ LANGUAGE plpgsql;

CREATE FUNCTION pg_temp.t_expect_error(p_item text, p_sql text, p_state text)
RETURNS void AS $f$
DECLARE
    v_state text;
    v_msg   text;
    v_con   text;
BEGIN
    BEGIN
        EXECUTE p_sql;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE,
                                v_msg   = MESSAGE_TEXT,
                                v_con   = CONSTRAINT_NAME;
        INSERT INTO t_result (item, pass, detail)
        VALUES (p_item,
                p_state IS NULL OR v_state = p_state,
                format('거부 [%s]%s %s',
                       v_state,
                       CASE WHEN COALESCE(v_con, '') <> '' THEN ' ' || v_con ELSE '' END,
                       v_msg)
                || CASE WHEN p_state IS NOT NULL AND v_state <> p_state
                        THEN format(' (기대 %s)', p_state) ELSE '' END);
        RETURN;
    END;
    INSERT INTO t_result (item, pass, detail)
    VALUES (p_item, false, '거부되지 않고 실행됨 (기대 ' || COALESCE(p_state, '에러') || ')');
END;
$f$ LANGUAGE plpgsql;

CREATE FUNCTION pg_temp.t_expect_ok(p_item text, p_sql text)
RETURNS void AS $f$
DECLARE
    v_state text;
    v_msg   text;
BEGIN
    BEGIN
        EXECUTE p_sql;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
        INSERT INTO t_result (item, pass, detail)
        VALUES (p_item, false, format('실패 [%s] %s', v_state, v_msg));
        RETURN;
    END;
    INSERT INTO t_result (item, pass, detail) VALUES (p_item, true, '정상 실행');
END;
$f$ LANGUAGE plpgsql;
