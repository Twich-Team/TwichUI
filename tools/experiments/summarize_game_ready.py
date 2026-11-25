#!/usr/bin/env python3
"""Retain bounded review evidence; generated data files stay outside the repo."""
import argparse
import hashlib
import json
from pathlib import Path

from market_game_ready import canonical

METRICS=('cpu_ms','process_elapsed_seconds','experiment_current_initialization_ms','experiment_current_validation_ms',
 'experiment_compile_ms','experiment_execute_ms','experiment_worst_load_ms','experiment_loads','experiment_decodes',
 'experiment_validation_jobs','experiment_source_bytes','experiment_worst_part_source_bytes','experiment_distinct_items',
 'experiment_requested_legacy_buckets','experiment_authenticated','experiment_proof_hashes','experiment_bulk_authentications',
 'first_model_seconds','first_cpu_ms','ten_model_seconds','first_reference_model_seconds','ten_references_model_seconds',
 'experiment_visible_rows','experiment_visible_model_seconds','experiment_visible_cpu_ms','opportunities_settlement_model_seconds',
 'worst_callback_ms','callback_p95_ms','callback_p99_ms','callbacks','retained_delta_kib','sampled_peak_delta_kib','heap_drops',
 'explicit_gc_ms','warm_ms','warm_crafts','warm_record_calls','price_cache_entries','repeated_decodes','history_loads',
 'experiment_history_cpu_ms','experiment_history_compile_ms','experiment_history_execute_ms','experiment_history_validation_ms',
 'experiment_history_worst_load_ms','experiment_history_sampled_peak_delta_kib','experiment_history_retained_delta_kib',
 'experiment_warm_1000_prices_ms','experiment_history_loads','experiment_history_gc_ms',
 'crafts','record_calls','price_calls','view_requests','synchronous_full_lists','full_calculations',
 'engine_catalogBuilds','engine_calculated','engine_crafts','engine_fullInvalidations','engine_partialPublications',
 'scenario_cpu_ms','scenario_crafts','scenario_record_calls','scenario_full_lists','scenario_views')


def summarize(results,names,fixtures):
    output={'synthetic':True,'native_forever_tested':False,'campaigns':[],'fixtures':[]}
    economics={}
    for name in names:
        path=results/(name+'.json');r=json.loads(path.read_text())
        assert r['source_unchanged'] and r['economic_results_equal'],name
        meta={k:v for k,v in r.items()if k!='cases'};meta['fixture']=Path(r['fixture']).name
        meta['name']=name;meta['raw_report_sha256']=hashlib.sha256(path.read_bytes()).hexdigest();meta['cases']=[]
        for c in r['cases']:
            keep={k:v for k,v in c.items()if k not in ('layouts','metrics','samples')}
            keep['layouts']=[{k:v for k,v in l.items()if k!='descriptors'}for l in c['layouts']]
            if c['status']=='measured':
                key=(r['semantic_sha256'],c['recipes'],r.get('native_cohort',False),r.get('scenario','none'))
                hashes={s['result_sha256']for s in c['samples']}
                assert len(hashes)==1
                if key in economics:assert economics[key]==hashes,(name,key)
                economics[key]=hashes
                keep['metrics']={k:v for k,v in c['metrics'].items()if k in METRICS}
                keep['samples']=[{k:v for k,v in s.items()if k in METRICS or k in ('oracle_passed','result_sha256','semantic_fixture_sha256','experiment_recipe_sha256','warm_estimator_reused')}for s in c['samples']]
            assert c['status']!='failed',c
            meta['cases'].append(keep)
        output['campaigns'].append(meta)
    for folder in fixtures:
        r=json.loads((folder/'fixture.json').read_text())
        f={k:r[k]for k in ('records','unique_items','history_days','profile','semantic_sha256')};f['source_generation']=r['manifest']['generation_id'];f['layouts']=[]
        for l in r['layouts']:
            item={k:v for k,v in l.items()if k not in ('descriptors','generation_cpu_us')}
            item['descriptor_inventory_sha256']=hashlib.sha256(canonical(l['descriptors'])).hexdigest()
            item['mean_raw_bytes']=l['total_raw_bytes']/l['count'];item['mean_source_bytes']=l['total_source_bytes']/l['count']
            item['max_records']=max(d['record_count']for d in l['descriptors'])
            f['layouts'].append(item)
        output['fixtures'].append(f)
    output['economic_results_equal_across_campaigns']=True
    return output


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--results',type=Path,required=True);p.add_argument('--out',type=Path,required=True)
    p.add_argument('--campaigns',nargs='+',required=True);p.add_argument('--fixtures',type=Path,nargs='+',required=True)
    a=p.parse_args();r=summarize(a.results,a.campaigns,a.fixtures);a.out.parent.mkdir(parents=True,exist_ok=True);a.out.write_text(json.dumps(r,indent=2)+'\n')


if __name__=='__main__':main()
