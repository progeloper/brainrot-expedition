#!/usr/bin/env python3
"""Compare actual native Relevant logs, preserving failed-suite status."""
from pathlib import Path
import re,json,hashlib
ROOT=Path(__file__).resolve().parents[2];DOC=ROOT/'docs/map-compaction/private-tests'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def parse(path):
 text=path.read_text();cases=[]
 for match in re.finditer(r'^\[BRAINROT_TEST\]\[(PASS|FAIL)\] ([^\n]+)',text,re.M):
  end=text.find('\n',match.end());nextline=text[end+1:].splitlines()[0]if end>=0 else ''
  cases.append({'name':match.group(2),'status':match.group(1),'failureMessage':nextline if match.group(1)=='FAIL'else None})
 summary=re.findall(r'^\[BRAINROT_TEST_SUMMARY\] files=(\d+) fileErrors=(\d+) tests=(\d+) passed=(\d+) failed=(\d+)',text,re.M);assert len(summary)==1
 counts=dict(zip(['files','fileErrors','tests','passed','failed'],map(int,summary[0])))
 assert len(cases)==counts['tests']and sum(c['status']=='PASS'for c in cases)==counts['passed']and sum(c['status']=='FAIL'for c in cases)==counts['failed']
 assert len({c['name']for c in cases})==len(cases),'Duplicate case name requires ordered comparison'
 guard=re.findall(r'^\[COMPACT_PRIVATE_SOURCE_GUARD\] (.+)$',text,re.M);assert len(guard)==1
 results=re.findall(r'^\[BRAINROT_TEST_RESULT\] (PASS|FAIL)$',text,re.M);assert len(results)==1
 return {'log':str(path.relative_to(ROOT)),'sha256':sha(path),'summary':counts,'sourceGuard':guard[0],'suiteResult':results[0],'cases':cases}
before=parse(DOC/'baseline/BaselineRelevant.native.log');after=parse(DOC/'Relevant.native.log')
bm,am={c['name']:c for c in before['cases']},{c['name']:c for c in after['cases']};assert bm.keys()==am.keys()
changes=[{'name':n,'before':bm[n]['status'],'after':am[n]['status']}for n in bm if bm[n]['status']!=am[n]['status']]
failures=[]
for name,a in am.items():
 if a['status']!='FAIL':continue
 b=bm[name];same=b['status']=='FAIL'and a['failureMessage']==b['failureMessage']
 if name.startswith('BaseIncomePlaqueSystem.spec'):reason='Current saved-stud policy already uses Glacier; historical fixture still expects SmoothPlastic.'
 elif name.startswith('BaseSignSystem.spec'):reason='Fixture requires absent imported username-sign template; retained actual asset library already contains it.'
 else:reason='Sale fixture requires absent SellSign template; first setup assertion leaves its private SellStall allocated, so subsequent cases reject an existing sale point.'
 failures.append({'name':name,'beforeFailed':b['status']=='FAIL','afterFailed':True,'sameFirstFailureMessage':same,'beforeMessage':b['failureMessage'],'afterMessage':a['failureMessage'],'classification':'ConfirmedPreexistingInMatchedPrivateBaseline'if same else'NeedsReview','reason':reason})
assert not changes and all(f['sameFirstFailureMessage']for f in failures)
result={'schemaVersion':1,'status':'ActualMatchedPrivateComparisonComplete','before':{k:v for k,v in before.items()if k!='cases'},'after':{k:v for k,v in after.items()if k!='cases'},'comparedCaseCount':len(bm),'caseStatusesIdentical':not changes,'caseStatusChanges':changes,'confirmedPreexistingFailures':len(failures),'failures':failures,'baselineSourceSubstitutions':0,'proposedSourceSubstitutions':5,'baselineExactSourceCount':356,'proposedExactSourceCount':357,'retainedAssetInventoryIdentical':1163,'assetSerializedSHA256':'de5c12c6b96270f26da78800910dbb233323ed7315d60e272f6eb89fd81c2725','testsOrAssertionsModified':False,'suiteAcceptancePassed':False,'ordinaryGameplayAcceptancePassed':False,'interpretation':'No new Relevant case failures were observed in the matched private native comparison. Both unchanged suites remain failed; this is not a full acceptance waiver.','originalDEVSourceOrWorldWrites':0,'nativePrivateProcessExitCode':0,'processExitMeaning':'Studio native task exited0 despite failing tests; explicit test summary/result governs status.'}
(DOC/'RelevantBeforeAfterComparison.json').write_text(json.dumps(result,indent=2)+'\n')
(DOC/'RelevantBeforeAfterComparison.md').write_text('''# Actual native Relevant comparison

The proposed and exact-baseline private copies both ran **212 tests:205 passed,7 failed** across20 files, with0 file errors. All212 case statuses and the seven first failure messages are identical. No test source or assertion was changed.

| Source set | Exact native source guard | Tests | Passed | Failed |
| --- | ---: | ---: | ---: | ---: |
| Captured baseline, zero substitutions |356|212|205|7|
| Five proposals plus new Utility |357|212|205|7|

One failure is the old BaseIncome fixture expecting SmoothPlastic after the current saved-stud owner already changed to Glacier. Three BaseSign failures require absent imported username-sign templates. Three SalePoint failures require absent SellSign/SellStall fixtures; the first setup assertion leaves its private stall behind, causing the next two guards. The actual asset library is retained identically in both copies.

[Comparison JSON](RelevantBeforeAfterComparison.json) records each exact case/message and both log hashes. Raw logs: [baseline](baseline/BaselineRelevant.native.log), [proposed](Relevant.native.log). [Baseline preparation](baseline/PrivateBaselinePreparation.json) proves all356 original source bytes and unchanged asset subtree before native execution.

Both suites remain **FAIL**. The comparison establishes no new Relevant case failure under these identical private fixtures; it does not prove full-suite, ordinary gameplay, mobile or performance acceptance. Main DEV sources/world and the original saved input were untouched.
'''.replace('tests:205','tests: 205').replace('passed,7','passed, 7').replace('across20','across 20').replace('with0','with 0').replace('All212','All 212').replace('all356','all 356'))
print(json.dumps({'casesCompared':len(bm),'baseline':before['summary'],'proposed':after['summary'],'identicalStatuses':not changes,'sameFailureMessages':all(f['sameFirstFailureMessage']for f in failures),'suiteAcceptancePassed':False}))
