#!/usr/bin/env python3
"""Disposable authenticated L2 server -> native Rust archive/publisher -> production Lua/UI.

Requires the pinned Market checkout and its built archive_smoke example. No real
credentials, databases, provider collection, game installation or SavedVariables.
"""
import argparse
from datetime import datetime, timedelta, timezone
import hashlib
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--market-root', type=Path, required=True)
    parser.add_argument('--rust-client', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    market = args.market_root.resolve()
    source = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=market, text=True).strip()
    if source != '6cef35797f28d562c7ee3db3aa290cfe876f418d':
        raise SystemExit('Use reviewed merged Market producer 6cef357; re-review other revisions explicitly')
    def digest(value):
        return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
    with tempfile.TemporaryDirectory(prefix='twichui-l3-e2e-') as directory:
        temp = Path(directory)
        os.environ.update(DATABASE_URL='sqlite:///' + str(temp / 'market_test.sqlite'),
                          APP_ORIGIN='https://l3-fixture.invalid', SYNC_CURSOR_SECRET='synthetic-l3-secret-' + 'a'*40,
                          BRIDGE_CONTRACT_ROOT=str(market / 'contracts/bridge/v1'))
        sys.path.insert(0, str(market / 'backend'))
        from market.app import app
        from market.db import Base, engine, Session
        from market.models import User, Market, PlayerMarketMapping
        from market.ingest import ingest
        from market.security import issue
        from market import archive_api, bridge_api
        import uvicorn
        # Checkpoint expiry is evaluated by the native UTC clock. Prices remain fixed expectations.
        at = datetime.now(timezone.utc)-timedelta(minutes=1)
        archive_api.now = lambda: at
        bridge_api.now = lambda: at
        Base.metadata.create_all(engine)
        def book(price, historical):
            rows = [{'id': i+1, 'item': {'id': 2589}, 'quantity': q, 'buyout': price*q} for i,q in enumerate([3,3,4])]
            if historical: rows += [{'id': 10, 'item': {'id': 2}, 'quantity': 10, 'buyout': 500}]
            rows += [{'id': 20, 'item': {'id': 2589, 'bonus_lists': [9]}, 'quantity': 1, 'buyout': 999},
                     {'id': 21, 'item': {'id': 123}, 'quantity': 2, 'bid': 50}]
            rows += [{'id': 1000+i, 'item': {'id': 10000+i}, 'quantity': 1, 'buyout': price} for i in range(125)]
            return json.dumps({'auctions': rows}).encode()
        with Session.begin() as db:
            user = User(username='synthetic_l3', password_hash='not-a-login', role='member');db.add(user);db.flush()
            token,_,_ = issue(db,user,'device');account=user.id
            m = Market(region='us', ruleset_id=1, house_id=114, source_kind='auctions', label='Synthetic L3 only', verified=True, enabled=True)
            db.add(m);db.flush();mid=m.id
            evidence=json.dumps({'region':'us','house_id':114,'ruleset':'Normal','faction':'Horde','upstream_receipt':'synthetic',
                                 'independent_observation':'synthetic','independent_source_url':'https://fixtures.example.invalid/synthetic'})
            db.add(PlayerMarketMapping(region='us',ruleset='Normal',faction='Horde',house_id=114,source_kind='auctions',transport_ruleset_id=1,
                                       confidence='verified',evidence=evidence,evidence_hash=hashlib.sha256(evidence.encode()).hexdigest(),verified_at=at))
            ingest(db,mid,book(100,True),request_key='l3-first',retrieved_at=at-timedelta(days=2),synthetic=True)
            ingest(db,mid,book(120,False),request_key='l3-current',retrieved_at=at,synthetic=True)
        sock=socket.socket();sock.bind(('127.0.0.1',0));port=sock.getsockname()[1]
        server=uvicorn.Server(uvicorn.Config(app,host='127.0.0.1',port=port,log_level='error',access_log=False))
        thread=threading.Thread(target=server.run,kwargs={'sockets':[sock]},daemon=True);thread.start()
        stage=temp/'staging';stage.mkdir(mode=0o700)
        env=os.environ.copy();env['TWICHUI_ARCHIVE_TEST_TOKEN']=token
        env['TWICHUI_ARCHIVE_TEST_ALGORITHM']='twichui-pricing-v1'
        env['NO_PROXY']='127.0.0.1,localhost'
        env['no_proxy']='127.0.0.1,localhost'
        requests=[]
        @app.middleware('http')
        async def measure(request,call_next):
            response=await call_next(request);requests.append([request.method,request.url.path,response.status_code]);return response
        def native(action,request=None):
            command=[str(args.rust_client.resolve()),f'http://127.0.0.1:{port}',str(account),str(mid),str(temp/'archive.sqlite'),str(stage),action]
            if request: command.append(str(request))
            result=subprocess.run(command,env=env,capture_output=True,text=True,timeout=180)
            if result.returncode: raise RuntimeError('native acceptance failed: '+result.stderr+'; test request statuses='+str(requests))
            return json.loads(result.stdout)
        try:
            until=time.monotonic()+10
            while not server.started:
                if not thread.is_alive() or time.monotonic()>until: raise RuntimeError('test server startup failed')
                time.sleep(.02)
            first=native('step');assert first['pending'] and not first['complete']
            archive=native('sync');assert archive['complete'] and not archive['pending']
            h=archive['header'];assert h['total_records']==257 and h['total_observations']==2
            at+=timedelta(seconds=1)
            with Session.begin() as db: ingest(db,mid,book(140,False),request_key='l3-update',retrieved_at=at,synthetic=True)
            interrupted=native('step');assert interrupted['header']['checkpoint_id']==h['checkpoint_id']
            archive=native('sync');h=archive['header'];assert h['transfer_observations']==1 and h['total_observations']==3
            pairs=[(2,{'id':2}),(123,{'id':123}),(2589,{'id':2589})]+[(10000+i,{'id':10000+i}) for i in range(97)]
            selection=dict(format='twichui-market-selection',contract_version=1,expected_schema_version=3,issuer_id=h['issuer_id'],market=h['market'],scope_type='explicit_variants',
                           variants=[dict(item_id=i,variant_key=digest(v)) for i,v in pairs],history_from_day=(at.date()-timedelta(days=59)).isoformat(),history_through_day=at.date().isoformat(),
                           pricing_algorithm=h['pricing_algorithm'],history_basis=h['history_basis'],profile='daily_research_v1')
            request=temp/'selection.json';request.write_text(json.dumps(selection))
            exported=native('export',request);artifact=Path(exported['lua_path'])
            generation=json.loads(Path(exported['generation_path']).read_text())
            http=urllib.request.Request(f'http://127.0.0.1:{port}/api/v1/archive/markets/{mid}/scoped?checkpoint='+h['checkpoint_id'],
                                       data=json.dumps(selection).encode(),headers={'Authorization':'Bearer '+token,'Content-Type':'application/json'})
            with urllib.request.build_opener(urllib.request.ProxyHandler({})).open(http,timeout=60) as response:
                assert json.load(response)==generation,'server and Rust generation differ'
            assert generation['record_count']==100 and not generation['coverage']['generation_complete']
            assert sum(d['state']=='no_observation' for d in generation['scope']['date_coverage'])==58
            env['L3_MARKET_ARTIFACT']=str(artifact)
            lua=subprocess.run(['lua5.1','-e','require("bit"); ROOT="../!!!TwichUI/"; REPO="../"; TESTS="./"','test_workshop_auction_market_scoped.lua'],cwd=ROOT/'tests',env=env,capture_output=True,text=True,timeout=180)
            if lua.returncode: raise RuntimeError('production reader/UI failed: '+lua.stdout+lua.stderr)
            report=dict(result='PASS',origin='synthetic',producer_revision=source,consumer_revision=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
                        consumer_source_sha256={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in [ROOT/'TwichUI_Workshop'/n for n in ('Bridge.lua','BridgeCodec.lua','BridgeSchema.lua','BridgeValidate.lua','ServerMarket.lua','Style.lua','auction/ViewMarket.lua')]},
                        source_checkpoint=h['checkpoint_id'],native_sha256=hashlib.sha256(args.rust_client.read_bytes()).hexdigest(),variants=129,selected_variants=100,canonical_bytes=len(json.dumps(generation,sort_keys=True,separators=(',',':')).encode()),
                        lua_bytes=artifact.stat().st_size,lua_sha256=hashlib.sha256(artifact.read_bytes()).hexdigest(),generation=generation['generation_id'],fixture_manifest_sha256=hashlib.sha256((market/'contracts/bridge/scoped-l1/SHA256SUMS.json').read_bytes()).hexdigest(),
                        complete_bootstrap=True,resumed_bootstrap=True,incremental_observations=1,server_rust_equal=True,lua_production_reader_and_UI=lua.stdout.strip(),
                        expected=dict(prices=[100,140],market_value=100,historical_value=None,bid_supply=2,historical_current_state='absent',missing_dates=58),real_client=False,production_access=False)
            args.report.parent.mkdir(parents=True,exist_ok=True);args.report.write_text(json.dumps(report,indent=2)+'\n')
            print(json.dumps(report,indent=2))
        finally:
            server.should_exit=True;thread.join(timeout=10);sock.close();engine.dispose()

if __name__=='__main__':main()
