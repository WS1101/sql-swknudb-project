"""Deterministic, opt-in synthetic seed using existing business tables and triggers.

Run only on a separate database containing mission 2 schema (no reset required).
No DELETE/TRUNCATE, no modification of existing responses. Entire seed is atomic.
"""
from __future__ import annotations

import argparse
import math
import random
from datetime import datetime, timedelta, timezone
from pathlib import Path

from analysis.db import connect

SEED_VERSION = 'survey-insight-v1-20261123'
UTC = timezone.utc


def seed(conn, *, seed_number=20261123, students=360, programs=24, with_participation=False):
    rng = random.Random(seed_number)
    if students < 300 or programs < 20:
        raise ValueError('시연 데이터는 학생 300명, 프로그램 20개 이상이어야 합니다.')
    conn.execute("SELECT pg_advisory_xact_lock(706031)")
    if conn.execute('SELECT count(*) AS n FROM analytics.survey_demo_program').fetchone()['n']:
        raise RuntimeError('합성 프로그램이 이미 있습니다. 재실행은 별도 빈 시연 DB를 사용하세요.')
    if with_participation:
        conn.execute((Path(__file__).resolve().parents[1]/'seed/09_survey_participation_demo.sql').read_text(encoding='utf8'))
    conn.execute("INSERT INTO college(college_code,college_name) VALUES ('SI_C','합성 시연 대학')")
    conn.execute("INSERT INTO campus(campus_code,campus_name) VALUES ('SI_P','합성 시연 캠퍼스')")
    for k in range(4):
        conn.execute('''INSERT INTO department(dept_code,dept_name,college_code,campus_code,track_type)
            VALUES (%s,%s,'SI_C','SI_P','ENG')''', (f'SI_D{k}', f'합성 학과 {k+1}'))
    conn.execute("INSERT INTO program_type VALUES ('SI_DEMO','Survey Insight 합성 시연',true)")
    cats = [('SI_TEACH','강사'),('SI_CONTENT','내용'),('SI_OPERATION','운영'),('SI_TIME','시간')]
    for code, name in cats:
        conn.execute('INSERT INTO survey_question_category(category_code,category_name) VALUES (%s,%s)', (code,name))
    for i in range(students):
        no = f'SI{i:05}'
        conn.execute('''INSERT INTO app_user(user_id,login_id,password_hash,user_name,user_type,is_active)
            VALUES (%s,%s,'!disabled-synthetic-account',%s,'STUDENT',false)''', (no,no,f'가상학생 {i+1}'))
        conn.execute('''INSERT INTO student(student_no,dept_code,grade,enrollment_status,admission_type,admission_date)
            VALUES (%s,%s,%s,'ENROLLED','NEW','2023-03-01')''', (no,f'SI_D{i%4}',1+i%4))
    base = datetime(2025, 9, 1, 3, tzinfo=UTC)
    ps = []
    for j in range(programs):
        at = base + timedelta(days=18*j)
        pid = conn.execute('''INSERT INTO program(program_type_code,program_name,program_date,capacity)
            VALUES ('SI_DEMO',%s,%s,%s) RETURNING program_id''', (f'[합성] SW 역량 프로그램 {j+1:02}',at.date(),students)).fetchone()['program_id']
        conn.execute('INSERT INTO analytics.survey_demo_program VALUES (%s,%s)',(pid,SEED_VERSION))
        sid = conn.execute('''INSERT INTO survey(program_id,survey_name,start_date,end_date,status)
            VALUES (%s,%s,%s,%s,'CLOSED') RETURNING survey_id''', (pid,f'[합성] 만족도 {j+1:02}',at.date(),(at+timedelta(days=7)).date())).fetchone()['survey_id']
        qs = []
        for k in range(8):
            code, name = cats[k//2]
            qid=conn.execute('''INSERT INTO survey_question(survey_id,category_code,display_order,question_text,question_type,scale_max)
                VALUES (%s,%s,%s,%s,'SCALE',5) RETURNING question_id''', (sid,code,k+1,f'{name} 관련 만족도 문항 {k%2+1}')).fetchone()['question_id']
            qs.append(qid)
        ps.append((pid,sid,at,qs))
    # Participation depends probabilistically on prior content satisfaction, plus individual propensity.
    # Survey response behavior is a separate random variable; no target aggregate is enforced.
    scenarios = ['genuine_all5','fast_all5','fast_low','varied','high','low','incomplete','legacy']
    counts = {s:0 for s in scenarios}
    for i in range(students):
        no=f'SI{i:05}'
        propensity=rng.uniform(-1,1)
        prior_content=3.0
        for j,(pid,sid,at,qs) in enumerate(ps):
            offered=rng.random()<.78
            if not offered:
                continue
            if with_participation:
                conn.execute('''INSERT INTO analytics.survey_demo_opportunity(student_no,program_id,offered_at,scheduled_at)
                    VALUES (%s,%s,%s,%s)''',(no,pid,at-timedelta(days=7),at))
            probability=1/(1+math.exp(-(-.5+propensity+.55*(prior_content-3))))
            if rng.random()>=probability:
                continue
            if with_participation:
                conn.execute('''INSERT INTO analytics.survey_demo_attendance(student_no,program_id,attended_at)
                    VALUES (%s,%s,%s)''',(no,pid,at))
            if rng.random()<.12:  # attendance without survey is allowed
                continue
            scenario=rng.choices(scenarios,[12,12,7,35,10,8,6,10])[0]
            counts[scenario]+=1
            latent=rng.uniform(1.7,4.8)
            scores=[max(1,min(5,round(rng.gauss(latent,.85)))) for _ in qs]
            duration=rng.uniform(35,150)
            if scenario in ('genuine_all5','fast_all5'): scores=[5]*8
            if scenario=='fast_low': scores=[rng.choice([1,2])]*8
            if scenario.startswith('fast'): duration=rng.uniform(2,7)
            if scenario=='high': scores=[rng.choice([4,5]) for _ in qs]
            if scenario=='low': scores=[rng.choice([1,2,3]) for _ in qs]
            submitted=at+timedelta(hours=2,minutes=rng.randrange(120))
            rid=conn.execute('''INSERT INTO survey_response(survey_id,student_no,responded_at)
                VALUES (%s,%s,%s) RETURNING response_id''',(sid,no,submitted)).fetchone()['response_id']
            for q,score in zip(qs[:3] if scenario=='incomplete' else qs,scores):
                conn.execute('INSERT INTO survey_response_detail(response_id,question_id,score) VALUES (%s,%s,%s)',(rid,q,score))
            conn.execute('''INSERT INTO analytics.survey_response_observation(response_id,started_at,synthetic_scenario)
                VALUES (%s,%s,%s)''',(rid,None if scenario=='legacy' else submitted-timedelta(seconds=duration),scenario))
            if scenario!='incomplete':
                conn.execute('UPDATE survey_response SET is_completed=true WHERE response_id=%s',(rid,))
                prior_content=sum(scores[2:4])/2
    end=base+timedelta(days=18*(programs-1),hours=23)
    if with_participation:
        conn.execute('''INSERT INTO analytics.participation_coverage VALUES
            ('synthetic',%s,%s,'합성 생성 구간: 모든 가상 출석/기회 생성 완료')''',(base-timedelta(days=7),end))
    return {'students':students,'programs':programs,'scenarios':counts,
            'participation_seeded':with_participation,'observed_through':end.isoformat() if with_participation else None}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--allow-synthetic',action='store_true',help='별도 시연 DB에 합성 데이터 삽입을 명시적으로 허용')
    parser.add_argument('--with-participation',action='store_true',help='06 적용된 별도 시연 DB에만 선택적 출석 시드 추가')
    args=parser.parse_args()
    if not args.allow_synthetic:
        parser.error('--allow-synthetic 이 필요합니다. 기존 운영 DB 대신 별도 시연 DB를 권장합니다.')
    with connect(readonly=False) as conn:
        db=conn.info.dbname.lower()
        if any(x in db for x in ('production','prod')):
            raise RuntimeError('운영 DB명에서는 합성 시드를 실행하지 않습니다.')
        print(seed(conn,with_participation=args.with_participation))


if __name__=='__main__':
    main()
