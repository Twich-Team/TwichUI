-- Small deterministic workload assertions; timings are deliberately not gates.
-- Existing market/crafting groups discover this through test_workshop_market*.lua.
local savedArg=arg
arg={'opportunities','session','20','2'}
AUDIT_QUIET=true
local out=dofile(REPO..'tests/bench_market_opportunities.lua')
arg=savedArg;AUDIT_QUIET=nil
assert(out.priced==20 and out.unpriced==0,'synthetic known prices failed to settle')
assert(out.loads==33 and out.decodes==33 and out.repeated_decodes==0,'ordinary pricing repeated partition work')
assert(out.warm_record_calls==0 and out.warm_estimator_reused,'resolved references/memo lost between compatible draws')
assert(out.warm_crafts==20 and out.crafts==20*out.full_calculations,'unexpected full-list accounting')
assert(out.full_calculations<70 and out.record_calls<=2*out.price_cache_entries,'retry/redraw amplification exceeded characterization bound')
assert(out.price_cache_entries==53 and out.price_cache_entries<=8192 and out.decoded_partitions<=1,'cache capacity/identity drift')
assert(out.memo_hits>out.memo_asked,'shared material questions bypassed memoization')
print('PASSED synthetic Opportunities completion, compact-cache reuse, shared memo hits and bounded retries; timing is not a gate')
