"""Shared fixtures for a dedicated *_test PostgreSQL database only."""
import os
from datetime import datetime, timedelta, timezone
import psycopg
from psycopg.rows import dict_row
import pytest

UTC=timezone.utc
AT=datetime(2025,10,1,6,tzinfo=UTC)
NORMAL=[5,4,3,4,5,2,4,3,5,4]

@pytest.fixture
def conn():
    dsn=os.environ.get('SURVEY_TEST_DATABASE_URL')
    if not dsn:
        pytest.skip('SURVEY_TEST_DATABASE_URL not configured: real DB test not run')
    c=psycopg.connect(dsn,row_factory=dict_row)
    if not c.info.dbname.endswith('_test'):
        c.close()
        pytest.fail('Integration tests require a separate database ending in _test')
    try:
        yield c
    finally:
        c.rollback()
        c.close()


@pytest.fixture
def sample(conn):
    typ=conn.execute('SELECT program_type_code FROM program_type ORDER BY 1 LIMIT 1').fetchone()['program_type_code']
    cat=conn.execute('SELECT category_code FROM survey_question_category ORDER BY 1 LIMIT 1').fetchone()['category_code']
    students=[r['student_no'] for r in conn.execute("SELECT student_no FROM student WHERE student_no NOT LIKE 'SI%' ORDER BY 1 LIMIT 20")]
    def program(name='quality test', at=AT):
        return conn.execute('INSERT INTO program(program_type_code,program_name,program_date) VALUES (%s,%s,%s) RETURNING program_id',
                            (typ,name,at.date())).fetchone()['program_id']
    pid=program()
    sid=conn.execute("INSERT INTO survey(program_id,survey_name,start_date,end_date) VALUES (%s,'quality test',%s,%s) RETURNING survey_id",(pid,AT.date(),AT.date())).fetchone()['survey_id']
    qs=[]
    for i in range(10):
        qs.append(conn.execute("INSERT INTO survey_question(survey_id,category_code,display_order,question_text,question_type,scale_max) VALUES (%s,%s,%s,'test','SCALE',5) RETURNING question_id",(sid,cat,i+1)).fetchone()['question_id'])
    def respond(i,scores,duration,completed=True,at=AT):
        rid=conn.execute('INSERT INTO survey_response(survey_id,student_no,responded_at) VALUES (%s,%s,%s) RETURNING response_id',(sid,students[i],at)).fetchone()['response_id']
        for q,score in zip(qs,scores):
            conn.execute('INSERT INTO survey_response_detail VALUES (%s,%s,%s,NULL)',(rid,q,score))
        if duration is not None:
            conn.execute('INSERT INTO analytics.survey_response_observation VALUES (%s,%s,NULL)',(rid,at-timedelta(seconds=duration)))
        if completed:
            conn.execute('UPDATE survey_response SET is_completed=true WHERE response_id=%s',(rid,))
        return rid
    old=respond(0,[1]*10,40,at=AT-timedelta(days=1))
    ids=[respond(0,[5]*10,5),respond(1,[5]*10,95),respond(2,NORMAL,65),respond(3,[4]*10,None)]
    draft=respond(0,[1]*3,1,False,AT+timedelta(days=1))
    return {'pid':pid,'sid':sid,'ids':ids,'old':old,'draft':draft,'respond':respond,'program':program,'students':students}


