#!/usr/bin/env python3
"""Compare untouched and proposed actual native Full suites without waiving failures."""
from collections import Counter
from pathlib import Path
import hashlib,json,re
ROOT=Path(__file__).resolve().parents[2]
DOC=ROOT/'docs/map-compaction/private-tests'

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def parse(path):
 text=path.read_text();cases=[];occurrences=Counter()
 for match in re.finditer(r'^\[BRAINROT_TEST\]\[(PASS|FAIL)\] ([^\n]+)',text,re.M):
  name=match.group(2);occurrences[name]+=1
  following=text[match.end():].lstrip('\n').splitlines()
  cases.append({'name':name,'occurrence':occurrences[name],'status':match.group(1),'failureMessage':following[0] if following and match.group(1)=='FAIL' else None})
 summary=re.findall(r'^\[BRAINROT_TEST_SUMMARY\] files=(\d+) fileErrors=(\d+) tests=(\d+) passed=(\d+) failed=(\d+)',text,re.M)
 assert len(summary)==1,'Expected one completed native test summary'
 counts=dict(zip(['files','fileErrors','tests','passed','failed'],map(int,summary[0])))
 assert len(cases)==counts['tests'] and sum(c['status']=='PASS' for c in cases)==counts['passed'] and sum(c['status']=='FAIL' for c in cases)==counts['failed'],'Native case count mismatch'
 guard=re.findall(r'^\[COMPACT_PRIVATE_SOURCE_GUARD\] (.+)$',text,re.M)
 result=re.findall(r'^\[BRAINROT_TEST_RESULT\] (PASS|FAIL)$',text,re.M)
 assert len(guard)==1 and len(result)==1,'Native source proof/result marker missing'
 return {'log':str(path.relative_to(ROOT)),'sha256':sha(path),'summary':counts,'sourceGuard':guard[0],'suiteResult':result[0],'cases':cases,'duplicateNameOccurrences':{n:v for n,v in occurrences.items() if v>1}}

def reason(name):
 if name.startswith('BaseIncomePlaqueSystem.spec'):return {'observedFixtureAssumption':'The historical fixture expects SmoothPlastic; captured pre-compaction source already applies the accepted Glacier saved-stud policy.','source':'docs/map-compaction/live-sources/ServerScriptService/Server/Tests/BaseIncomePlaqueSystem/spec.lua','line':305}
 if name.startswith('BaseSignSystem.spec'):return {'observedFixtureAssumption':'The fixture asserts that no imported username-sign template exists, but both private copies retain the actual imported asset library.','source':'docs/map-compaction/live-sources/ServerScriptService/Server/Tests/BaseSignSystem/spec.lua','line':19}
 if name.startswith('BrainrotSalePointSystem.spec'):return {'observedFixtureAssumption':'The first fixture asserts that no SellSign source exists; it leaves its private SellStall when setup aborts, and subsequent cases reject an existing sale point.','source':'docs/map-compaction/live-sources/ServerScriptService/Server/Tests/BrainrotSalePointSystem/spec.lua','line':36}
 rows={'Camouflage.spec':('The case expects property/descendant signal effects immediately, without yielding before the failing assertion.','Camouflage',189),'CartAssemblyObservation.spec':('The case expects a physical-property observer callback immediately after changing Anchored.','CartAssemblyObservation',87),'CartInputController.spec':('The case expects BindableEvent listeners to update local counters/values immediately after the input setter.','CartInputController',98),'IncomePlaqueController.spec':('The case expects attribute-change listeners to update label text immediately after setting the snapshot.','IncomePlaqueController',155),'LocalCartResetState.spec':('The case expects BindableEvent listeners to update transitionCount immediately after setters.','LocalCartResetState',43)}
 for prefix,(observation,spec,line) in rows.items():
  if name.startswith(prefix):return {'observedFixtureAssumption':observation,'source':f'docs/map-compaction/live-sources/ServerScriptService/Server/Tests/{spec}/spec.lua','line':line,'causalLimit':'This source observation is an inference; the comparison proves pre-existence in the same native task environment, not the engine scheduling cause or ordinary Play behavior.'}
 return {'observedFixtureAssumption':'No mechanism asserted; inspect the exact before/after failure messages.'}

before=parse(DOC/'baseline/BaselineFull.native.log');after=parse(DOC/'Full.native.log')
key=lambda c:(c['name'],c['occurrence'])
bm={key(c):c for c in before['cases']};am={key(c):c for c in after['cases']}
assert bm.keys()==am.keys(),'Before/after test inventories differ'
changes=[{'name':n,'occurrence':i,'before':bm[(n,i)]['status'],'after':am[(n,i)]['status']} for n,i in bm if bm[(n,i)]['status']!=am[(n,i)]['status']]
failures=[]
for k,a in am.items():
 if a['status']!='FAIL':continue
 b=bm[k];same=b['status']=='FAIL' and a['failureMessage']==b['failureMessage']
 failures.append({'name':a['name'],'occurrence':a['occurrence'],'beforeFailed':b['status']=='FAIL','afterFailed':True,'sameFirstFailureMessage':same,'beforeMessage':b['failureMessage'],'afterMessage':a['failureMessage'],'classification':'ConfirmedPreexistingInMatchedPrivateBaseline' if same else 'NeedsReview',**reason(a['name']),'actualAssertionLines':[int(v) for v in re.findall(r'\.spec:(\d+)',a['failureMessage'] or '')]})
identical=not changes
same_failures=all(f['sameFirstFailureMessage'] for f in failures)
result={'schemaVersion':1,'status':'ActualMatchedPrivateComparisonComplete','before':{k:v for k,v in before.items() if k!='cases'},'after':{k:v for k,v in after.items() if k!='cases'},'comparedCaseCount':len(bm),'caseOrderIdentical':[key(c) for c in before['cases']]==[key(c) for c in after['cases']],'caseStatusesIdentical':identical,'caseStatusChanges':changes,'confirmedPreexistingFailures':sum(f['sameFirstFailureMessage'] for f in failures),'failures':failures,'baselineSourceSubstitutions':0,'proposedSourceSubstitutions':5,'baselineExactSourceCount':356,'proposedExactSourceCount':357,'retainedAssetInventoryIdentical':1163,'assetSerializedSHA256':'de5c12c6b96270f26da78800910dbb233323ed7315d60e272f6eb89fd81c2725','testsOrAssertionsModified':False,'suiteAcceptancePassed':before['suiteResult']=='PASS' and after['suiteResult']=='PASS','ordinaryGameplayAcceptancePassed':False,'interpretation':'All observed failures are confirmed pre-existing in the matched native private baseline; both suites remain failed.' if identical and same_failures else 'Comparison contains differences; review individual cases before any regression conclusion.','originalDEVSourceOrWorldWrites':0,'nativePrivateProcessExitCode':0,'processExitMeaning':'Studio native task exited 0 despite failed tests; explicit summary/result governs status.'}
(DOC/'FullBeforeAfterComparison.json').write_text(json.dumps(result,indent=2)+'\n')
counts=before['summary'];ac=after['summary']
md=['# Actual native Full comparison','',f"The exact-original private copy ran **{counts['tests']:,} tests: {counts['passed']:,} passed, {counts['failed']} failed** across {counts['files']} files, with {counts['fileErrors']} file errors. The proposed copy ran **{ac['tests']:,} tests: {ac['passed']:,} passed, {ac['failed']} failed**. All test source and assertions were retained unchanged.",'','| Source set | Exact native source guard | Tests | Passed | Failed |','| --- | ---: | ---: | ---: | ---: |',f"| Captured baseline, zero substitutions | 356 | {counts['tests']} | {counts['passed']} | {counts['failed']} |",f"| Five proposals plus new Utility | 357 | {ac['tests']} | {ac['passed']} | {ac['failed']} |",'']
md.append(f"All {len(bm):,} case statuses and {len(failures)} first failure messages are identical. This includes the seven failures from the [Relevant comparison](RelevantBeforeAfterComparison.md). One duplicated test name is compared by occurrence so neither result is discarded." if identical and same_failures else 'There are comparison differences; consult the JSON before drawing a regression conclusion.')
md+=['','The existing fixture failures involve the prior saved-stud material expectation, retained imported sign assets, and seven immediate event/label-update assertions. Source inspection supports the immediate-callback assumption for those seven cases; their exact scheduling cause and ordinary Play behavior have not been proven by this task. Each failure and its source observation are recorded in the JSON.','','[Comparison JSON](FullBeforeAfterComparison.json) records all failures and both raw log hashes. Raw logs: [baseline](baseline/BaselineFull.native.log), [proposed](Full.native.log). [Baseline preparation](baseline/PrivateBaselineFullPreparation.json) proves all 356 original source bytes and the identical 1,163-instance asset subtree before native execution.','','Both suites remain **FAIL**. This comparison establishes whether any new case failures appear under identical private fixtures. It does not waive full-suite acceptance or establish ordinary gameplay, mobile, performance or live compaction acceptance. Main DEV sources/world and the original saved place input were untouched.','']
(DOC/'FullBeforeAfterComparison.md').write_text('\n'.join(md))
print(json.dumps({'casesCompared':len(bm),'baseline':counts,'proposed':ac,'identicalStatuses':identical,'sameFailureMessages':same_failures,'caseStatusChanges':changes,'suiteAcceptancePassed':result['suiteAcceptancePassed']}))
